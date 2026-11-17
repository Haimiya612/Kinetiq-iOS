import Foundation
import SwiftUI

/// A bounded, private diagnostic ledger. Store only stable error categories and
/// deliberately filtered display labels: never stream URLs, query strings,
/// cookies, request headers, raw exception messages, or Discord information.
enum KinetiqRecoveryPhase: String, Codable, CaseIterable, Identifiable {
    case resolution = "Source resolution"
    case playback = "Video playback"
    case subtitles = "Subtitles"
    case offline = "Offline media"

    var id: String { rawValue }
}

enum KinetiqRecoveryOutcome: String, Codable {
    case failed = "Failure"
    case retrying = "Retrying"
    case switching = "Switching server"
    case recovered = "Recovered"
}

struct KinetiqRecoveryEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var phase: KinetiqRecoveryPhase
    var outcome: KinetiqRecoveryOutcome
    var code: String
    var source: String
    var episode: String
    var httpStatus: Int?
    var occurrences: Int

    var recommendation: String {
        switch httpStatus {
        case .some(401), .some(403):
            return "This provider rejected the media request. Try another server that provides the same episode; do not change your account credentials here."
        case .some(404), .some(410):
            return "The media address has expired or was removed. Refresh the episode and choose another resolved server."
        case .some(429):
            return "The provider is rate-limiting requests. Wait before manually retrying."
        case let .some(status) where (500...599).contains(status):
            return "The upstream provider returned a server failure. Retry later or choose another verified server."
        default:
            switch phase {
            case .resolution:
                return "The source could not resolve this episode. Refresh the source, then copy diagnostics if it still fails."
            case .playback:
                return "Try one manual retry or a different server for this exact episode. Check quality and subtitles separately."
            case .subtitles:
                return "Retry the selected caption track or choose an embedded alternative. Your selection should stay saved."
            case .offline:
                return "Use Travel Vault to verify the local file before departure. Do not delete the original."
            }
        }
    }

    var safeSummary: String {
        "\(date.formatted(date: .abbreviated, time: .shortened)) · \(phase.rawValue) · \(outcome.rawValue) · \(code) · \(source) · Ep \(episode)" +
            (httpStatus.map { " · HTTP \($0)" } ?? "") +
            (occurrences > 1 ? " · repeated \(occurrences)×" : "")
    }
}

enum KinetiqRecoverySanitizer {
    /// Preserve Unicode letters (including Japanese), numerals and modest
    /// punctuation. Remove URL separators, control characters and query syntax.
    static func label(_ value: String, limit: Int = 72) -> String {
        // Entirely discard input resembling a URL or key/value token, rather
        // than merely stripping punctuation and accidentally retaining secrets.
        if value.contains("://") || value.contains("?") || value.contains("=") ||
            value.contains("@") || value.contains("#") || value.contains("\n") ||
            value.contains("\r") {
            return "Hidden source"
        }
        let truncated = String(value.prefix(limit))
        let filtered = truncated.replacingOccurrences(
            of: "[^\\p{L}\\p{N} _().-]", with: " ", options: .regularExpression
        )
        let collapsed = filtered.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? "Unknown" : collapsed
    }

    static func code(_ value: String) -> String {
        let normalized = String(value.uppercased().filter {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
        }.prefix(60))
        return normalized.isEmpty ? "UNCLASSIFIED_FAILURE" : normalized
    }
}

@MainActor
final class KinetiqRecoveryStore: ObservableObject {
    static let shared = KinetiqRecoveryStore()

    @Published private(set) var events: [KinetiqRecoveryEvent] = []

