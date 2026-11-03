import XCTest
@testable import Kinetiq

// MARK: - Playback Queue Tests

final class PlaybackQueueStoreTests: XCTestCase {

    @MainActor
    func testRepeatModeDirectAssignmentPersists() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "two"
        )
        store.repeatMode = .all

        let restored = PlaybackQueueStore(defaults: defaults)
        XCTAssertEqual(restored.repeatMode, .all)
        XCTAssertEqual(restored.currentEntry?.id, "two")
    }

    @MainActor
    func testShuffleStateDirectAssignmentPersists() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(with: [item("one"), item("two")], startingAt: "one")
        store.isShuffled = true

        let restored = PlaybackQueueStore(defaults: defaults)
        XCTAssertTrue(restored.isShuffled)
        XCTAssertEqual(restored.currentEntry?.id, "one")
    }

    @MainActor
    func testPlayNextKeepsCurrentItemWhenMovingItemFromBeforeIt() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "two"
        )

        store.playNext(item("one"))

        XCTAssertEqual(store.currentEntry?.id, "two")
        XCTAssertEqual(store.entries.map(\.id), ["two", "one", "three"])
    }

    @MainActor
    func testPlayNextMovesItemFromAfterCurrentWithoutChangingCurrent() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "one"
        )

        store.playNext(item("three"))

        XCTAssertEqual(store.currentEntry?.id, "one")
        XCTAssertEqual(store.entries.map(\.id), ["one", "three", "two"])
    }

    @MainActor
    func testPlayNextCurrentItemDoesNotMoveOrDuplicateIt() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "two"
        )

        store.playNext(item("two"))

        XCTAssertEqual(store.currentEntry?.id, "two")
        XCTAssertEqual(store.entries.map(\.id), ["one", "two", "three"])
    }

    @MainActor
    func testMovePreservesCurrentEntryWhenAnotherItemMovesAcrossIt() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three"), item("four")],
            startingAt: "three"
        )

        store.move(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.entries.map(\.id), ["two", "three", "one", "four"])
        XCTAssertEqual(store.currentIndex, 1)
        XCTAssertEqual(store.currentEntry?.id, "three")
    }

    @MainActor
    func testMovePreservesCurrentEntryWhenCurrentItemMoves() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three"), item("four")],
            startingAt: "two"
        )

        store.move(from: IndexSet(integer: 1), to: 4)

        XCTAssertEqual(store.entries.map(\.id), ["one", "three", "four", "two"])
        XCTAssertEqual(store.currentIndex, 3)
        XCTAssertEqual(store.currentEntry?.id, "two")
    }

    @MainActor
    func testRepeatOneRepeatsOnCompletionButManualNextSkips() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "two"
        )
        store.repeatMode = .one

        XCTAssertEqual(store.advance()?.id, "two")
        XCTAssertEqual(store.currentEntry?.id, "two")

        XCTAssertEqual(store.advance(repeatingCurrent: false)?.id, "three")
        XCTAssertEqual(store.currentEntry?.id, "three")

        XCTAssertEqual(store.advance(repeatingCurrent: false)?.id, "one")
        XCTAssertEqual(store.currentEntry?.id, "one")
    }

    @MainActor
    func testRepeatAllWrapsAndRepeatOffStopsAtEnd() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(with: [item("one"), item("two")], startingAt: "two")
        XCTAssertNil(store.advance())
        XCTAssertEqual(store.currentEntry?.id, "two")

        store.repeatMode = .all
        XCTAssertEqual(store.advance()?.id, "one")
        XCTAssertEqual(store.currentEntry?.id, "one")
    }

    @MainActor
    func testRemovingCurrentEntrySelectsTheNextAvailableEntry() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.replaceQueue(
            with: [item("one"), item("two"), item("three")],
            startingAt: "two"
        )

        store.remove(mediaID: "two")

        XCTAssertEqual(store.entries.map(\.id), ["one", "three"])
        XCTAssertEqual(store.currentIndex, 1)
        XCTAssertEqual(store.currentEntry?.id, "three")
    }

    @MainActor
    private func makeStore() -> (PlaybackQueueStore, UserDefaults, String) {
        let suite = "KinetiqQueueRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PlaybackQueueStore(defaults: defaults), defaults, suite)
    }

    private func item(_ id: String) -> PlaybackQueueEntry {
        PlaybackQueueEntry(
            id: id,
            title: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).mp4")
        )
    }
}

// MARK: - Playback History Tests

final class PlaybackHistoryStoreTests: XCTestCase {

