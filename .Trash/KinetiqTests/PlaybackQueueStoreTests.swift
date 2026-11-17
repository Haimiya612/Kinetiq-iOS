import XCTest
import UIKit
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

// MARK: - Local Media Thumbnail Cache Tests

final class LocalMediaThumbnailCacheTests: XCTestCase {

    func testThumbnailPersistsAcrossCacheInstances() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "persistent.mp4",
            in: environment.mediaDirectory
        )

        let counter = ThumbnailGenerationCounter()
        let generatedImage = makeTestImage()

        let firstCache = makeCache(
            environment: environment,
            counter: counter,
            image: generatedImage
        )

        let firstImage = await firstCache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(firstImage)

        let persisted = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            persisted,
            "The generated thumbnail should be saved as an image and metadata file."
        )

        // A new cache instance simulates an app restart.
        let restoredCache = LocalMediaThumbnailCache(
            localMediaDirectory: environment.mediaDirectory,
            thumbnailDirectory: environment.thumbnailDirectory
        ) { _ in
            counter.increment()
            return nil
        }

        let restoredImage = await restoredCache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(restoredImage)
        XCTAssertEqual(
            counter.value,
            1,
            "The restored cache should load the saved thumbnail instead of generating it again."
        )
    }

    func testChangedMediaFileRegeneratesThumbnail() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "changed.mp4",
            in: environment.mediaDirectory,
            contents: "original"
        )

        let counter = ThumbnailGenerationCounter()
        let cache = makeCache(
            environment: environment,
            counter: counter,
            image: makeTestImage()
        )

        let firstImage = await cache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(firstImage)

        let initialPersistence = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            initialPersistence,
            "The initial thumbnail and metadata must both be persisted before the media is changed."
        )

        let metadataFiles = try FileManager.default.contentsOfDirectory(
            at: environment.thumbnailDirectory,
            includingPropertiesForKeys: nil
        )

        let metadataURL = try XCTUnwrap(
            metadataFiles.first {
                $0.pathExtension.lowercased() == "json"
            },
            "The cache metadata file should exist after persistence completes."
        )

        let originalMetadata = try Data(contentsOf: metadataURL)

        // Change the file size so its fingerprint must change.
        try Data("updated media contents that are longer".utf8).write(
            to: mediaURL,
            options: .atomic
        )

        let updatedImage = await cache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(updatedImage)
        XCTAssertEqual(
            counter.value,
            2,
            "A changed media file must not reuse the old generated frame."
        )

        let metadataUpdated = await waitForMetadataChange(
            in: environment.thumbnailDirectory,
            from: originalMetadata
        )

        XCTAssertTrue(
            metadataUpdated,
            "The persisted metadata must be updated for the new file fingerprint."
        )
    }

    func testInvalidatingDeletedMediaRemovesDiskArtifacts() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "deleted.mp4",
            in: environment.mediaDirectory
        )

        let cache = makeCache(
            environment: environment,
            counter: ThumbnailGenerationCounter(),
            image: makeTestImage()
        )

        let generatedImage = await cache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(generatedImage)

        let persisted = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(persisted)

        try FileManager.default.removeItem(at: mediaURL)

        let invalidation = cache.invalidate(
            mediaID: mediaURL.lastPathComponent
        )
        await invalidation.value

        let artifactsRemoved = await waitForCacheArtifacts(
            expectedImages: 0,
            expectedMetadata: 0,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            artifactsRemoved,
            "Deleting local media and invalidating it must remove both thumbnail files."
        )
    }

    func testOrphanCleanupRemovesOnlyDeletedMediaThumbnails() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let retainedURL = try makeMediaFile(
            named: "retained.mp4",
            in: environment.mediaDirectory
        )

        let deletedURL = try makeMediaFile(
            named: "orphan.mp4",
            in: environment.mediaDirectory
        )

        let cache = makeCache(
            environment: environment,
            counter: ThumbnailGenerationCounter(),
            image: makeTestImage()
        )

        let retainedImage = await cache.image(
            for: retainedURL.lastPathComponent,
            url: retainedURL
        )

        let deletedImage = await cache.image(
            for: deletedURL.lastPathComponent,
            url: deletedURL
        )

        XCTAssertNotNil(retainedImage)
        XCTAssertNotNil(deletedImage)

        let allPersisted = await waitForCacheArtifacts(
            expectedImages: 2,
            expectedMetadata: 2,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(allPersisted)

        try FileManager.default.removeItem(at: deletedURL)

        let cleanup = cache.removeOrphans()
        await cleanup.value

        let orphanRemoved = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            orphanRemoved,
            "Cleanup should remove only the deleted media item's thumbnail and metadata."
        )
    }

    func testRemovingContinueWatchingEntryDoesNotDeleteThumbnail() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "completed.mp4",
            in: environment.mediaDirectory
        )

        let cache = makeCache(
            environment: environment,
            counter: ThumbnailGenerationCounter(),
            image: makeTestImage()
        )

        let generatedImage = await cache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(generatedImage)

        let persisted = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(persisted)

        let suite = "KinetiqThumbnailHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let history = PlaybackHistoryStore(defaults: defaults)

        history.save(
            mediaID: mediaURL.lastPathComponent,
            title: "Completed Movie",
            position: 40,
            duration: 100
        )

        XCTAssertNotNil(history.entry(for: mediaURL.lastPathComponent))

        // Completing playback removes the history entry, not the media file.
        history.save(
            mediaID: mediaURL.lastPathComponent,
            title: "Completed Movie",
            position: 97,
            duration: 100
        )

        XCTAssertNil(history.entry(for: mediaURL.lastPathComponent))

        // HomeView runs orphan cleanup when Continue Watching changes.
        let cleanup = cache.removeOrphans()
        await cleanup.value

        let thumbnailRetained = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            thumbnailRetained,
            "A thumbnail must remain while its local media file still exists."
        )
    }

    func testConcurrentRequestsShareOneGeneration() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "concurrent.mp4",
            in: environment.mediaDirectory
        )

        let counter = ThumbnailGenerationCounter()
        let generatedImage = makeTestImage()

        let cache = LocalMediaThumbnailCache(
            localMediaDirectory: environment.mediaDirectory,
            thumbnailDirectory: environment.thumbnailDirectory
        ) { _ in
            counter.increment()

            // Keep generation open long enough for concurrent requests
            // to join the same pending operation.
            Thread.sleep(forTimeInterval: 0.2)

            return generatedImage
        }

        let mediaID = mediaURL.lastPathComponent

        let results = await withTaskGroup(
            of: Bool.self,
            returning: [Bool].self
        ) { group in
            for _ in 0..<16 {
                group.addTask {
                    await cache.image(
                        for: mediaID,
                        url: mediaURL
                    ) != nil
                }
            }

            var values: [Bool] = []

            for await value in group {
                values.append(value)
            }

            return values
        }

        XCTAssertEqual(results.count, 16)
        XCTAssertTrue(results.allSatisfy { $0 })

        XCTAssertEqual(
            counter.value,
            1,
            "Concurrent requests for the same media revision should share one generation."
        )

        let persisted = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(persisted)
    }

    func testFilesOutsideManagedMediaDirectoryAreRejected() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let outsideURL = environment.root.appendingPathComponent("outside.mp4")
        try Data("not managed media".utf8).write(to: outsideURL)

        let counter = ThumbnailGenerationCounter()

        let cache = makeCache(
            environment: environment,
            counter: counter,
            image: makeTestImage()
        )

        let result = await cache.image(
            for: outsideURL.lastPathComponent,
            url: outsideURL
        )

        XCTAssertNil(result)
        XCTAssertEqual(counter.value, 0)
    }

    func testMissingMediaDirectoryDoesNotDeleteExistingCache() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }

        let mediaURL = try makeMediaFile(
            named: "preserved.mp4",
            in: environment.mediaDirectory
        )

        let cache = makeCache(
            environment: environment,
            counter: ThumbnailGenerationCounter(),
            image: makeTestImage()
        )

        let generatedImage = await cache.image(
            for: mediaURL.lastPathComponent,
            url: mediaURL
        )

        XCTAssertNotNil(generatedImage)

        let persisted = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(persisted)

        try FileManager.default.removeItem(at: environment.mediaDirectory)

        let cleanup = cache.removeOrphans()
        await cleanup.value

        let cachePreserved = await waitForCacheArtifacts(
            expectedImages: 1,
            expectedMetadata: 1,
            in: environment.thumbnailDirectory
        )

        XCTAssertTrue(
            cachePreserved,
            "An inaccessible media directory must not be treated as an empty library."
        )
    }

    // MARK: Test Helpers

    private struct TestEnvironment {
        let root: URL
        let mediaDirectory: URL
        let thumbnailDirectory: URL
    }

    private func makeEnvironment() throws -> TestEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KinetiqThumbnailTests-\(UUID().uuidString)",
                isDirectory: true
            )

        let mediaDirectory = root.appendingPathComponent(
            "KinetiqMedia",
            isDirectory: true
        )

        let thumbnailDirectory = root.appendingPathComponent(
            "Thumbnails",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: mediaDirectory,
            withIntermediateDirectories: true
        )

        try FileManager.default.createDirectory(
            at: thumbnailDirectory,
            withIntermediateDirectories: true
        )

        return TestEnvironment(
            root: root,
            mediaDirectory: mediaDirectory,
            thumbnailDirectory: thumbnailDirectory
        )
    }

    private func makeMediaFile(
        named name: String,
        in directory: URL,
        contents: String = "test video payload"
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)

        try Data(contents.utf8).write(
            to: url,
            options: .atomic
        )

        return url
    }

    private func makeCache(
        environment: TestEnvironment,
        counter: ThumbnailGenerationCounter,
        image: UIImage
    ) -> LocalMediaThumbnailCache {
        LocalMediaThumbnailCache(
            localMediaDirectory: environment.mediaDirectory,
            thumbnailDirectory: environment.thumbnailDirectory
        ) { _ in
            counter.increment()
            return image
        }
    }

    private func makeTestImage() -> UIImage {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(
                CGRect(origin: .zero, size: size)
            )
        }
    }

    /// Waits for completed cache artifacts only.
    ///
    /// Atomic writes can temporarily create staging files in the directory.
    /// Counting every directory entry can therefore report that persistence
    /// is complete before the final .jpg or .json file is visible.
    private func waitForCacheArtifacts(
        expectedImages: Int,
        expectedMetadata: Int,
        in directory: URL,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            let imageCount = files.filter {
                $0.pathExtension.lowercased() == "jpg"
            }.count

            let metadataCount = files.filter {
                $0.pathExtension.lowercased() == "json"
            }.count

            if imageCount == expectedImages,
               metadataCount == expectedMetadata {
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        let imageCount = files.filter {
            $0.pathExtension.lowercased() == "jpg"
        }.count

        let metadataCount = files.filter {
            $0.pathExtension.lowercased() == "json"
        }.count

        return imageCount == expectedImages
            && metadataCount == expectedMetadata
    }

    private func waitForMetadataChange(
        in directory: URL,
        from originalData: Data,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let files = (
                try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
            ) ?? []

            if let metadataURL = files.first(where: {
                $0.pathExtension.lowercased() == "json"
            }),
            let currentData = try? Data(contentsOf: metadataURL),
            currentData != originalData {
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }
}

// MARK: - Thread-Safe Test Counter

private final class ThumbnailGenerationCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }
}