import Foundation

// MARK: - Source-owned discovery contracts (Batch 05J)
//
// Compatible with the actual `discoveryHome()` and `discoveryFeed(id, page)`
// results from the extracted Synthetiq One, AniWorld, Anime and Flux modules.
// This parser deliberately does NOT scrape, invent catalogue items, alter source
// names, return fake playback links or treat arbitrary strings as media URLs.

struct ModuleDiscoveryCard: Identifiable {
    let anime: ModuleAnimeItem
    let badge: String?
    let year: String?

    var id: String { anime.id }
}

struct ModuleDiscoveryShelf: Identifiable {
    let id: String
    let title: String
    let style: String
    let feedID: String?
    let cards: [ModuleDiscoveryCard]
}

struct ModuleDiscoveryFeedPage {
    let cards: [ModuleDiscoveryCard]
    let page: Int
    let hasMore: Bool
}

enum ModuleDiscoveryDecoder {
    static let maxShelves = 12
    static let maxCardsPerShelf = 40
    static let maxFeedCards = 60

    static func home(from response: Any, baseURL: URL) -> [ModuleDiscoveryShelf] {
        guard let root = response as? [String: Any],
              let rawSections = root["sections"] as? [[String: Any]] else { return [] }

        var seenSections = Set<String>()
        var shelves: [ModuleDiscoveryShelf] = []

        for section in rawSections.prefix(maxShelves * 2) {
            guard let sectionID = text(section, keys: ["id", "key"]),
                  !sectionID.isEmpty,
                  seenSections.insert(sectionID).inserted else { continue }

            let rawCards = section["items"] as? [[String: Any]] ?? []
            let cards = parseCards(rawCards, baseURL: baseURL,
                                   limit: maxCardsPerShelf)
            guard !cards.isEmpty else { continue }

            let title = text(section, keys: ["title", "name"]) ?? sectionID
            let style = text(section, keys: ["style"]) ?? "poster"
            let viewAll = section["viewAll"] as? [String: Any]
            let mode = text(viewAll ?? [:], keys: ["mode"])?.lowercased()
            // Only expose feeds explicitly advertised by this module.
            let feedID: String? = mode == "feed"
                ? text(viewAll ?? [:], keys: ["feedId", "feedID"]) : nil

            shelves.append(ModuleDiscoveryShelf(
                id: sectionID,
                title: String(title.prefix(100)),
                style: String(style.prefix(35)),
                feedID: feedID,
                cards: cards
            ))
            if shelves.count >= maxShelves { break }
        }
        return shelves
    }

    static func feed(from response: Any, baseURL: URL,
                     requestedPage: Int) -> ModuleDiscoveryFeedPage {
        let root = response as? [String: Any] ?? [:]
        let rawCards = root["items"] as? [[String: Any]]
            ?? (response as? [[String: Any]] ?? [])
        let cards = parseCards(rawCards, baseURL: baseURL, limit: maxFeedCards)
        let reportedPage = number(root["page"]) ?? requestedPage
        let page = max(1, min(1_000, reportedPage))
        let hasMore = (root["hasMore"] as? Bool) == true && !cards.isEmpty
        return ModuleDiscoveryFeedPage(cards: cards, page: page, hasMore: hasMore)
    }

    static func parseCards(_ rawCards: [[String: Any]], baseURL: URL,
                           limit: Int) -> [ModuleDiscoveryCard] {
        var seen = Set<String>()
        var result: [ModuleDiscoveryCard] = []
        for item in rawCards.prefix(max(1, min(limit * 3, 300))) {
            guard let title = text(item, keys: ["title", "name", "label"]),
                  let reference = text(item, keys: [
                    "href", "url", "link", "id", "animeId", "seriesId"
                  ]) else { continue }
            let id = text(item, keys: ["id", "animeId", "seriesId"]) ?? reference
            guard seen.insert(id).inserted else { continue }

            let rawArtwork = text(item, keys: [
                "image", "posterUrl", "posterURL", "poster", "thumbnail", "cover"
            ])
            let synopsis = text(item, keys: [
                "description", "synopsis", "summary", "overview"
            ]).map { String($0.prefix(3_500)) }

            let artworkURL: URL?
            if let rawArtwork,
               let url = URL(string: rawArtwork, relativeTo: baseURL)?.absoluteURL,
               url.scheme?.lowercased() == "https", url.host != nil,
               url.user == nil, url.password == nil {
                artworkURL = url
            } else {
                artworkURL = nil
            }

            let isFast = ["streamCached", "fast", "isFast", "cached"]
                .contains { (item[$0] as? Bool) == true }
            let badge: String?
            if isFast { badge = "FAST" }
            else if (item["isMovie"] as? Bool) == true { badge = "Movie" }
            else { badge = nil }

            let year = text(item, keys: ["year", "releaseYear"])
            result.append(ModuleDiscoveryCard(
                anime: ModuleAnimeItem(
                    id: id, title: String(title.prefix(350)), href: reference,
                    imageURL: artworkURL, synopsis: synopsis
                ),
                badge: badge,
                year: year.map { String($0.prefix(12)) }
            ))
            if result.count >= limit { break }
        }
        return result
    }

    private static func text(_ item: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !result.isEmpty { return result }
            }
            if let value = item[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
