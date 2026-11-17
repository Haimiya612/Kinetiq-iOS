import SwiftUI
import Foundation

/// Confirmed connections are navigation metadata. Each provider keeps its
/// original title ID, favorites, episode IDs, subtitles and watch history.
/// No fuzzy-title match can silently connect two different works.
struct KinetiqMediaConnection: Codable, Hashable, Identifiable {
    let first: String
    let second: String

    var id: String { "\(first.utf8.count):\(first)|\(second)" }

    init?(_ lhs: String, _ rhs: String) {
        guard !lhs.isEmpty, !rhs.isEmpty, lhs != rhs,
              lhs.utf8.count <= 2_500, rhs.utf8.count <= 2_500 else { return nil }
        first = min(lhs, rhs)
        second = max(lhs, rhs)
    }
}

@MainActor
final class KinetiqMediaConnectionStore: ObservableObject {
    static let shared = KinetiqMediaConnectionStore()
    @Published private(set) var connections: [KinetiqMediaConnection] = []
    private let defaults: UserDefaults
    private let key = "kinetiq.media.confirmedConnections.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let restored = try? JSONDecoder().decode([KinetiqMediaConnection].self, from: data) {
            connections = Array(Set(restored.compactMap { KinetiqMediaConnection($0.first, $0.second) })
                .prefix(500))
        }
    }

    func contains(_ lhs: String, _ rhs: String) -> Bool {
        guard let edge = KinetiqMediaConnection(lhs, rhs) else { return false }
        return connections.contains(edge)
    }

    func setLinked(_ linked: Bool, _ lhs: String, _ rhs: String) {
        guard let edge = KinetiqMediaConnection(lhs, rhs) else { return }
        if linked {
            guard connections.count < 500, !connections.contains(edge) else { return }
            connections.append(edge)
        } else {
            connections.removeAll { $0 == edge }
        }
        if let data = try? JSONEncoder().encode(connections) { defaults.set(data, forKey: key) }
    }

    func connectedIDs(to id: String) -> Set<String> {
        var visited: Set<String> = [id]
        var queue = [id]
        while let next = queue.popLast() {
            for edge in connections {
                let candidate: String?
                if edge.first == next { candidate = edge.second }
                else if edge.second == next { candidate = edge.first }
                else { candidate = nil }
                if let candidate, visited.insert(candidate).inserted { queue.append(candidate) }
            }
        }
        return visited
    }
}

@MainActor
struct KinetiqSourcePassportView: View {
    let entry: ModuleAnimeCollectionEntry

    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @StateObject private var connections = KinetiqMediaConnectionStore.shared
    @State private var confirmation: Candidate?

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let source: String
    }

    private var moduleCandidates: [Candidate] {
        collection.entries.filter { $0.id != entry.id }.map {
            Candidate(id: $0.id, name: $0.title, source: $0.sourceName)
        }.filter { candidate in
            let normalized = KinetiqEpisodeMetadataMatching.normalized(candidate.name)
            let original = KinetiqEpisodeMetadataMatching.normalized(entry.title)
            // Suggestions only. Search remains exhaustive in DiscoverView.
            return !normalized.isEmpty && normalized == original
        }
    }

    private var localCandidates: [Candidate] {
        let original = KinetiqEpisodeMetadataMatching.normalized(entry.title)
        guard original.count >= 4 else { return [] }
        return KinetiqPrivateLibraryScanner.importedVideos().compactMap { item in
            let normalized = KinetiqEpisodeMetadataMatching.normalized(item.title)
            guard normalized.contains(original) else { return nil }
            return Candidate(id: "local:\(item.id)", name: item.title, source: "Local Library")
        }
    }

    private var candidates: [Candidate] { moduleCandidates + localCandidates }

    var body: some View {
        List {
            Section {
                HStack(spacing: 13) {
                    ModuleAnimeArtworkView(url: entry.anime.imageURL)
                        .frame(width: 70, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        Text("Saved from \(entry.sourceName)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.playbackLabel)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Connected media identities") {
                if candidates.isEmpty {
                    Text("No matching saved or imported items found yet. Search your other sources, open the title, then return to confirm a connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(candidates) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: candidate.source == "Local Library" ?
                              "iphone.gen3" : "play.rectangle")
                            .foregroundStyle(KinetiqPalette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name).font(.subheadline.weight(.medium))
                            Text(candidate.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if connections.contains(entry.id, candidate.id) {
                            Button("Unlink") {
                                connections.setLinked(false, entry.id, candidate.id)
                            }.buttonStyle(.bordered)
                        } else {
                            Button("Connect") { confirmation = candidate }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            Section("Find every available source") {
                NavigationLink {
                    DiscoverView(initialQuery: entry.title,
                        searchesAllSourcesOnOpen: true)
                } label: {
                    Label("Search all trusted modules", systemImage: "square.stack.3d.up")
                }
                Text("No search result is removed just because its name resembles another. Connections are saved only after you confirm the same title and edition.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Identity rules") {
                Label("Provider IDs are never overwritten", systemImage: "checkmark.shield")
                Label("Existing favorites and playback history remain separate", systemImage: "checkmark.shield")
                Label("Episode and subtitle equivalence must be verified before progress handoff", systemImage: "exclamationmark.shield")
                    .font(.caption)
            }
        }
        .navigationTitle("Source Passport")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Confirm the same title?",
                            isPresented: Binding(get: { confirmation != nil },
                                                 set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible) {
            if let candidate = confirmation {
                Button("Connect \(candidate.source)") {
                    connections.setLinked(true, entry.id, candidate.id)
                    confirmation = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text("Check the series, season and edition yourself. A similar name alone is not proof the media matches.")
        }
    }
}
