import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// A shareable appointment, not a streaming URL or a real-time synchronized room.
/// Participants must access their own authorized copy of the episode.
struct KinetiqWatchPlan: Codable, Identifiable, Equatable {
    let id: UUID
    var series: String
    var episode: String
    var startTime: Date
    var note: String
    var createdAt: Date

    init(series: String, episode: String, startTime: Date, note: String) {
        id = UUID()
        self.series = String(series.prefix(160))
        self.episode = String(episode.prefix(100))
        self.startTime = startTime
        self.note = String(note.prefix(200))
        createdAt = Date()
    }

    var invitation: String {
        let timezone = TimeZone.current.identifier
        let when = startTime.formatted(date: .abbreviated, time: .shortened)
        let noteLine = note.isEmpty ? "" : "\nNote: \(note)"
        return "Kinetiq Watch Plan\n\(series) · Episode \(episode)\n\(when) (\(timezone))\(noteLine)\nBring your own authorized playback source. This invitation does not contain a stream link or provide live sync."
    }
}

@MainActor
final class KinetiqWatchPlanStore: ObservableObject {
    static let shared = KinetiqWatchPlanStore()
    @Published private(set) var plans: [KinetiqWatchPlan] = []

    private let defaults: UserDefaults
    private let key = "kinetiq.social.watchPlans.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KinetiqWatchPlan].self, from: bytes) {
            plans = Array(decoded.filter { !$0.series.isEmpty && !$0.episode.isEmpty &&
                $0.series.count <= 160 && $0.episode.count <= 100 &&
                $0.note.count <= 200 && $0.startTime.timeIntervalSince1970.isFinite
            }.sorted { $0.startTime > $1.startTime }.prefix(100))
        }
    }

    func add(series: String, episode: String, start: Date, note: String) {
        let title = series.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = episode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !number.isEmpty, start.timeIntervalSince1970.isFinite else { return }
        plans.insert(KinetiqWatchPlan(series: title, episode: number,
                                      startTime: start, note: note), at: 0)
        plans = Array(plans.sorted { $0.startTime > $1.startTime }.prefix(100))
        save()
    }

    func remove(_ ids: Set<UUID>) {
        plans.removeAll { ids.contains($0.id) }
        save()
    }

    func merge(_ incoming: [KinetiqWatchPlan]) {
        guard incoming.count <= 100 else { return }
        var unique: [UUID: KinetiqWatchPlan] = [:]
        for plan in plans + incoming where !plan.series.isEmpty && !plan.episode.isEmpty &&
            plan.series.count <= 160 && plan.episode.count <= 100 &&
            plan.note.count <= 200 && plan.startTime.timeIntervalSince1970.isFinite {
            unique[plan.id] = plan
        }
        plans = Array(unique.values.sorted { $0.startTime > $1.startTime }.prefix(100))
        save()
    }

    private func save() {
        if let bytes = try? JSONEncoder().encode(plans) {
            defaults.set(bytes, forKey: key)
        }
    }
}

@MainActor
struct KinetiqWatchPlansView: View {
    @StateObject private var store = KinetiqWatchPlanStore.shared
    @State private var series = ""
    @State private var episode = "1"
    @State private var date = Date().addingTimeInterval(3_600)
    @State private var note = ""
    @State private var preview: KinetiqWatchPlan?

    var body: some View {
        Form {
            Section {
                Label("Plan a watch session", systemImage: "person.2.wave.2")
                    .font(.headline)
                Text("Make a spoiler-safe appointment and share it through Messages, AirDrop, or a QR code. This is an actual invitation you can save, not a live synchronized streaming room.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("New watch plan") {
                TextField("Anime or movie title", text: $series)
                    .textInputAutocapitalization(.words)
                TextField("Episode or part", text: $episode)
                DatePicker("Start", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                Button("Save watch plan", systemImage: "calendar.badge.plus") {
                    store.add(series: series, episode: episode, start: date, note: note)
                    series = ""
                    note = ""
                }
                .disabled(series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          episode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Saved plans") {
                if store.plans.isEmpty {
                    Text("No watch plans yet. Set a time above to invite someone.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.plans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.series).font(.headline)
                        Text("Episode \(plan.episode) · \(plan.startTime.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !plan.note.isEmpty { Text(plan.note).font(.caption) }
                        HStack(spacing: 16) {
                            ShareLink(item: plan.invitation) {
                                Label("Invite", systemImage: "square.and.arrow.up")
                            }
                            Button("QR code", systemImage: "qrcode") { preview = plan }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 5)
                }
                .onDelete { offsets in
                    store.remove(Set(offsets.map { store.plans[$0].id }))
                }
            }
            Section {
                Text("A live room with synchronized pause, seek, readiness and chat would require an approved SharePlay integration or a backend. No participant's playback credentials are collected or shared by Watch Plans.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Watch Plans")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { plan in
            NavigationStack {
                VStack(spacing: 18) {
                    if let qr = Self.makeQR(plan.invitation) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 290, maxHeight: 290)
                            .accessibilityLabel("QR code containing the watch invitation text")
                    } else {
                        Text("Couldn't create the QR code. Use Invite to share the text instead.")
                    }
                    Text(plan.invitation).font(.caption).textSelection(.enabled)
                }
                .padding()
                .navigationTitle("Watch invitation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { preview = nil } }
            }
        }
    }

    private static func makeQR(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
