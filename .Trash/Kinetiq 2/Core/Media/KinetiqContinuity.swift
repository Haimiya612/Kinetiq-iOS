import Foundation
import SwiftUI

/// A Scene Passport contains only playback metadata. It never contains a
/// stream URL, request headers, cookies or authentication credentials.
struct KinetiqSceneAnchor: Codable, Identifiable, Equatable {
    let id: UUID
    let mediaID: String
    let sourceName: String
    let episodeID: String
    let episodeNumber: String
    let language: String
    let seconds: Double
    let duration: Double
    let savedAt: Date

    init(mediaID: String, sourceName: String, episodeID: String,
         episodeNumber: String, language: String, seconds: Double,
         duration: Double, savedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.mediaID = mediaID
        self.sourceName = sourceName
        self.episodeID = episodeID
        self.episodeNumber = episodeNumber
        self.language = language
        self.seconds = seconds
        self.duration = duration
        self.savedAt = savedAt
    }

    var isValid: Bool {
        !mediaID.isEmpty && mediaID.count <= 3_000 &&
        !episodeID.isEmpty && episodeID.count <= 2_500 &&
        episodeNumber.count <= 80 && language.count <= 24 &&
        seconds.isFinite && duration.isFinite &&
        duration > 5 && seconds >= 0 && seconds <= duration + 5
    }
}

struct KinetiqSceneBookmark: Codable, Identifiable, Equatable {
    let id: UUID
    let anchor: KinetiqSceneAnchor
    var note: String
    let createdAt: Date

    init(anchor: KinetiqSceneAnchor, note: String = "") {
        id = UUID()
        self.anchor = anchor
        self.note = String(note.prefix(240))
        createdAt = Date()
    }
}

struct KinetiqContinuitySuggestion: Identifiable {
    let anchor: KinetiqSceneAnchor
    let mappedSeconds: Double
    let explanation: String
    let confidence: Double
    var id: UUID { anchor.id }
}

/// An episode identity is more specific than the display number. An OVA,
/// recap or special with the same numeral as a normal episode is never an
/// interchangeable target. Unnumbered/unknown editions require the user to
/// line up the scene manually; title similarity cannot prove a match.
enum KinetiqEpisodeIdentity: Equatable {
    case regular(season: Int?, episode: Int)
    case alternate(kind: String, number: Int?)

    var hasExplicitSeason: Bool {
        if case .regular(let season, _) = self { return season != nil }
        return false
    }

    static func parse(_ raw: String) -> KinetiqEpisodeIdentity? {
        let normalized = raw.lowercased()
            .replacingOccurrences(of: #"[\s_]+"#, with: "", options: .regularExpression)
        guard !normalized.isEmpty else { return nil }

        let qualified = [
            #"^s(\d{1,2})-?e(\d{1,3})$"#,
            #"^season(\d{1,2})episode(\d{1,3})$"#,
            #"^(\d{1,2})x(\d{1,3})$"#
        ]
        for expression in qualified {
            if let fields = captures(in: normalized, expression: expression),
               fields.count == 2, fields[1] > 0 {
                return .regular(season: fields[0], episode: fields[1])
            }
        }

        for prefix in ["ova", "special", "sp", "recap"] {
            if normalized == prefix { return .alternate(kind: prefix, number: nil) }
            if normalized.hasPrefix(prefix),
               let number = Int(normalized.dropFirst(prefix.count)),
               (0...999).contains(number) {
                return .alternate(kind: prefix, number: number)
            }
        }

        for expression in [#"^(\d{1,3})$"#, #"^e(\d{1,3})$"#,
                           #"^ep(\d{1,3})$"#, #"^episode(\d{1,3})$"#] {
            if let fields = captures(in: normalized, expression: expression),
               let number = fields.first {
                return .regular(season: nil, episode: number)
            }
        }
        // Fractional episodes, movies with unknown editions, volume identifiers
        // and arbitrary scraped labels must not be guessed into a normal episode.
        return nil
    }

    private static func captures(in text: String, expression: String) -> [Int]? {
        guard let regex = try? NSRegularExpression(pattern: expression),
              let match = regex.firstMatch(in: text,
                  range: NSRange(text.startIndex..., in: text)) else { return nil }
        var values: [Int] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text),
                  let value = Int(text[range]), value <= 999 else { return nil }
            values.append(value)
        }
        return values
    }
}

enum KinetiqContinuityMatcher {
    /// Never infer equivalence merely from a similar series title. Explicit
    /// Source Passport links, episode numbering, language and cut duration
    /// must agree before suggesting a source-to-source seek.
    static func candidate(_ anchor: KinetiqSceneAnchor,
                          targetMediaID: String,
                          connectedIDs: Set<String>,
                          episodeNumber: String, language: String,
                          duration: Double) -> KinetiqContinuitySuggestion? {
        guard anchor.isValid, anchor.mediaID != targetMediaID,
              connectedIDs.contains(anchor.mediaID),
              let originalIdentity = KinetiqEpisodeIdentity.parse(anchor.episodeNumber),
              let targetIdentity = KinetiqEpisodeIdentity.parse(episodeNumber),
              originalIdentity == targetIdentity,
              anchor.language.caseInsensitiveCompare(language) == .orderedSame,
              duration.isFinite, duration > 5 else { return nil }

        let mismatch = abs(anchor.duration - duration) / max(duration, anchor.duration)
        // A materially different cut needs an explicit manual alignment.
        guard mismatch <= 0.02 else { return nil }
        let scale = duration / anchor.duration
        let mapped = min(max(anchor.seconds * scale, 0), max(0, duration - 1))
        let knownSeason = originalIdentity.hasExplicitSeason
        let nearlyExactCut = mismatch < 0.005
        return KinetiqContinuitySuggestion(anchor: anchor,
            mappedSeconds: mapped,
            explanation: knownSeason
                ? (nearlyExactCut
                    ? "Same confirmed season, episode, language and nearly identical runtime."
                    : "Confirmed season and episode; small runtime difference, so adjust the scene if needed.")
                : "The sources agree on episode number and language, but neither provided a season identifier. Confirm the edition before applying this seek.",
            confidence: knownSeason ? (nearlyExactCut ? 0.98 : 0.88)
                                    : (nearlyExactCut ? 0.82 : 0.72))
    }

