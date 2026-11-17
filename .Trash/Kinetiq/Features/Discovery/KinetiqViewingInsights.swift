import SwiftUI
import Foundation

/// Derived exclusively from records already present on the device.
/// Never creates a telemetry identifier or uploads watch-history analytics.
@MainActor
struct KinetiqViewingInsightsView: View {
    private struct SourceStat: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @StateObject private var downloads = KinetiqOfflineDownloadStore.shared
    @StateObject private var continuity = KinetiqContinuityStore.shared

    private var progressRecords: [ModuleEpisodeProgress] {
        collection.entries.flatMap { $0.episodeProgress ?? [] }
    }

    private var completedEpisodes: Int { progressRecords.filter(\.isCompleted).count }

    private var remainingEpisodes: Int {
        progressRecords.filter { !$0.isCompleted && $0.resumePosition > 0 }.count
    }

    private var verifiedDownloads: [KinetiqOfflineEntry] {
        downloads.entries.filter {
            $0.state == .ready && KinetiqOfflineFileAudit.failureReason(for: $0) == nil
        }
    }

    private var downloadBytes: Int64 {
        verifiedDownloads.reduce(0) { $0 + max($1.bytes, 0) }
    }

    private var favoriteSources: [SourceStat] {
        let groups = Dictionary(grouping: collection.favorites, by: \.sourceName)
        return groups.map { SourceStat(name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var body: some View {
        List {
            Section {
                Label("Private, honest statistics", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Text("Only records you created in Kinetiq appear here. Counts are per-source, so the same anime linked across two providers may be counted twice. No analytics are sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Your watch ledger") {
                LabeledContent("Saved anime", value: "\(collection.entries.count)")
                LabeledContent("Favorites", value: "\(collection.favorites.count)")
                LabeledContent("Completed episode records", value: "\(completedEpisodes)")
                LabeledContent("Episodes in progress", value: "\(remainingEpisodes)")
                LabeledContent("Recent scene anchors", value: "\(continuity.anchors.count)")
                LabeledContent("Manually bookmarked moments", value: "\(continuity.bookmarks.count)")
            }

            Section("Offline readiness") {
                LabeledContent("Verified ready episodes", value: "\(verifiedDownloads.count)")
                LabeledContent("Verified media storage", value:
                    ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file))
                let unavailable = downloads.entries.filter {
                    $0.state == .ready && KinetiqOfflineFileAudit.failureReason(for: $0) != nil
                }.count
                if unavailable > 0 {
                    Label("\(unavailable) saved episode(s) need a storage check", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text("Storage totals exclude imports, artwork caches and temporary conversions; this is not the iOS system-wide storage figure.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !favoriteSources.isEmpty {
                Section("Favorites by source") {
                    ForEach(favoriteSources) { source in
                        LabeledContent(source.name, value: "\(source.count)")
                    }
                }
            }

            Section("Explore") {
                NavigationLink {
                    KinetiqBrainView()
                } label: {
                    Label("Ask Brain about your backlog", systemImage: "brain.head.profile")
                }
                NavigationLink {
                    KinetiqSceneMemoryView()
                } label: {
                    Label("Browse scene bookmarks", systemImage: "bookmark")
                }
                NavigationLink {
                    KinetiqSyncVaultView()
                } label: {
                    Label("Take your watch ledger to another device", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Viewing Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}
