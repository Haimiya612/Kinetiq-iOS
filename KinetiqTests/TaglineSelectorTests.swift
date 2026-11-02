import XCTest
@testable import Kinetiq

final class TaglineSelectorTests: XCTestCase {

    // MARK: - Existing Tagline Tests

    func testSelectionDoesNotRepeatPreviousTagline() {
        let options = ["One", "Two", "Three"]

        let selected = TaglineSelector.next(
            previous: "Two",
            candidates: options,
            choose: { $0.last }
        )

        XCTAssertEqual(selected, "Three")
        XCTAssertNotEqual(selected, "Two")
    }

    func testSingleCandidateCanBeSelectedAgain() {
        let selected = TaglineSelector.next(
            previous: "Only",
            candidates: ["Only"],
            choose: { $0.first }
        )

        XCTAssertEqual(selected, "Only")
    }

    func testEmptyCandidateListUsesBrandFallback() {
        let selected = TaglineSelector.next(
            previous: nil,
            candidates: [],
            choose: { _ in nil }
        )

        XCTAssertEqual(selected, BrandTagline.options[0])
    }

    // MARK: - Playback History Tests

    func testPlaybackProgressCanBeSavedAndRetrieved() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "movie.mp4",
            title: "My Movie",
            position: 120,
            duration: 600
        )

        let entry = store.entry(for: "movie.mp4")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.title, "My Movie")
        XCTAssertEqual(entry?.position, 120)
        XCTAssertEqual(entry?.duration, 600)
        XCTAssertEqual(entry?.progressPercent, 20)
    }

    func testResumePositionReturnsSavedPosition() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "episode.mkv",
            title: "Episode",
            position: 245,
            duration: 1200
        )

        XCTAssertEqual(
            store.resumePosition(for: "episode.mkv"),
            245
        )
    }

    func testEarlyProgressDoesNotCreateAnEntry() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "short.mp4",
            title: "Short Video",
            position: 4,
            duration: 60
        )

        XCTAssertNil(store.entry(for: "short.mp4"))
    }

    func testEarlyProgressDoesNotOverwriteExistingProgress() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "movie.mp4",
            title: "My Movie",
            position: 150,
            duration: 600
        )

        store.save(
            mediaID: "movie.mp4",
            title: "My Movie",
            position: 3,
            duration: 600
        )

        XCTAssertEqual(
            store.entry(for: "movie.mp4")?.position,
            150
        )
    }

    func testCompletedVideoIsRemovedFromHistory() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "movie.mp4",
            title: "My Movie",
            position: 500,
            duration: 600
        )

        XCTAssertNotNil(store.entry(for: "movie.mp4"))

        store.save(
            mediaID: "movie.mp4",
            title: "My Movie",
            position: 590,
            duration: 600
        )

        XCTAssertNil(store.entry(for: "movie.mp4"))
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    func testHistoryPersistsBetweenStoreInstances() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "persisted.mp4",
            title: "Persisted Video",
            position: 90,
            duration: 300
        )

        let restoredStore = PlaybackHistoryStore(defaults: defaults)

        XCTAssertEqual(
            restoredStore.entry(for: "persisted.mp4")?.position,
            90
        )
    }

    func testRemovingHistoryDeletesOnlyRequestedEntry() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "first.mp4",
            title: "First",
            position: 30,
            duration: 300
        )

        store.save(
            mediaID: "second.mp4",
            title: "Second",
            position: 60,
            duration: 300
        )

        store.remove(mediaID: "first.mp4")

        XCTAssertNil(store.entry(for: "first.mp4"))
        XCTAssertNotNil(store.entry(for: "second.mp4"))
    }

    func testClearRemovesAllPlaybackHistory() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "first.mp4",
            title: "First",
            position: 30,
            duration: 300
        )

        store.save(
            mediaID: "second.mp4",
            title: "Second",
            position: 60,
            duration: 300
        )

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    func testInvalidPlaybackValuesAreIgnored() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.save(
            mediaID: "invalid.mp4",
            title: "Invalid",
            position: .nan,
            duration: 300
        )

        store.save(
            mediaID: "invalid-duration.mp4",
            title: "Invalid Duration",
            position: 30,
            duration: 0
        )

        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - Test Helpers

    private func makeStore() -> (
        PlaybackHistoryStore,
        UserDefaults,
        String
    ) {
        let suiteName = "KinetiqPlaybackHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)

        let store = PlaybackHistoryStore(defaults: defaults)

        return (store, defaults, suiteName)
    }
}