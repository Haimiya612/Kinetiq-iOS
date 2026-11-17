import XCTest
import Foundation
@testable import Kinetiq

final class KinetiqMetadataContractTests: XCTestCase {
    func testEpisodeDecoderPreservesPlaybackIdentityWhileAddingPresentationData() {
        let source: [[String: Any]] = [[
            "id": "source-ep-5", "href": "/play/episode-5", "episodeNumber": 5,
            "title": "Episode 5 - The First Promise",
            "thumbnail": "/images/episode-5.jpg", "description": "A new chapter begins.",
            "durationMinutes": 24,
            "subAvailable": true, "dubAvailable": false
        ]]
        let episodes = ModuleRuntimeDecoder.episodes(
            from: source, baseURL: URL(string: "https://example.org")!)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.id, "source-ep-5")
        XCTAssertEqual(episodes.first?.href, "/play/episode-5")
        XCTAssertEqual(episodes.first?.number, "5")
        XCTAssertEqual(episodes.first?.title, "The First Promise")
        XCTAssertEqual(episodes.first?.imageURL?.absoluteString,
                       "https://example.org/images/episode-5.jpg")
        XCTAssertEqual(episodes.first?.durationMinutes, 24)
        XCTAssertEqual(episodes.first?.synopsis, "A new chapter begins.")
        XCTAssertEqual(episodes.first?.subAvailable, true)
        XCTAssertEqual(episodes.first?.dubAvailable, false)
    }

    func testTitleAndNumberHaveSeparateMeanings() {
        let source: [[String: Any]] = [[
            "href": "/ep/one", "title": "The Lost Letter"
        ], [
            "href": "/ep/two", "title": "Episode 2: A New Beginning"
        ]]
        let episodes = ModuleRuntimeDecoder.episodes(from: source)
        XCTAssertEqual(episodes.map(\.number), ["1", "2"])
        XCTAssertEqual(episodes.compactMap(\.title), ["The Lost Letter", "A New Beginning"])
        XCTAssertNil(KinetiqEpisodeMetadataMatching.displayTitle("Episode 5", episodeNumber: "5"))
    }

    func testDiscordPresentationRemovesRepeatedEpisodePrefixesWithoutDroppingRealTitle() {
        XCTAssertEqual(KinetiqEpisodeMetadataMatching.displayTitle(
            "Episode 1: S1E1: Episode 1: Alya Hides Her Feelings", episodeNumber: "1"),
            "Alya Hides Her Feelings")
        XCTAssertEqual(KinetiqEpisodeMetadataMatching.displayTitle(
            "S2E05: Episode 5 - The First Promise", episodeNumber: "5"),
            "The First Promise")
        XCTAssertNil(KinetiqEpisodeMetadataMatching.displayTitle(
            "Episode 3: S1E3: Episode 3", episodeNumber: "3"))
        XCTAssertEqual(KinetiqEpisodeMetadataMatching.displayTitle(
            "Episode 6: Opening Night", episodeNumber: "5"),
            "Episode 6: Opening Night")
    }

    func testSeasonMatchingAvoidsNumberingByTitleSimilarity() {
        let matching = KinetiqEpisodeMetadataMatching.normalized("Blue Box Season 2")
        XCTAssertEqual(matching,
                       KinetiqEpisodeMetadataMatching.normalized("Blue Box 2nd Season"))
        XCTAssertNotEqual(matching,
                          KinetiqEpisodeMetadataMatching.normalized("Blue Box"))
        let (season, title) = KinetiqEpisodeMetadataMatching.seasonAndBaseTitle("Blue Box Season 2")
        XCTAssertEqual(season, 2)
        XCTAssertEqual(title, "Blue Box")
    }

    func testNoCrossProviderOverlayForSpecialsOrCompoundIDs() {
        XCTAssertNil(KinetiqEpisodeMetadataMatching.episodeIndex("OVA 1"))
        XCTAssertNil(KinetiqEpisodeMetadataMatching.episodeIndex("S2E5"))
        XCTAssertNil(KinetiqEpisodeMetadataMatching.episodeIndex("Special"))
        XCTAssertEqual(KinetiqEpisodeMetadataMatching.episodeIndex("5"), 5)
    }
}
