import XCTest
import Foundation
@testable import Kinetiq

/// These tests use local, deterministic data. They do not access the AniList
/// service, installed modules, a real user library or Discord credentials.
final class KinetiqCompassContractTests: XCTestCase {
    func testSmartSearchExtractsGenreAndLengthWithoutLosingTitle() {
        let intent = KinetiqDiscoveryIntent.interpret("Completed romance under 12 episodes")
        XCTAssertEqual(intent.genre, "Romance")
        XCTAssertTrue(intent.finishedOnly)
        XCTAssertEqual(intent.maximumEpisodes, 12)
        XCTAssertNil(intent.catalogSearch)

        let direct = KinetiqDiscoveryIntent.interpret("Find Roshidere")
        XCTAssertEqual(direct.catalogSearch, "roshidere")
        XCTAssertNil(direct.genre)

        // A title word is not a stopword just because it is also a preposition.
        XCTAssertEqual(KinetiqDiscoveryIntent.interpret("Attack on Titan").catalogSearch,
                       "attack on titan")
        XCTAssertEqual(KinetiqDiscoveryIntent.interpret("Please find Blue Box").catalogSearch,
                       "blue box")
    }

    func testPrivateLibraryQueryDoesNotBecomeAnOnlineSearch() {
        let intent = KinetiqDiscoveryIntent.interpret("What haven't I watched in my storage?")
        XCTAssertTrue(intent.asksForLocal)
        XCTAssertNil(intent.catalogSearch)
    }

    func testMediaConnectionsCanonicalizeAndRoundTrip() throws {
        let forward = try XCTUnwrap(KinetiqMediaConnection("module:a", "local:file.mp4"))
        let reverse = try XCTUnwrap(KinetiqMediaConnection("local:file.mp4", "module:a"))
        XCTAssertEqual(forward, reverse)
        XCTAssertNil(KinetiqMediaConnection("duplicate", "duplicate"))
        let decoded = try JSONDecoder().decode(KinetiqMediaConnection.self,
            from: JSONEncoder().encode(forward))
        XCTAssertEqual(decoded, forward)
    }

    @MainActor
    func testExplicitConnectionsDoNotAutoMergeUnknownSources() {
        let suite = "KinetiqCompassContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KinetiqMediaConnectionStore(defaults: defaults)
        XCTAssertEqual(store.connectedIDs(to: "a"), ["a"])
        store.setLinked(true, "a", "b")
        XCTAssertEqual(store.connectedIDs(to: "a"), ["a", "b"])
        XCTAssertFalse(store.contains("a", "c"))
        store.setLinked(false, "a", "b")
        XCTAssertEqual(store.connectedIDs(to: "a"), ["a"])
    }
}
