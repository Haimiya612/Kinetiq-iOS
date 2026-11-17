import Foundation
import SwiftUI
import CryptoKit

/// A read-only inventory of media imported into Kinetiq. It never scans the
/// user's entire Files app, Photos library or another app's sandbox.
struct KinetiqLibraryAudit: Sendable {
    struct Video: Identifiable, Sendable {
        let name: String
        let bytes: Int64
        var id: String { name }
    }

    let videos: [Video]
    let duplicateGroups: [[String]]
    let skippedLargeCandidates: Int

    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.bytes } }
    var duplicateBytes: Int64 {
        let sizes = Dictionary(uniqueKeysWithValues: videos.map { ($0.name, $0.bytes) })
        return duplicateGroups.reduce(0) { sum, group in
            sum + group.dropFirst().reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        }
    }
}

actor KinetiqLibraryAuditor {
    static let shared = KinetiqLibraryAuditor()

    /// Only same-sized files are hashed. Cap reading so a huge library cannot
    /// silently drain a battery. Skipped candidates remain explicitly unknown.
    func audit() throws -> KinetiqLibraryAudit {
        let imported = KinetiqPrivateLibraryScanner.importedVideos()
        let videos = imported.map { KinetiqLibraryAudit.Video(name: $0.id, bytes: $0.bytes) }
        let groups = Dictionary(grouping: imported, by: \.bytes).values
            .filter { $0.count > 1 && ($0.first?.bytes ?? 0) > 0 }
        var duplicates: [[String]] = []
        var skipped = 0
        var remainingBudget: Int64 = 6_000_000_000

        for group in groups {
            try Task<Never, Never>.checkCancellation()
            var byDigest: [String: [String]] = [:]
            for item in group {
                try Task<Never, Never>.checkCancellation()
                guard item.bytes <= 2_000_000_000,
                      item.bytes <= remainingBudget else {
                    skipped += 1
                    continue
                }
                remainingBudget -= item.bytes
                // An unreadable or concurrently removed file must never be
                // counted as a duplicate based only on its size.
                if let digest = try? Self.fingerprint(url: item.url) {
                    byDigest[digest, default: []].append(item.id)
                }
            }
            duplicates += byDigest.values.filter { $0.count > 1 }
        }

        try Task<Never, Never>.checkCancellation()
        return KinetiqLibraryAudit(videos: videos,
            duplicateGroups: duplicates.sorted { ($0.first ?? "") < ($1.first ?? "") },
            skippedLargeCandidates: skipped)
    }

    /// Full-file SHA-256, not a filename or size guess. No files are changed.
    nonisolated static func fingerprint(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task<Never, Never>.checkCancellation()
            guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { break }
            digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
struct KinetiqLibraryDoctorView: View {
    @StateObject private var history = PlaybackHistoryStore.shared
    @State private var audit: KinetiqLibraryAudit?
    @State private var scanning = false
    @State private var errorMessage: String?
    @State private var scanTask: Task<Void, Never>?
    @State private var scanGeneration = UUID()

    private var unwatched: [KinetiqLibraryAudit.Video] {
        (audit?.videos ?? []).filter {
            history.entry(for: $0.id) == nil && !history.hasCompleted(mediaID: $0.id)
        }
    }

    private var reportText: String {
        guard let audit else { return "Kinetiq Library Doctor: no scan completed." }
        return """
        Kinetiq Library Doctor — private local report
        Imported videos: \(audit.videos.count)
        Total imported bytes: \(audit.totalBytes)
        No Kinetiq playback record: \(unwatched.count)
        Exact SHA-256 duplicate groups: \(audit.duplicateGroups.count)
        Potential redundant bytes: \(audit.duplicateBytes)
        Large same-size candidates not hashed: \(audit.skippedLargeCandidates)
        No files were modified or deleted.
        """
    }

    var body: some View {
        List {
            Section {
                Label("Only Kinetiq's imported KinetiqMedia folder is inspected. Files, Photos, iCloud and streaming-module caches outside this folder are not scanned.", systemImage: "hand.raised.square")
                    .font(.subheadline)
                Text("Exact duplicates use full-file SHA-256, not names or matching sizes alone. The audit is read-only and cancellable.")
                    .font(.caption).foregroundStyle(.secondary)

                Button {
                    beginScan()
                } label: {
                    Label(scanning ? "Scanning imported media…" : "Run storage and duplicate audit",
                          systemImage: "externaldrive.badge.magnifyingglass")
                }
                .disabled(scanning)
                if scanning {
                    ProgressView("Checking files on device")
                    Button("Stop scan", role: .cancel) { scanTask?.cancel(); scanning = false }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }

            if let audit {
                Section("Library health") {
                    LabeledContent("Imported videos", value: "\(audit.videos.count)")
                    LabeledContent("Imported storage", value: ByteCountFormatter.string(fromByteCount: audit.totalBytes, countStyle: .file))
                    LabeledContent("No recorded playback", value: "\(unwatched.count)")
                    LabeledContent("Verified duplicate groups", value: "\(audit.duplicateGroups.count)")
                    LabeledContent("Potential duplicate space", value: ByteCountFormatter.string(fromByteCount: audit.duplicateBytes, countStyle: .file))
                    if audit.skippedLargeCandidates > 0 {
                        Text("\(audit.skippedLargeCandidates) large same-sized files were skipped by the 6 GB read budget. Their duplicate status is unknown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Largest imported files") {
                    ForEach(audit.videos.sorted { $0.bytes > $1.bytes }.prefix(12)) { video in
                        LabeledContent(video.name,
                            value: ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file))
                    }
                }

                Section("Exact duplicate review") {
                    if audit.duplicateGroups.isEmpty {
                        Text("No exact duplicates were found among the files checked.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(audit.duplicateGroups, id: \.self) { names in
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Identical content · \(names.count) copies", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                            ForEach(names, id: \.self) { name in
                                Text(name).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    Text("Library Doctor never deletes media automatically. Review originals and any linked watch history before removing anything manually.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Unwatched imports") {
                    ForEach(unwatched.prefix(20)) { video in
                        Text(video.name).font(.subheadline).textSelection(.enabled)
                    }
                    if unwatched.isEmpty {
                        Text("Every imported file has a Kinetiq playback record, or the library is empty.")
                            .foregroundStyle(.secondary)
                    }
                    Text("No recorded playback does not prove a file was never watched outside Kinetiq.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ShareLink(item: reportText) {
                        Label("Share privacy-safe summary", systemImage: "square.and.arrow.up")
                    }
                    Text("The exported summary contains counts and sizes only, not filenames, module addresses or credentials.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Library Doctor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if audit == nil && !scanning { beginScan() } }
        .onDisappear { scanTask?.cancel(); scanning = false }
    }

    private func beginScan() {
        scanTask?.cancel()
        scanGeneration = UUID()
        let generation = scanGeneration
        scanning = true
        errorMessage = nil
        scanTask = Task {
            defer { if scanGeneration == generation { scanning = false } }
            do {
                let newAudit = try await KinetiqLibraryAuditor.shared.audit()
                guard !Task.isCancelled else { return }
                audit = newAudit
            } catch is CancellationError {
                // The previous completed report remains visible.
            } catch {
                errorMessage = "The local scan could not finish. Your media was not changed."
            }
        }
    }
}