    private let defaults: UserDefaults
    private let key = "kinetiq.recovery.events.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: key),
           bytes.count <= 300_000,
           let decoded = try? JSONDecoder().decode([KinetiqRecoveryEvent].self, from: bytes) {
            events = Array(decoded.prefix(200)).map { event in
                KinetiqRecoveryEvent(
                    id: event.id, date: event.date, phase: event.phase,
                    outcome: event.outcome,
                    code: KinetiqRecoverySanitizer.code(event.code),
                    source: KinetiqRecoverySanitizer.label(event.source),
                    episode: KinetiqRecoverySanitizer.label(event.episode, limit: 40),
                    httpStatus: event.httpStatus.flatMap { (100...599).contains($0) ? $0 : nil },
                    occurrences: min(max(event.occurrences, 1), 99)
                )
            }
        }
    }

    func record(
        phase: KinetiqRecoveryPhase,
        outcome: KinetiqRecoveryOutcome,
        code: String,
        source: String,
        episode: String,
        httpStatus: Int? = nil,
        now: Date = Date()
    ) {
        let safeCode = KinetiqRecoverySanitizer.code(code)
        let safeSource = KinetiqRecoverySanitizer.label(source)
        let safeEpisode = KinetiqRecoverySanitizer.label(episode, limit: 40)
        let status = httpStatus.flatMap { (100...599).contains($0) ? $0 : nil }

        if !events.isEmpty && events[0].phase == phase &&
            events[0].outcome == outcome && events[0].code == safeCode &&
            events[0].source == safeSource && events[0].episode == safeEpisode &&
            events[0].httpStatus == status &&
            now.timeIntervalSince(events[0].date) >= 0 &&
            now.timeIntervalSince(events[0].date) < 120 {
            events[0].date = now
            events[0].occurrences = min(99, events[0].occurrences + 1)
        } else {
            events.insert(KinetiqRecoveryEvent(id: UUID(), date: now,
                phase: phase, outcome: outcome, code: safeCode,
                source: safeSource, episode: safeEpisode,
                httpStatus: status, occurrences: 1), at: 0)
            if events.count > 200 { events.removeLast(events.count - 200) }
        }
        save()
    }

    func clear() {
        events.removeAll()
        defaults.removeObject(forKey: key)
    }

    var redactedReport: String {
        (["Kinetiq Recovery Center · private, sanitized history",
          "Last 200 events; no stream addresses or request secrets are saved."] +
         events.map { $0.safeSummary + "\nNext: " + $0.recommendation })
            .joined(separator: "\n\n")
    }

    private func save() {
        guard let bytes = try? JSONEncoder().encode(events) else { return }
        defaults.set(bytes, forKey: key)
    }
}

@MainActor
struct KinetiqRecoveryCenterView: View {
    @StateObject private var store = KinetiqRecoveryStore.shared
    @State private var filter: KinetiqRecoveryPhase?
    @State private var confirmClear = false

    private var visible: [KinetiqRecoveryEvent] {
        guard let filter else { return store.events }
        return store.events.filter { $0.phase == filter }
    }

    var body: some View {
        List {
            Section {
                Label("Private recovery history", systemImage: "cross.case.fill")
                    .font(.headline)
                Text("Only categorized errors and safe source labels are kept. Playback URLs, authentication, cookies and Discord data are never recorded here.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Recorded events", value: "\(store.events.count)")
                LabeledContent("Failure records", value: "\(store.events.filter { $0.outcome == .failed }.count)")
                ShareLink(item: store.redactedReport) {
                    Label("Share sanitized report", systemImage: "square.and.arrow.up")
                }
                .disabled(store.events.isEmpty)
            }

            Section("Filter") {
                Picker("Recovery category", selection: $filter) {
                    Text("All categories").tag(nil as KinetiqRecoveryPhase?)
                    ForEach(KinetiqRecoveryPhase.allCases) { phase in
                        Text(phase.rawValue).tag(Optional(phase))
                    }
                }
            }

            Section("Events") {
                if visible.isEmpty {
                    ContentUnavailableView("No recorded errors", systemImage: "checkmark.shield",
                        description: Text("A playback failure will appear here if the video engine or source resolver reports one."))
                }
                ForEach(visible) { event in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: event.outcome == .failed ?
                                "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(event.outcome == .failed ? .orange : .green)
                            Text(event.code).font(.subheadline.weight(.semibold))
                                .textSelection(.enabled)
                            Spacer(minLength: 4)
                            Text(event.date, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(event.source) · Episode \(event.episode) · \(event.outcome.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let status = event.httpStatus {
                            Text("HTTP \(status)").font(.caption.weight(.medium))
                        }
                        Text(event.recommendation).font(.caption)
                        if event.occurrences > 1 {
                            Text("Repeated \(event.occurrences) times")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }

            if !store.events.isEmpty {
                Section {
                    Button("Clear recovery history", role: .destructive) {
                        confirmClear = true
                    }
                }
            }
        }
        .navigationTitle("Recovery Center")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete private recovery history?",
            isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete recorded history", role: .destructive) { store.clear() }
            } message: {
                Text("The entries are permanently removed from this device. Playback files and saved watch progress are unaffected.")
            }
    }
}