    func testNewStoreStartsWithEmptyHistory() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    func testSaveStoresProgressAndProvidesResumePosition() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "movie-1",
            title: "Example Movie",
            position: 35,
            duration: 100
        )

        let entry = store.entry(for: "movie-1")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.title, "Example Movie")
        XCTAssertEqual(entry?.position ?? 0, 35, accuracy: 0.001)
        XCTAssertEqual(entry?.duration ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(entry?.progress ?? 0, 0.35, accuracy: 0.001)
        XCTAssertEqual(entry?.progressPercent, 35)
        XCTAssertEqual(store.resumePosition(for: "movie-1"), 35, accuracy: 0.001)
        XCTAssertEqual(store.continueWatching.count, 1)
    }

    func testHistorySurvivesStoreRecreation() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "persistent-movie",
            title: "Persistent Movie",
            position: 42,
            duration: 120
        )

        let restoredStore = PlaybackHistoryStore(defaults: defaults)

        XCTAssertEqual(restoredStore.entries.count, 1)
        XCTAssertEqual(
            restoredStore.entry(for: "persistent-movie")?.title,
            "Persistent Movie"
        )
        XCTAssertEqual(
            restoredStore.resumePosition(for: "persistent-movie"),
            42,
            accuracy: 0.001
        )
    }

    func testSavingSameMediaReplacesPreviousEntry() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "movie-1",
            title: "Old Title",
            position: 20,
            duration: 100
        )

        store.save(
            mediaID: "movie-1",
            title: "Updated Title",
            position: 60,
            duration: 100
        )

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entry(for: "movie-1")?.title, "Updated Title")
        XCTAssertEqual(store.resumePosition(for: "movie-1"), 60, accuracy: 0.001)
    }

    func testProgressBelowEightSecondsIsNotSaved() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "movie-1",
            title: "Example Movie",
            position: 7.9,
            duration: 100
        )

        XCTAssertNil(store.entry(for: "movie-1"))
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    func testCompletedMediaIsAutomaticallyRemoved() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "movie-1",
            title: "Example Movie",
            position: 40,
            duration: 100
        )

        XCTAssertNotNil(store.entry(for: "movie-1"))

        store.save(
            mediaID: "movie-1",
            title: "Example Movie",
            position: 97,
            duration: 100
        )

        XCTAssertNil(store.entry(for: "movie-1"))
        XCTAssertEqual(store.resumePosition(for: "movie-1"), 0)
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    func testInvalidProgressValuesAreIgnored() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "",
            title: "Movie",
            position: 10,
            duration: 100
        )

        store.save(
            mediaID: "empty-title",
            title: "",
            position: 10,
            duration: 100
        )

        store.save(
            mediaID: "negative-position",
            title: "Movie",
            position: -1,
            duration: 100
        )

        store.save(
            mediaID: "zero-duration",
            title: "Movie",
            position: 10,
            duration: 0
        )

        store.save(
            mediaID: "nan-position",
            title: "Movie",
            position: .nan,
            duration: 100
        )

        store.save(
            mediaID: "infinite-duration",
            title: "Movie",
            position: 10,
            duration: .infinity
        )

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveAndClearArePersisted() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "movie-1",
            title: "Movie One",
            position: 20,
            duration: 100
        )

        store.save(
            mediaID: "movie-2",
            title: "Movie Two",
            position: 30,
            duration: 100
        )

        store.remove(mediaID: "movie-1")

        let afterRemoval = PlaybackHistoryStore(defaults: defaults)

        XCTAssertNil(afterRemoval.entry(for: "movie-1"))
        XCTAssertNotNil(afterRemoval.entry(for: "movie-2"))

        afterRemoval.clear()

        let afterClear = PlaybackHistoryStore(defaults: defaults)
        XCTAssertTrue(afterClear.entries.isEmpty)
    }

    func testLoadingFiltersCompletedAndInvalidEntries() throws {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Date()

        let validEntry = PlaybackHistoryEntry(
            id: "valid",
            title: "Valid Movie",
            position: 40,
            duration: 100,
            lastPlayedAt: now
        )

        let completedEntry = PlaybackHistoryEntry(
            id: "completed",
            title: "Completed Movie",
            position: 98,
            duration: 100,
            lastPlayedAt: now
        )

        let invalidEntry = PlaybackHistoryEntry(
            id: "invalid",
            title: "Invalid Movie",
            position: 10,
            duration: 0,
            lastPlayedAt: now
        )

        let data = try JSONEncoder().encode([
            validEntry,
            completedEntry,
            invalidEntry
        ])

        defaults.set(data, forKey: AppStorageKey.playbackHistory)

        let restoredStore = PlaybackHistoryStore(defaults: defaults)

        XCTAssertEqual(restoredStore.entries.map(\.id), ["valid"])
        XCTAssertNotNil(restoredStore.entry(for: "valid"))
        XCTAssertNil(restoredStore.entry(for: "completed"))
        XCTAssertNil(restoredStore.entry(for: "invalid"))

        // Keep the original store alive so this test also confirms that
        // initializing another store does not mutate the first one.
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCorruptStoredDataFailsSafely() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            Data("{ invalid json".utf8),
            forKey: AppStorageKey.playbackHistory
        )

        let restoredStore = PlaybackHistoryStore(defaults: defaults)

        XCTAssertTrue(restoredStore.entries.isEmpty)
        XCTAssertTrue(restoredStore.continueWatching.isEmpty)

        // The already-created store remains independent of the restored one.
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testHistoryIsLimitedToThirtyEntries() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        for index in 0..<35 {
            store.save(
                mediaID: "movie-\(index)",
                title: "Movie \(index)",
                position: 10 + Double(index),
                duration: 1_000
            )
        }

        XCTAssertEqual(store.entries.count, 30)
        XCTAssertEqual(
            Set(store.entries.map(\.id)).count,
            30
        )
    }

    private func makeHistoryStore() -> (PlaybackHistoryStore, UserDefaults, String) {
        let suite = "KinetiqPlaybackHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        return (
            PlaybackHistoryStore(defaults: defaults),
            defaults,
            suite
        )
    }
}