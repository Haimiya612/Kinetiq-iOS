import XCTest
@testable import Kinetiq

final class TaglineSelectorTests: XCTestCase {

    // MARK: - Tagline Tests

    func testSelectionDoesNotRepeatPreviousTagline() {
        let selected = TaglineSelector.next(
            previous: "Two",
            candidates: ["One", "Two", "Three"],
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
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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

    func testEarlyProgressDoesNotCreateEntry() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "short.mp4",
            title: "Short Video",
            position: 4,
            duration: 60
        )

        XCTAssertNil(store.entry(for: "short.mp4"))
    }

    func testEarlyProgressDoesNotOverwriteExistingProgress() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(
            mediaID: "persisted.mp4",
            title: "Persisted Video",
            position: 90,
            duration: 300
        )

        let restored = PlaybackHistoryStore(defaults: defaults)

        XCTAssertEqual(
            restored.entry(for: "persisted.mp4")?.position,
            90
        )
    }

    func testRemovingHistoryDeletesOnlyRequestedEntry() {
        let (store, defaults, suite) = makeHistoryStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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

    // MARK: - Playback Queue Tests

    @MainActor
    func testQueueStartsAtRequestedItem() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4"),
                queueItem("three.mp4")
            ],
            startingAt: "two.mp4"
        )

        XCTAssertEqual(queue.currentEntry?.id, "two.mp4")
        XCTAssertEqual(
            queue.upcomingEntries.map(\.id),
            ["three.mp4"]
        )
    }

    @MainActor
    func testAdvanceMovesToNextItem() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4"),
                queueItem("three.mp4")
            ],
            startingAt: "one.mp4"
        )

        let next = queue.advance()

        XCTAssertEqual(next?.id, "two.mp4")
        XCTAssertEqual(queue.currentEntry?.id, "two.mp4")
    }

    @MainActor
    func testQueueStopsAtEndWhenRepeatIsOff() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4")
            ],
            startingAt: "two.mp4"
        )

        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.currentEntry?.id, "two.mp4")
    }

    @MainActor
    func testRepeatAllWrapsToFirstItem() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4")
            ],
            startingAt: "two.mp4"
        )

        queue.repeatMode = .all

        XCTAssertEqual(queue.advance()?.id, "one.mp4")
        XCTAssertEqual(queue.currentEntry?.id, "one.mp4")
    }

    @MainActor
    func testRepeatOneKeepsCurrentItem() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4")
            ],
            startingAt: "one.mp4"
        )

        queue.repeatMode = .one

        XCTAssertEqual(queue.advance()?.id, "one.mp4")
        XCTAssertEqual(queue.currentEntry?.id, "one.mp4")
    }

    @MainActor
    func testPlayNextInsertsImmediatelyAfterCurrentItem() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4"),
                queueItem("three.mp4")
            ],
            startingAt: "one.mp4"
        )

        queue.playNext(queueItem("priority.mp4"))

        XCTAssertEqual(
            queue.entries.map(\.id),
            [
                "one.mp4",
                "priority.mp4",
                "two.mp4",
                "three.mp4"
            ]
        )
    }

    @MainActor
    func testEnqueueDoesNotCreateDuplicates() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4")
            ],
            startingAt: "one.mp4"
        )

        queue.enqueue(queueItem("two.mp4"))

        XCTAssertEqual(
            queue.entries.filter { $0.id == "two.mp4" }.count,
            1
        )
    }

    @MainActor
    func testRemovingCurrentQueueItemSelectsReplacement() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4"),
                queueItem("three.mp4")
            ],
            startingAt: "two.mp4"
        )

        queue.remove(mediaID: "two.mp4")

        XCTAssertEqual(queue.currentEntry?.id, "three.mp4")
        XCTAssertEqual(
            queue.entries.map(\.id),
            ["one.mp4", "three.mp4"]
        )
    }

    @MainActor
    func testQueuePersistsBetweenStoreInstances() {
        let (queue, defaults, suite) = makeQueueStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        queue.replaceQueue(
            with: [
                queueItem("one.mp4"),
                queueItem("two.mp4")
            ],
            startingAt: "two.mp4"
        )

        queue.repeatMode = .all

        let restored = PlaybackQueueStore(defaults: defaults)

        XCTAssertEqual(restored.currentEntry?.id, "two.mp4")
        XCTAssertEqual(restored.entries.count, 2)
        XCTAssertEqual(restored.repeatMode, .all)
    }

    // MARK: - Helpers

    private func makeHistoryStore() -> (
        PlaybackHistoryStore,
        UserDefaults,
        String
    ) {
        let suite = "KinetiqHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        return (
            PlaybackHistoryStore(defaults: defaults),
            defaults,
            suite
        )
    }

    @MainActor
    private func makeQueueStore() -> (
        PlaybackQueueStore,
        UserDefaults,
        String
    ) {
        let suite = "KinetiqQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        return (
            PlaybackQueueStore(defaults: defaults),
            defaults,
            suite
        )
    }

    @MainActor
    private func queueItem(_ name: String) -> PlaybackQueueEntry {
        PlaybackQueueEntry(
            id: name,
            title: name,
            fileURL: URL(fileURLWithPath: "/tmp/\(name)")
        )
    }
}