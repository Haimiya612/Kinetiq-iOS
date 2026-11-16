import SwiftUI
import Foundation

/// Offline preflight checks the actual saved payloads, not merely a queue's
/// optimistic `ready` flag. Native playback still requires an Airplane Mode
/// device test; no network request is made by this screen.
enum KinetiqTravelAudit {
    struct Result: Identifiable {
        let entry: KinetiqOfflineEntry
        let failure: String?
        var id: String { entry.id }
        var fileReady: Bool { entry.state == .ready && failure == nil }
    }

    static func inspect(_ entries: [KinetiqOfflineEntry]) -> [Result] {
        entries.map { entry in
            Result(entry: entry, failure: entry.state == .ready ?
                KinetiqOfflineFileAudit.failureReason(for: entry) :
                "This episode has not finished downloading.")
        }
    }
}

@MainActor
struct KinetiqTravelVaultView: View {
    @StateObject private var store = KinetiqOfflineDownloadStore.shared
    @State private var lastChecked = Date()

    private struct TravelGroup: Identifiable {
        let title: String
        let results: [KinetiqTravelAudit.Result]
        var id: String { title }
    }

    private var audit: [KinetiqTravelAudit.Result] {
        KinetiqTravelAudit.inspect(store.entries)
    }
    private var readyCount: Int { audit.filter(\.fileReady).count }
    private var grouped: [TravelGroup] {
        let groups = Dictionary(grouping: audit) {
            "\($0.entry.animeTitle)|\($0.entry.sourceName)"
        }
        return groups.keys.sorted().compactMap { key in
            guard let records = groups[key], let first = records.first else { return nil }
            return TravelGroup(title: "\(first.entry.animeTitle) · \(first.entry.sourceName)",
                    results: records.sorted {
                        ($0.entry.episodeNumber.localizedStandardCompare($1.entry.episodeNumber)) == .orderedAscending
                    })
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    Label("TRAVEL VAULT", systemImage: "airplane")
                        .font(.caption.weight(.heavy)).foregroundStyle(KinetiqPalette.accent)
                    Text("Check before you leave")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(readyCount) of \(audit.count) episodes passed local file checks")
                        .font(.subheadline)
                    ProgressView(value: Double(readyCount), total: Double(max(audit.count, 1)))
                        .tint(KinetiqPalette.accent)
                    Button("Check downloads again", systemImage: "arrow.clockwise") {
                        lastChecked = Date()
                    }
                    .buttonStyle(.bordered)
                    Text("Last checked \(lastChecked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if grouped.isEmpty {
                Section {
                    ContentUnavailableView("Nothing to check", systemImage: "externaldrive",
                        description: Text("Download an authorized episode or season, then return before travelling."))
                }
            }

            ForEach(grouped) { group in
                Section {
                    ForEach(group.results) { result in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: result.fileReady ? "checkmark.shield.fill" :
                                  "exclamationmark.triangle.fill")
                                .foregroundStyle(result.fileReady ? Color.green : Color.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Episode \(result.entry.episodeNumber) · \(result.entry.language.uppercased())")
                                    .font(.subheadline.weight(.medium))
                                Text(result.entry.quality)
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let failure = result.failure {
                                    Text(failure).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Label("Video present; \(result.entry.subtitleTracks.count) external subtitle track(s) checked",
                                          systemImage: "checkmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text("\(group.results.filter(\.fileReady).count) / \(group.results.count) local files passed")
                }
            }

            Section("Offline acceptance") {
                Label("Saved video exists and contains media data", systemImage: "checkmark.circle")
                Label("Saved external subtitle files exist", systemImage: "captions.bubble")
                Label("Airplane Mode and post-restart playback require iPhone testing", systemImage: "iphone.gen3.radiowaves.left.and.right")
                Text("Passing the file preflight is not proof the decoder can play every HLS rendition offline. Streaming URLs, private cookies and user history are never included in this report.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Travel Vault")
        .navigationBarTitleDisplayMode(.inline)
    }
}