    static func normalizedEpisode(_ raw: String) -> String {
        // Keep season identifiers, specials, OVAs and episode 0 distinct.
        raw.lowercased().replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }
}

@MainActor
final class KinetiqContinuityStore: ObservableObject {
    static let shared = KinetiqContinuityStore()
    @Published private(set) var anchors: [KinetiqSceneAnchor] = []
    @Published private(set) var bookmarks: [KinetiqSceneBookmark] = []

    private let defaults: UserDefaults
    private let anchorsKey = "kinetiq.continuity.anchors.v1"
    private let bookmarksKey = "kinetiq.continuity.bookmarks.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: anchorsKey),
           let saved = try? JSONDecoder().decode([KinetiqSceneAnchor].self, from: bytes) {
            anchors = Array(saved.filter(\.isValid).prefix(2_000))
        }
        if let bytes = defaults.data(forKey: bookmarksKey),
           let saved = try? JSONDecoder().decode([KinetiqSceneBookmark].self, from: bytes) {
            bookmarks = Array(saved.filter { $0.anchor.isValid }.prefix(1_000))
        }
    }

    func record(_ anchor: KinetiqSceneAnchor) {
        guard anchor.isValid else { return }
        // Only one latest anchor per source episode and language.
        anchors.removeAll { $0.mediaID == anchor.mediaID &&
            $0.episodeID == anchor.episodeID && $0.language == anchor.language }
        anchors.insert(anchor, at: 0)
        if anchors.count > 2_000 { anchors.removeLast(anchors.count - 2_000) }
        save()
    }

    func bookmark(_ anchor: KinetiqSceneAnchor, note: String = "") {
        guard anchor.isValid else { return }
        bookmarks.insert(KinetiqSceneBookmark(anchor: anchor, note: note), at: 0)
        if bookmarks.count > 1_000 { bookmarks.removeLast(bookmarks.count - 1_000) }
        save()
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func suggestion(for targetMediaID: String, episodeNumber: String,
                    language: String, duration: Double,
                    confirmedLinks: Set<String>) -> KinetiqContinuitySuggestion? {
        anchors.compactMap {
            KinetiqContinuityMatcher.candidate($0, targetMediaID: targetMediaID,
                connectedIDs: confirmedLinks, episodeNumber: episodeNumber,
                language: language, duration: duration)
        }.max { $0.anchor.savedAt < $1.anchor.savedAt }
    }

    func merge(anchors incomingAnchors: [KinetiqSceneAnchor],
               bookmarks incomingBookmarks: [KinetiqSceneBookmark]) {
        var latest: [String: KinetiqSceneAnchor] = [:]
        for item in anchors + incomingAnchors where item.isValid {
            let key = [item.mediaID, item.episodeID, item.language].joined(separator: "\u{1F}")
            if latest[key]?.savedAt ?? .distantPast < item.savedAt { latest[key] = item }
        }
        anchors = Array(latest.values.sorted { $0.savedAt > $1.savedAt }.prefix(2_000))
        var visited = Set<UUID>()
        bookmarks = Array((bookmarks + incomingBookmarks)
            .filter { $0.anchor.isValid && visited.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }.prefix(1_000))
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(anchors) { defaults.set(data, forKey: anchorsKey) }
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: bookmarksKey) }
    }
}

@MainActor
struct KinetiqSceneMemoryView: View {
    @StateObject private var store = KinetiqContinuityStore.shared

    var body: some View {
        List {
            Section {
                Label("Scene Passports remember where you stopped, even across confirmed Source Passport links.",
                      systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline)
                Text("Source names, episode numbers and timestamps stay on this device. Video links and credentials are never stored here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scene bookmarks") {
                if store.bookmarks.isEmpty {
                    Text("Nothing bookmarked yet. While playing a module episode, open More → Power Deck → Bookmark scene.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.bookmarks) { bookmark in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bookmark.anchor.sourceName).font(.headline)
                        Text("Episode \(bookmark.anchor.episodeNumber) · \(Int(bookmark.anchor.seconds)) seconds · \(bookmark.anchor.language.uppercased())")
                            .font(.subheadline)
                        if !bookmark.note.isEmpty { Text(bookmark.note).font(.caption) }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.bookmarks[$0].id }
                    for id in ids { store.removeBookmark(id) }
                }
            }
            Section("Recent progress anchors") {
                ForEach(store.anchors.prefix(40)) { anchor in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(anchor.sourceName) · Episode \(anchor.episodeNumber)")
                        Text("\(Int(anchor.seconds))s of \(Int(anchor.duration))s · \(anchor.language.uppercased())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Scene Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
}
