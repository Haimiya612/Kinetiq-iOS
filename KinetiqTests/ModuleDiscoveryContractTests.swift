import Foundation
import XCTest
@testable import Kinetiq

// Batch 05J: deterministic fixtures model the shapes returned by the
// Synthetiq One / Anime / Flux / AniWorld discovery_v1 handlers. These are
// parser tests, NOT evidence of source-site availability or iPhone playback.
final class ModuleDiscoveryContractTests: XCTestCase {
    private let baseURL = URL(string: "https://example.org/")!

    func testRealHomeSectionsAndViewAllFeed() {
        let payload: [String: Any] = [
            "sections": [
                ["id": "popular", "title": "Popular Now", "style": "poster",
                 "viewAll": ["mode": "feed", "feedId": "more-fast"],
                 "items": [
                    ["id": "mal:21", "href": "mal:21", "title": "One Piece",
                     "image": "https://img.example.org/21.jpg",
                     "streamCached": true, "year": 1999],
                    ["id": "mal:21", "href": "mal:21", "title": "Duplicate"]]],
                ["id": "empty", "title": "Empty", "items": []]
            ]
        ]
        let shelves = ModuleDiscoveryDecoder.home(from: payload, baseURL: baseURL)
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves[0].id, "popular")
        XCTAssertEqual(shelves[0].title, "Popular Now")
        XCTAssertEqual(shelves[0].feedID, "more-fast")
        XCTAssertEqual(shelves[0].cards.count, 1)
        XCTAssertEqual(shelves[0].cards[0].anime.href, "mal:21")
        XCTAssertEqual(shelves[0].cards[0].badge, "FAST")
        XCTAssertEqual(shelves[0].cards[0].year, "1999")
    }

    func testAniWorldHomeCardsUseSourceIdentity() {
        let payload: [String: Any] = [
            "sections": [[
                "id": "home-new", "title": "Neue Animes",
                "items": [["id": "series-abc", "href": "/anime/stream/series-abc",
                           "title": "Example Anime", "posterUrl": "/images/abc.jpg"]]
            ]]
        ]
        let shelves = ModuleDiscoveryDecoder.home(from: payload, baseURL: baseURL)
        XCTAssertEqual(shelves.first?.cards.first?.anime.id, "series-abc")
        XCTAssertEqual(shelves.first?.cards.first?.anime.href,
                       "/anime/stream/series-abc")
        XCTAssertEqual(shelves.first?.cards.first?.anime.imageURL?.absoluteString,
                       "https://example.org/images/abc.jpg")
        XCTAssertNil(shelves.first?.feedID)
    }

    func testInvalidArtAndMissingTitlesAreRejectedSafely() {
        let cards = ModuleDiscoveryDecoder.parseCards([
            ["id": "a", "title": "Valid", "image": "http://insecure.example/a.jpg"],
            ["id": "b", "title": "Missing art", "image": "javascript:alert(1)"],
            ["id": "c", "image": "https://example.org/c.jpg"],
            ["id": "a", "title": "Repeated"]
        ], baseURL: baseURL, limit: 40)
        XCTAssertEqual(cards.map(\.id), ["a", "b"])
        XCTAssertNil(cards[0].anime.imageURL)
        XCTAssertNil(cards[1].anime.imageURL)
    }

    func testExplicitFeedPaginationAndNoManufacturedHasMore() {
        let first = ModuleDiscoveryDecoder.feed(from: [
            "items": [["id": "mal:10", "title": "A"],
                      ["id": "mal:10", "title": "A again"]],
            "page": 2, "hasMore": true
        ], baseURL: baseURL, requestedPage: 2)
        XCTAssertEqual(first.cards.count, 1)
        XCTAssertEqual(first.page, 2)
        XCTAssertTrue(first.hasMore)

        let empty = ModuleDiscoveryDecoder.feed(from: [
            "items": [], "page": 3, "hasMore": true
        ], baseURL: baseURL, requestedPage: 3)
        XCTAssertFalse(empty.hasMore)
    }

    func testMalformedDiscoveryDoesNotBreakSearchFallback() {
        XCTAssertTrue(ModuleDiscoveryDecoder.home(from: ["error": "source down"],
                                                  baseURL: baseURL).isEmpty)
        XCTAssertTrue(ModuleDiscoveryDecoder.home(from: ["sections": "not an array"],
                                                  baseURL: baseURL).isEmpty)
    }

    func testBoundedLargeModuleOutput() {
        let many = (0..<250).map { i -> [String: Any] in
            ["id": "s\(i)", "title": "Title \(i)"]
        }
        let sections = (0..<30).map { index -> [String: Any] in
            ["id": "shelf\(index)", "items": many]
        }
        let result = ModuleDiscoveryDecoder.home(
            from: ["sections": sections], baseURL: baseURL
        )
        XCTAssertEqual(result.count, 12)
        XCTAssertTrue(result.allSatisfy { $0.cards.count == 40 })
    }
}
