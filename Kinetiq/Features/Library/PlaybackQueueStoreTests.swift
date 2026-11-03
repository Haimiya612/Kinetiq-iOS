import XCTest
@testable import Kinetiq

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
