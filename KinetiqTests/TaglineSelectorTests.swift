import XCTest
import AVFoundation
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

// MARK: - Module Episode Progress (Batch 03D)

final class ModuleEpisodeProgressTests: XCTestCase {
    private let storageKey = "kinetiq.modules.animeCollection.v1"

    @MainActor
    func testLegacyCollectionMigratesWithoutLosingFavoriteOrResume() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy: [[String: Any]] = [[
            "sourceID": "source", "sourceName": "Original Source",
            "animeID": "anime", "title": "Original Title", "href": "/anime",
            "artworkURL": "https://example.invalid/poster.jpg",
            "isFavorite": true, "savedAt": 100.0,
            "latestEpisodeID": "one", "latestEpisodeNumber": "1",
            "latestLanguage": "sub", "latestEpisodeDate": 110.0,
            "lastPlaybackPosition": 120.0, "lastPlaybackDuration": 600.0,
            "lastPlaybackDate": 120.0
        ]]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: storageKey)

        let store = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(store.favorites.first?.sourceName, "Original Source")
        XCTAssertEqual(store.favorites.first?.artworkURL, "https://example.invalid/poster.jpg")
        XCTAssertEqual(resume(store, episode: "one"), 120)
        XCTAssertEqual(store.continueWatching.first?.latestEpisodeID, "one")

        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(resume(restored, episode: "one"), 120)
        XCTAssertEqual(restored.entries.first?.episodeProgress?.count, 1)
    }

    @MainActor
    func test03AFavoriteWithoutPlaybackDoesNotInventProgress() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy: [[String: Any]] = [[
            "sourceID": "source", "sourceName": "Source", "animeID": "anime",
            "title": "Anime", "href": "/anime", "isFavorite": true, "savedAt": 100.0,
            "latestEpisodeID": "one", "latestEpisodeNumber": "1", "latestLanguage": "sub"
        ]]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: storageKey)
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertTrue(store.continueWatching.isEmpty)
        XCTAssertEqual(resume(store, episode: "one"), 0)
    }

    @MainActor
    func testEpisodeAndLanguagePositionsSurviveSwitchingAndRestart() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", language: "sub", position: 120)
        save(store, episode: "two", language: "sub", position: 240)
        save(store, episode: "one", language: "dub", position: 60)
        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(resume(restored, episode: "one", language: "sub"), 120)
        XCTAssertEqual(resume(restored, episode: "two", language: "sub"), 240)
        XCTAssertEqual(resume(restored, episode: "one", language: "dub"), 60)
    }

    @MainActor
    func testSourcesAndTitlesDoNotShareEpisodeProgress() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", position: 120, sourceID: "a", animeID: "bc")
        save(store, episode: "one", position: 240, sourceID: "ab", animeID: "c")
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.resumePosition(sourceID: "a", animeID: "bc",
                                            episodeID: "one", language: "sub"), 120)
        XCTAssertEqual(store.resumePosition(sourceID: "ab", animeID: "c",
                                            episodeID: "one", language: "sub"), 240)
        XCTAssertEqual(store.resumePosition(sourceID: "a", animeID: "c",
                                            episodeID: "one", language: "sub"), 0)
    }

    @MainActor
    func testSelectingAnotherEpisodeKeepsEarlierUnfinishedCard() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", position: 120)
        store.recordEpisode(sourceID: "source", sourceName: "Source", anime: anime(),
                            episode: episode("two"), language: "sub")
        XCTAssertEqual(store.recentEpisodes(for: "source").first?.latestEpisodeID, "two")
        XCTAssertEqual(store.continueWatching.first?.latestEpisodeID, "one")
        XCTAssertEqual(resume(store, episode: "one"), 120)
    }

    @MainActor
    func testCompletionThresholdAndNextUnwatchedEpisode() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", position: 581) // Under 97% of 600.
        XCTAssertEqual(store.continueWatching.count, 1)
        save(store, episode: "one", position: 582)
        XCTAssertTrue(store.continueWatching.isEmpty)
        XCTAssertEqual(resume(store, episode: "one"), 0)
        let next = store.continuation(sourceID: "source", animeID: "anime",
                                      episodes: [episode("one"), episode("two")])
        XCTAssertEqual(next?.episode.id, "two")
        XCTAssertEqual(next?.isResume, false)
    }

    @MainActor
    func testFinishedPlaybackRemainsWatchedAfterALateLowerTimestamp() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        store.recordPlayback(sourceID: "source", sourceName: "Source", anime: anime(),
                             episode: episode("one"), language: "sub",
                             position: 500, duration: 600, finished: true)
        save(store, episode: "one", position: 570)
        XCTAssertTrue(store.hasWatched(sourceID: "source", animeID: "anime", episode: episode("one")))
        XCTAssertEqual(resume(store, episode: "one"), 0)
        XCTAssertTrue(store.continueWatching.isEmpty)
    }

    @MainActor
    func testManualWatchedAndResetAffectOnlySelectedLanguage() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", language: "dub", position: 60)
        mark(store, watched: true, episode: "one", language: "sub")
        XCTAssertTrue(store.hasWatched(sourceID: "source", animeID: "anime", episode: episode("one")))
        XCTAssertEqual(store.progress(sourceID: "source", animeID: "anime",
                                      episodeID: "one", language: "sub")?.duration, 0)
        mark(store, watched: false, episode: "one", language: "sub")
        XCTAssertFalse(store.hasWatched(sourceID: "source", animeID: "anime", episode: episode("one")))
        XCTAssertEqual(resume(store, episode: "one", language: "sub"), 0)
        XCTAssertEqual(resume(store, episode: "one", language: "dub"), 60)
        XCTAssertEqual(store.continueWatching.first?.latestLanguage, "dub")
    }

    @MainActor
    func testHidingContinueWatchingPreservesFavoriteRecentAndResumeAcrossRestart() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        store.toggleFavorite(sourceID: "source", sourceName: "Source", anime: anime())
        save(store, episode: "one", position: 120)
        store.hideFromContinueWatching(sourceID: "source", animeID: "anime")
        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertTrue(restored.continueWatching.isEmpty)
        XCTAssertEqual(restored.favorites.count, 1)
        XCTAssertEqual(restored.recentEpisodes(for: "source").count, 1)
        XCTAssertEqual(resume(restored, episode: "one"), 120)
        save(restored, episode: "one", position: 130)
        XCTAssertEqual(restored.continueWatching.count, 1)
    }

    @MainActor
    func testRemovingFavoriteOrRecentDoesNotDeleteEpisodeProgress() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        store.toggleFavorite(sourceID: "source", sourceName: "Source", anime: anime())
        save(store, episode: "one", position: 120)
        store.toggleFavorite(sourceID: "source", sourceName: "Source", anime: anime())
        store.removeRecent(sourceID: "source", animeID: "anime")
        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertTrue(restored.favorites.isEmpty)
        XCTAssertTrue(restored.recentEpisodes(for: "source").isEmpty)
        XCTAssertTrue(restored.continueWatching.isEmpty)
        XCTAssertEqual(resume(restored, episode: "one"), 120)
    }

    @MainActor
    func testContinuationResumesAvailableProgressBeforeChoosingNewEpisode() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "two", language: "dub", position: 80)
        let choice = store.continuation(sourceID: "source", animeID: "anime",
                                        episodes: [episode("one"), episode("two")])
        XCTAssertEqual(choice?.episode.id, "two")
        XCTAssertEqual(choice?.language, "dub")
        XCTAssertEqual(choice?.resumePosition, 80)
    }

    @MainActor
    func testContinuationSkipsMissingEpisodesUnavailableLanguagesAndUsesSourceOrder() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "gone", language: "dub", position: 80)
        let unavailable = ModuleAnimeEpisode(id: "none", number: "0", href: "/none",
                                              subAvailable: false, dubAvailable: false)
        let subOnly = ModuleAnimeEpisode(id: "gone", number: "Special", href: "/gone",
                                         subAvailable: true, dubAvailable: false)
        let choice = store.continuation(sourceID: "source", animeID: "anime",
                                        episodes: [unavailable, subOnly, episode("one")])
        XCTAssertEqual(choice?.episode.id, "gone")
        XCTAssertEqual(choice?.language, "sub")
        XCTAssertEqual(choice?.resumePosition, 0)
        XCTAssertNil(store.continuation(sourceID: "source", animeID: "anime", episodes: []))
    }

    @MainActor
    func testAllWatchedHasNoFabricatedNextEpisode() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        mark(store, watched: true, episode: "one", language: "sub")
        XCTAssertNil(store.continuation(sourceID: "source", animeID: "anime",
                                        episodes: [episode("one")]))
    }

    @MainActor
    func testInvalidPlaybackCannotCreateOrOverwriteProgress() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        save(store, episode: "one", position: 120)
        for bad in [Double.nan, Double.infinity, -1, 1000] {
            save(store, episode: "one", position: bad)
        }
        save(store, episode: "one", language: "unknown", position: 200)
        store.recordPlayback(sourceID: "source", sourceName: "Source", anime: anime(),
                             episode: episode("one"), language: "sub",
                             position: 200, duration: .infinity)
        XCTAssertEqual(resume(store, episode: "one"), 120)
        XCTAssertEqual(store.entries.first?.episodeProgress?.count, 1)
    }

    @MainActor
    func testRestoreDiscardsInvalidRecordsAndKeepsNewestDuplicate() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = ModuleAnimeCollectionStore(defaults: defaults)
        save(seed, episode: "one", position: 120)
        var entry = try XCTUnwrap(seed.entries.first)
        var first = try XCTUnwrap(entry.episodeProgress?.first)
        first.updatedAt = Date(timeIntervalSince1970: 1)
        var newer = first
        newer.position = 240
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        var invalid = first
        invalid.position = -10
        invalid.updatedAt = Date(timeIntervalSince1970: 3)
        entry.episodeProgress = [first, newer, invalid]
        defaults.set(try JSONEncoder().encode([entry]), forKey: storageKey)
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(resume(store, episode: "one"), 240)
        XCTAssertEqual(store.entries.first?.episodeProgress?.count, 1)
    }

    @MainActor
    func testExplicitEmptyProgressDoesNotRemigrateLegacySummary() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = ModuleAnimeCollectionStore(defaults: defaults)
        save(seed, episode: "one", position: 120)
        var entry = try XCTUnwrap(seed.entries.first)
        entry.episodeProgress = []
        defaults.set(try JSONEncoder().encode([entry]), forKey: storageKey)
        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(resume(restored, episode: "one"), 0)
        XCTAssertTrue(restored.continueWatching.isEmpty)
    }

    @MainActor
    func testRestoreBoundsProgressAndRetainsNewestRecords() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = ModuleAnimeCollectionStore(defaults: defaults)
        save(seed, episode: "one", position: 120)
        var entry = try XCTUnwrap(seed.entries.first)
        entry.episodeProgress = (0..<8_005).map { index in
            ModuleEpisodeProgress(episodeID: "episode-\(index)", episodeNumber: "\(index)",
                                  language: "sub", position: 120, duration: 600,
                                  isWatched: false, updatedAt: Date(timeIntervalSince1970: Double(index)))
        }
        defaults.set(try JSONEncoder().encode([entry]), forKey: storageKey)
        let restored = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertEqual(restored.entries.first?.episodeProgress?.count, 8_000)
        XCTAssertEqual(resume(restored, episode: "episode-8004"), 120)
        XCTAssertEqual(resume(restored, episode: "episode-0"), 0)
    }

    @MainActor
    func testMalformedStorageIsNotOverwrittenOnInitialization() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("invalid json".utf8)
        defaults.set(data, forKey: storageKey)
        let store = ModuleAnimeCollectionStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(defaults.data(forKey: storageKey), data)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "KinetiqEpisodeProgressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func anime(_ id: String = "anime") -> ModuleAnimeItem {
        ModuleAnimeItem(id: id, title: "Anime", href: "/anime", imageURL: nil)
    }

    private func episode(_ id: String) -> ModuleAnimeEpisode {
        ModuleAnimeEpisode(id: id, number: id, href: "/episodes/\(id)",
                           subAvailable: true, dubAvailable: true)
    }

    @MainActor
    private func save(
        _ store: ModuleAnimeCollectionStore, episode id: String,
        language: String = "sub", position: Double,
        sourceID: String = "source", animeID: String = "anime"
    ) {
        store.recordPlayback(sourceID: sourceID, sourceName: "Source", anime: anime(animeID),
                             episode: episode(id), language: language,
                             position: position, duration: 600)
    }

    @MainActor
    private func resume(
        _ store: ModuleAnimeCollectionStore, episode: String, language: String = "sub"
    ) -> Double {
        store.resumePosition(sourceID: "source", animeID: "anime",
                             episodeID: episode, language: language)
    }

    @MainActor
    private func mark(
        _ store: ModuleAnimeCollectionStore, watched: Bool,
        episode id: String, language: String
    ) {
        store.setWatched(watched, sourceID: "source", sourceName: "Source", anime: anime(),
                         episode: episode(id), language: language)
    }
}

// MARK: - Remote Module Subtitles (Batch 03E)

final class ModuleRemoteSubtitleTests: XCTestCase {
    private let baseURL = URL(string: "https://source.example.invalid/")!

    func testLegacyDirectAndFlatPairStreamsRemainUnchanged() throws {
        let cases: [Any] = ["https://cdn.example.invalid/video.m3u8", ["Main", "https://cdn.example.invalid/video.m3u8"]]
        for value in cases {
            let streams = try ModuleRuntimeDecoder.streams(from: value, title: "Episode", baseURL: baseURL)
            XCTAssertEqual(streams.count, 1)
            XCTAssertEqual(streams[0].url.absoluteString, "https://cdn.example.invalid/video.m3u8")
            XCTAssertTrue(streams[0].subtitles.isEmpty)
        }
    }

    func testRootSubtitleMetadataIsAttachedToFlatStreamPair() throws {
        let result: [String: Any] = [
            "streams": ["Main", "https://cdn.example.invalid/video.m3u8"],
            "subtitles": [["file": "/captions/en.vtt", "label": "English", "srclang": "en_US"]]
        ]
        let stream = try ModuleRuntimeDecoder.stream(from: result, title: "Episode", baseURL: baseURL)
        XCTAssertEqual(stream.label, "Main")
        XCTAssertEqual(stream.subtitles.count, 1)
        XCTAssertEqual(stream.subtitles.first?.url.absoluteString, "https://source.example.invalid/captions/en.vtt")
        XCTAssertEqual(stream.subtitles.first?.language, "en-us")
        XCTAssertEqual(stream.subtitles.first?.format, .vtt)
    }

    func testServerSpecificTracksAndGlobalTracksAreMergedWithoutDuplicates() throws {
        let track: [String: Any] = ["url": "https://cdn.example.invalid/en.srt", "label": "English", "lang": "en"]
        let result: [String: Any] = [
            "sources": [["url": "https://cdn.example.invalid/video.mp4", "tracks": [track]]],
            "subtitles": [track, ["url": "https://cdn.example.invalid/de.vtt", "label": "German", "lang": "de"]]
        ]
        let stream = try ModuleRuntimeDecoder.stream(from: result, title: "Episode", baseURL: baseURL)
        XCTAssertEqual(stream.subtitles.map(\.language), ["en", "de"])
    }

    func testInvalidAndUnsupportedTracksDoNotInvalidateVideo() throws {
        let result: [String: Any] = [
            "url": "https://cdn.example.invalid/video.mp4",
            "tracks": [
                ["file": "http://cdn.example.invalid/en.vtt"],
                ["file": "https://user:password@cdn.example.invalid/en.vtt"],
                ["file": "https://cdn.example.invalid/en.vtt", "kind": "thumbnails"],
                ["file": "https://cdn.example.invalid/en.ass"],
                ["file": "https://cdn.example.invalid/en.m3u8"],
                ["file": "https://cdn.example.invalid/en.vtt", "kind": "captions"]
            ]
        ]
        let streams = try ModuleRuntimeDecoder.streams(from: result, title: "Episode", baseURL: baseURL)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].subtitles.count, 1)
    }

    func testSubtitleHeadersAreInheritedOnlyOnTheVideoOrigin() throws {
        let result: [String: Any] = [
            "url": "https://cdn.example.invalid/video.mp4",
            "headers": ["Authorization": "opaque", "Cookie": "video=secret", "User-Agent": "Kinetiq"],
            "subtitles": [
                ["url": "https://cdn.example.invalid/en.vtt", "label": "Same"],
                ["url": "https://other.example.invalid/en.vtt", "label": "Other", "headers": ["Referer": "https://source.example.invalid/"]]
            ]
        ]
        let stream = try ModuleRuntimeDecoder.stream(from: result, title: "Episode", baseURL: baseURL)
        XCTAssertEqual(stream.subtitles[0].headers["authorization"], "opaque")
        XCTAssertNil(stream.subtitles[1].headers["authorization"])
        XCTAssertNil(stream.subtitles[1].headers["cookie"])
        XCTAssertEqual(stream.subtitles[1].headers["referer"], "https://source.example.invalid/")
    }

    func testTrackCountIsBoundedAndSignedURLsAreNotLabelsOrIDs() throws {
        let tracks = (0..<60).map { index in
            ["url": "https://cdn.example.invalid/\(index).vtt?token=opaque", "label": "https://secret.example.invalid/?token=opaque"]
        }
        let result: [String: Any] = ["url": "https://cdn.example.invalid/video.mp4", "subtitles": tracks]
        let stream = try ModuleRuntimeDecoder.stream(from: result, title: "Episode", baseURL: baseURL)
        XCTAssertEqual(stream.subtitles.count, 24)
        XCTAssertTrue(stream.subtitles.allSatisfy { $0.label == "Source subtitles" && !$0.id.contains("opaque") })
    }

    func testUnsafeHeadersAreDiscardedAndCaseIsNormalized() {
        let headers = ModuleSubtitleRequestPolicy.cleanHeaders([
            "Authorization": "opaque", "Host": "wrong.invalid", "X-Bad": "a\r\nInjected: value",
            "Invalid Name": "value", "Content-Length": "500", "Referer": "https://source.example.invalid/"
        ])
        XCTAssertEqual(headers, ["authorization": "opaque", "referer": "https://source.example.invalid/"])
    }

    func testCrossOriginRedirectDropsAllSourceHeadersAndCookies() throws {
        var track = makeTrack("en", headers: ["Authorization": "opaque", "Cookie": "session=opaque", "Referer": "https://source.example.invalid/"])
        track.cookies = [ModuleStreamCookie(name: "session", value: "opaque", domain: ".example.invalid", path: "/", isSecure: true)]
        let same = try ModuleSubtitleRequestPolicy.request(for: track, destination: URL(string: "https://captions.example.invalid/new.vtt")!)
        XCTAssertEqual(same.value(forHTTPHeaderField: "Authorization"), "opaque")
        let other = try ModuleSubtitleRequestPolicy.request(for: track, destination: URL(string: "https://other.example.invalid/new.vtt")!)
        XCTAssertNil(other.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(other.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(other.value(forHTTPHeaderField: "Referer"))
        XCTAssertEqual(other.httpMethod, "GET")
        XCTAssertNotNil(other.value(forHTTPHeaderField: "Accept"))
    }

    func testRedirectDowngradeAndEmbeddedCredentialsAreRejected() {
        let track = makeTrack("en")
        for target in ["http://captions.example.invalid/en.vtt", "https://name:secret@captions.example.invalid/en.vtt", "file:///tmp/subtitles.vtt"] {
            XCTAssertThrowsError(try ModuleSubtitleRequestPolicy.request(for: track, destination: URL(string: target)!))
        }
    }

    func testCookiePathAndDomainAreRespected() throws {
        var track = makeTrack("en")
        track.cookies = [
            ModuleStreamCookie(name: "yes", value: "1", domain: "captions.example.invalid", path: "/", isSecure: true),
            ModuleStreamCookie(name: "otherPath", value: "2", domain: "captions.example.invalid", path: "/private", isSecure: true),
            ModuleStreamCookie(name: "otherDomain", value: "3", domain: "other.example.invalid", path: "/", isSecure: true)
        ]
        let request = try ModuleSubtitleRequestPolicy.request(for: track)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "yes=1")
    }

    func testSRTAndVTTParseWithCueBoundaries() throws {
        let srt = Data("1\n00:00:01,000 --> 00:00:03,000\nHello\n\n2\n00:00:04,000 --> 00:00:06,000\nWorld\n".utf8)
        let first = try ModuleSubtitleLoader.parse(data: srt, format: .srt, contentType: "text/plain")
        XCTAssertNil(first.text(at: 0.9))
        XCTAssertEqual(first.text(at: 1), "Hello")
        XCTAssertNil(first.text(at: 3))
        XCTAssertEqual(first.text(at: 4), "World")
        let vtt = Data("WEBVTT\n\n00:00:01.000 --> 00:00:03.000 align:start\n<b>Hello</b>\n".utf8)
        let second = try ModuleSubtitleLoader.parse(data: vtt, format: nil, contentType: "text/vtt")
        XCTAssertEqual(second.text(at: 2), "Hello")
    }

    func testOverlappingCuesAndBackwardSeeksRemainCorrect() {
        let timeline = ModuleSubtitleTimeline(cues: [
            ExternalSubtitleCue(id: 0, startTime: 0, endTime: 20, text: "Long"),
            ExternalSubtitleCue(id: 1, startTime: 2, endTime: 3, text: "Short"),
            ExternalSubtitleCue(id: 2, startTime: 5, endTime: 8, text: "Later")
        ])
        XCTAssertEqual(timeline.text(at: 10), "Long")
        XCTAssertEqual(timeline.text(at: 2.5), "Long\nShort")
        XCTAssertEqual(timeline.text(at: 6), "Long\nLater")
        XCTAssertNil(timeline.text(at: 20))
        XCTAssertNil(timeline.text(at: .nan))
    }

    func testHTMLAndOversizedBodiesAreRejected() {
        XCTAssertThrowsError(try ModuleSubtitleLoader.parse(data: Data("<html>Sign in</html>".utf8), format: .vtt, contentType: "text/html"))
        XCTAssertThrowsError(try ModuleSubtitleLoader.parse(data: Data(repeating: 65, count: ModuleSubtitleLoader.maximumBytes + 1), format: .srt, contentType: "text/plain"))
        XCTAssertThrowsError(try ModuleSubtitleLoader.parse(data: Data(), format: .vtt, contentType: "text/vtt"))
    }

    @MainActor
    func testOffDiscardsLateSubtitleLoad() async {
        let gate = ModuleSubtitleLoadGate()
        let controller = ModuleExternalSubtitleController(loader: { try await gate.load($0) })
        let track = makeTrack("en")
        controller.configure(tracks: [track])
        controller.updatePlaybackTime(2)
        controller.select(track)
        let started = await waitUntil { await gate.count() == 1 }
        XCTAssertTrue(started)
        controller.turnOff()
        await gate.finish(track.id, text: "Old")
        await Task.yield()
        XCTAssertFalse(controller.isRequested)
        XCTAssertNil(controller.selectedTrackID)
        XCTAssertNil(controller.currentText)
        XCTAssertFalse(controller.isLoading)
    }

    @MainActor
    func testNewTrackWinsWhenOlderRequestCompletesLast() async {
        let gate = ModuleSubtitleLoadGate()
        let controller = ModuleExternalSubtitleController(loader: { try await gate.load($0) })
        let first = makeTrack("en")
        let second = makeTrack("de")
        controller.configure(tracks: [first, second])
        controller.updatePlaybackTime(2)
        controller.select(first)
        let firstStarted = await waitUntil { await gate.count() == 1 }
        XCTAssertTrue(firstStarted)
        controller.select(second)
        let secondStarted = await waitUntil { await gate.count() == 2 }
        XCTAssertTrue(secondStarted)
        await gate.finish(second.id, text: "New")
        let ready = await waitUntil { controller.currentText == "New" }
        XCTAssertTrue(ready)
        await gate.finish(first.id, text: "Old")
        await Task.yield()
        XCTAssertEqual(controller.currentText, "New")
        XCTAssertEqual(controller.selectedTrackID, second.id)
        controller.stop()
    }

    @MainActor
    func testStreamChangeClearsOldCuesAndMatchesLanguageOnNewURL() async {
        let controller = ModuleExternalSubtitleController(loader: { track in
            ModuleSubtitleTimeline(cues: [ExternalSubtitleCue(id: 0, startTime: 0, endTime: 10, text: track.label)])
        })
        let first = makeTrack("en", label: "First")
        let second = makeTrack("en", label: "Second", suffix: "-new")
        controller.configure(tracks: [first])
        controller.updatePlaybackTime(2)
        controller.select(first)
        let firstReady = await waitUntil { controller.currentText == "First" }
        XCTAssertTrue(firstReady)
        controller.configure(tracks: [second])
        XCTAssertNil(controller.currentText)
        XCTAssertEqual(controller.selectedTrackID, second.id)
        controller.updatePlaybackTime(2)
        let secondReady = await waitUntil { controller.currentText == "Second" }
        XCTAssertTrue(secondReady)
        controller.stop()
    }

    @MainActor
    func testMissingLanguageDoesNotSelectUnrelatedTrackAndOffSurvivesConfigure() async {
        let controller = ModuleExternalSubtitleController(loader: { _ in ModuleSubtitleTimeline(cues: []) })
        let english = makeTrack("en")
        let german = makeTrack("de")
        controller.configure(tracks: [english])
        controller.select(english)
        controller.configure(tracks: [german])
        XCTAssertNil(controller.selectedTrackID)
        XCTAssertNotNil(controller.errorMessage)
        controller.turnOff()
        controller.configure(tracks: [english])
        XCTAssertNil(controller.selectedTrackID)
        XCTAssertFalse(controller.isRequested)
        XCTAssertNil(controller.errorMessage)
        controller.stop()
    }

    @MainActor
    func testNetworkErrorsDoNotExposeSignedURLs() async {
        let controller = ModuleExternalSubtitleController(loader: { _ in
            throw NSError(domain: "https://captions.example.invalid/?token=private", code: 1)
        })
        let track = makeTrack("en")
        controller.configure(tracks: [track])
        controller.select(track)
        let failed = await waitUntil { controller.errorMessage != nil }
        XCTAssertTrue(failed)
        XCTAssertEqual(controller.errorMessage, ModuleSubtitleError.unavailable.errorDescription)
        XCTAssertFalse(controller.errorMessage?.contains("private") ?? true)
        controller.stop()
    }

    private func makeTrack(_ language: String, label: String? = nil, suffix: String = "", headers: [String: String] = [:]) -> ModuleRemoteSubtitleTrack {
        ModuleRemoteSubtitleTrack(url: URL(string: "https://captions.example.invalid/\(language)\(suffix).vtt")!,
                                  label: label ?? language.uppercased(), language: language, format: .vtt, headers: headers)
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private actor ModuleSubtitleLoadGate {
    private var pending: [String: CheckedContinuation<ModuleSubtitleTimeline, Error>] = [:]

    func load(_ track: ModuleRemoteSubtitleTrack) async throws -> ModuleSubtitleTimeline {
        try await withCheckedThrowingContinuation { continuation in
            pending[track.id] = continuation
        }
    }

    func count() -> Int { pending.count }

    func finish(_ id: String, text: String) {
        pending.removeValue(forKey: id)?.resume(returning: ModuleSubtitleTimeline(cues: [
            ExternalSubtitleCue(id: 0, startTime: 0, endTime: 10, text: text)
        ]))
    }
}

// MARK: - Module Video Quality (Batch 03F)

final class ModuleVideoQualityTests: XCTestCase {
    private var ladder: [ModuleVideoQualityVariant] {
        [variant(1920, 1080, 6_000_000), variant(640, 360, 800_000), variant(1280, 720, 3_000_000)]
    }

    func testResolutionLadderIsSortedAndDuplicateCodecsAreMerged() {
        let options = ModuleVideoQualityCatalog.options(from: ladder + [variant(1280, 720, 5_000_000)])
        XCTAssertEqual(options.map(\.id), ["640x360", "1280x720", "1920x1080"])
        XCTAssertEqual(options[1].peakBitRate, 5_000_000)
    }

    func testEmptyAndSingleResolutionAssetsHaveNoManualChoices() {
        XCTAssertTrue(ModuleVideoQualityCatalog.options(from: []).isEmpty)
        XCTAssertTrue(ModuleVideoQualityCatalog.options(from: [variant(1280, 720, 3_000_000)]).isEmpty)
        XCTAssertTrue(ModuleVideoQualityCatalog.options(from: [variant(1280, 720, 3_000_000), variant(1280, 720, 6_000_000)]).isEmpty)
    }

    func testInvalidDimensionsCannotCreateOptionsOrTrapIntegerConversion() {
        let invalid = [variant(0, 720, 1), variant(-1, 720, 1), variant(.nan, 720, 1),
                       variant(.infinity, 720, 1), variant(1280, .nan, 1), variant(1280, 40_000, 1)]
        XCTAssertEqual(ModuleVideoQualityCatalog.options(from: ladder + invalid).count, 3)
    }

    func testMissingPeakInDuplicateResolutionDoesNotInventBandwidthLimit() {
        let options = ModuleVideoQualityCatalog.options(from: ladder + [variant(1280, 720, nil)])
        XCTAssertNil(options[1].peakBitRate)
        XCTAssertEqual(ModuleVideoQualityCatalog.preferredPeakBitRate(for: options[2], in: options), 0)
    }

    func testInvalidPeakBitratesAreTreatedAsUnknown() {
        for value in [Double.nan, Double.infinity, -1, 0, 2_000_000_000_000] {
            let options = ModuleVideoQualityCatalog.options(from: [variant(640, 360, value), variant(1280, 720, 3_000_000)])
            XCTAssertNil(options[0].peakBitRate)
            XCTAssertEqual(ModuleVideoQualityCatalog.preferredPeakBitRate(for: options[1], in: options), 0)
        }
    }

    func testLowerResolutionHigherBitrateIsIncludedInPreference() {
        let options = ModuleVideoQualityCatalog.options(from: [variant(640, 360, 5_000_000), variant(1280, 720, 3_000_000)])
        XCTAssertEqual(ModuleVideoQualityCatalog.preferredPeakBitRate(for: options[1], in: options), 5_000_000)
    }

    func testHigherResolutionDoesNotRaiseLowerResolutionBitratePreference() {
        let options = ModuleVideoQualityCatalog.options(from: ladder)
        XCTAssertEqual(ModuleVideoQualityCatalog.preferredPeakBitRate(for: options[0], in: options), 800_000)
        XCTAssertEqual(ModuleVideoQualityCatalog.preferredPeakBitRate(for: options[1], in: options), 3_000_000)
    }

    func testVariantInspectionAndOptionCountAreBounded() {
        let repeated = Array(repeating: variant(640, 360, 800_000), count: 256)
        XCTAssertTrue(ModuleVideoQualityCatalog.options(from: repeated + [variant(1280, 720, 3_000_000)]).isEmpty)
        let many = (1...60).map { variant(Double($0 * 32), Double($0 * 18), Double($0 * 100_000)) }
        XCTAssertEqual(ModuleVideoQualityCatalog.options(from: many).count, 32)
    }

    func testPortraitDimensionsAreNotSwapped() {
        let options = ModuleVideoQualityCatalog.options(from: [variant(360, 640, 800_000), variant(720, 1280, 3_000_000)])
        XCTAssertEqual(options[1].resolution, CGSize(width: 720, height: 1280))
        XCTAssertEqual(options[1].title, "Up to 720p")
    }

    func testFractionalPresentationDimensionsRoundUpWithinBounds() {
        let size = ModuleVideoQualityCatalog.dimensions(width: 853.333, height: 480)
        XCTAssertEqual(size?.width, 854)
        XCTAssertEqual(size?.height, 480)
    }

    @MainActor
    func testSelectionAppliesPreferencesToExistingItemAndAutoClearsBoth() async {
        let samples = ladder
        let controller = ModuleVideoQualityController(loader: { _ in samples })
        let item = makeItem("first")
        controller.configure(for: item)
        let ready = await waitUntil { controller.state == .available }
        XCTAssertTrue(ready)
        controller.select("1280x720")
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 1280, height: 720))
        XCTAssertEqual(item.preferredPeakBitRate, 3_000_000)
        XCTAssertEqual(controller.selectedID, "1280x720")
        controller.select(nil)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertNil(controller.selectedID)
        controller.stop()
    }

    @MainActor
    func testUnknownOptionCannotOverrideCurrentSelection() async {
        let samples = ladder
        let controller = ModuleVideoQualityController(loader: { _ in samples })
        let item = makeItem("unknown-option")
        controller.configure(for: item)
        let ready = await waitUntil { controller.state == .available }
        XCTAssertTrue(ready)
        controller.select("1280x720")
        controller.select("3840x2160")
        XCTAssertEqual(controller.selectedID, "1280x720")
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 1280, height: 720))
        controller.stop()
    }

    @MainActor
    func testNewItemStartsInAutoAndClearsPreviousPreferences() async {
        let samples = ladder
        let controller = ModuleVideoQualityController(loader: { _ in samples })
        let first = makeItem("first")
        let second = makeItem("second")
        controller.configure(for: first)
        let firstReady = await waitUntil { controller.state == .available }
        XCTAssertTrue(firstReady)
        controller.select("1280x720")
        controller.configure(for: second)
        XCTAssertNil(controller.selectedID)
        XCTAssertTrue(controller.options.isEmpty)
        XCTAssertEqual(first.preferredMaximumResolution, .zero)
        XCTAssertEqual(second.preferredMaximumResolution, .zero)
        let secondReady = await waitUntil { controller.state == .available }
        XCTAssertTrue(secondReady)
        XCTAssertNil(controller.selectedID)
        controller.stop()
    }

    @MainActor
    func testEmptyMetadataLeavesItemInAutoWithoutManualChoices() async {
        let controller = ModuleVideoQualityController(loader: { _ in [] })
        let item = makeItem("fixed")
        controller.configure(for: item)
        let finished = await waitUntil { controller.state == .unavailable }
        XCTAssertTrue(finished)
        controller.select("1280x720")
        XCTAssertTrue(controller.options.isEmpty)
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        controller.stop()
    }

    @MainActor
    func testLocalItemDoesNotInvokeRemoteDiscovery() {
        var called = false
        let controller = ModuleVideoQualityController(loader: { _ in called = true; return [] })
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent-quality-fixture.mp4"))
        controller.configure(for: item)
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertFalse(called)
        controller.stop()
    }

    @MainActor
    func testNonURLAssetDoesNotInvokeRemoteDiscovery() {
        var called = false
        let controller = ModuleVideoQualityController(loader: { _ in called = true; return [] })
        let item = AVPlayerItem(asset: AVMutableComposition())
        controller.configure(for: item)
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertFalse(called)
        controller.stop()
    }

    @MainActor
    func testFailedDiscoveryCanRetryWithoutReplacingItem() async {
        let samples = ladder
        var attempts = 0
        let controller = ModuleVideoQualityController(loader: { _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "https://private.invalid/?token=opaque", code: 1) }
            return samples
        })
        let item = makeItem("retry")
        controller.configure(for: item)
        let failed = await waitUntil { controller.state == .failed }
        XCTAssertTrue(failed)
        XCTAssertEqual(controller.selectionDescription, "Auto")
        controller.retry()
        let ready = await waitUntil { controller.state == .available }
        XCTAssertTrue(ready)
        XCTAssertEqual(attempts, 2)
        controller.select("1280x720")
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 1280, height: 720))
        controller.stop()
    }

    @MainActor
    func testLateOldItemResultCannotReplaceNewLadder() async {
        let gate = ModuleQualityLoadGate()
        let controller = ModuleVideoQualityController(loader: { try await gate.load($0.url.lastPathComponent) })
        let first = makeItem("first")
        let second = makeItem("second")
        controller.configure(for: first)
        let firstStarted = await waitUntil { await gate.count() == 1 }
        XCTAssertTrue(firstStarted)
        controller.configure(for: second)
        let bothStarted = await waitUntil { await gate.count() == 2 }
        XCTAssertTrue(bothStarted)
        await gate.finish("second", variants: ladder)
        let ready = await waitUntil { controller.state == .available }
        XCTAssertTrue(ready)
        controller.select("1280x720")
        await gate.finish("first", variants: [])
        let delivered = await waitUntil { await gate.deliveredCount() == 2 }
        XCTAssertTrue(delivered)
        await Task.yield()
        XCTAssertEqual(controller.state, .available)
        XCTAssertEqual(controller.selectedID, "1280x720")
        XCTAssertEqual(second.preferredMaximumResolution, CGSize(width: 1280, height: 720))
        controller.stop()
    }

    @MainActor
    func testStopInvalidatesPendingDiscovery() async {
        let gate = ModuleQualityLoadGate()
        let controller = ModuleVideoQualityController(loader: { try await gate.load($0.url.lastPathComponent) })
        let item = makeItem("stop")
        controller.configure(for: item)
        let started = await waitUntil { await gate.count() == 1 }
        XCTAssertTrue(started)
        controller.stop()
        await gate.finish("stop", variants: ladder)
        let delivered = await waitUntil { await gate.deliveredCount() == 1 }
        XCTAssertTrue(delivered)
        await Task.yield()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.options.isEmpty)
        XCTAssertNil(controller.presentedResolution)
    }

    @MainActor
    func testTimeoutIgnoresLateMetadataAndLeavesPlaybackPreferencesAlone() async {
        let gate = ModuleQualityLoadGate()
        let controller = ModuleVideoQualityController(loader: { try await gate.load($0.url.lastPathComponent) }, timeout: .milliseconds(30))
        let item = makeItem("timeout")
        controller.configure(for: item)
        let started = await waitUntil { await gate.count() == 1 }
        XCTAssertTrue(started)
        let failed = await waitUntil { controller.state == .failed }
        XCTAssertTrue(failed)
        await gate.finish("timeout", variants: ladder)
        let delivered = await waitUntil { await gate.deliveredCount() == 1 }
        XCTAssertTrue(delivered)
        await Task.yield()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertTrue(controller.options.isEmpty)
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        controller.stop()
    }

    private func variant(_ width: Double, _ height: Double, _ peak: Double?) -> ModuleVideoQualityVariant {
        ModuleVideoQualityVariant(width: width, height: height, peakBitRate: peak)
    }

    private func makeItem(_ name: String) -> AVPlayerItem {
        AVPlayerItem(asset: AVURLAsset(url: URL(string: "https://quality.example.invalid/\(name)")!))
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor ModuleQualityLoadGate {
    private var pending: [String: CheckedContinuation<[ModuleVideoQualityVariant], Error>] = [:]
    private var delivered = 0

    func load(_ id: String) async throws -> [ModuleVideoQualityVariant] {
        let result: [ModuleVideoQualityVariant] = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
        }
        delivered += 1
        return result
    }

    func count() -> Int { pending.count }
    func deliveredCount() -> Int { delivered }

    func finish(_ id: String, variants: [ModuleVideoQualityVariant]) {
        pending.removeValue(forKey: id)?.resume(returning: variants)
    }
}

// MARK: - Subtitle Preferences (Batch 03G)

final class KinetiqSubtitlePreferenceTests: XCTestCase {
    func testExactSourceTagWinsBeforeRegionalFallbackAndNativeWinsTies() {
        let regional = KinetiqCaptionLanguage(tag: "en-GB", name: "English UK")
        let exact = KinetiqCaptionLanguage(tag: "en_US", name: "English US")
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "en-us", embedded: [regional], sources: [exact]), .source(0))
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "en-us", embedded: [regional, exact], sources: [exact]), .embedded(1))
    }

    func testLanguageAliasesAndMissingTrackTags() {
        let unknown = KinetiqCaptionLanguage(tag: "und", name: "Track 1")
        let german = KinetiqCaptionLanguage(tag: nil, name: "Deutsch")
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "de-at", embedded: [unknown], sources: [german]), .source(0))
        XCTAssertEqual(KinetiqCaptionLanguage.normalized("DEU_DE"), "de-de")
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "tr", embedded: [unknown], sources: [german]), .off)
    }

    func testExplicitlyDifferentScriptsDoNotMatch() {
        let simplified = KinetiqCaptionLanguage(tag: "zh-Hans-CN", name: "Chinese")
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "zh-Hant", embedded: [simplified]), .off)
    }

    func testManualOffOrTrackTakesPrecedenceAndCanReturnToAutomatic() {
        let track = KinetiqCaptionLanguage(tag: "en", name: "English CC")
        XCTAssertEqual(KinetiqCaptionChoice.off.target(preference: "en", embedded: [track]), .off)
        XCTAssertEqual(KinetiqCaptionChoice.embedded(track).target(preference: "off", embedded: [track]), .embedded(0))
        XCTAssertEqual(KinetiqCaptionChoice.source.target(preference: "off", embedded: [track]), .manualSource)
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "automatic", embedded: [], sources: [track]), .automatic)
        XCTAssertEqual(KinetiqCaptionChoice.settings.target(preference: "off", embedded: [track]), .off)
    }

    @MainActor
    func testPreferencesSurviveReopeningAndInvalidInputRetainsLastChoice() throws {
        let suite = "kinetiq.tests.subtitles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KinetiqSubtitleSettings(defaults: defaults)
        XCTAssertEqual(settings.language, "automatic")
        XCTAssertTrue(settings.setLanguage(" en_GB "))
        XCTAssertFalse(settings.setLanguage("https://invalid.example/caption.vtt"))
        settings.appearance = .init(size: .large, ink: .yellow, background: .solid)
        let reopened = KinetiqSubtitleSettings(defaults: defaults)
        XCTAssertEqual(reopened.language, "en-gb")
        XCTAssertEqual(reopened.appearance, settings.appearance)
        XCTAssertEqual(reopened.appearance.nativeRules?.count, 1)
        reopened.appearance = .init()
        XCTAssertNil(reopened.appearance.nativeRules)
        XCTAssertEqual(KinetiqSubtitleSettings(defaults: defaults).language, "en-gb")
    }

    @MainActor
    func testUnknownStoredValuesFallBackPerField() throws {
        let suite = "kinetiq.tests.subtitles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("bad value", forKey: "kinetiq.subtitles.v1.language")
        defaults.set("Unknown", forKey: "kinetiq.subtitles.v1.size")
        defaults.set("Cyan", forKey: "kinetiq.subtitles.v1.ink")
        let settings = KinetiqSubtitleSettings(defaults: defaults)
        XCTAssertEqual(settings.language, "automatic")
        XCTAssertEqual(settings.appearance.size, .standard)
        XCTAssertEqual(settings.appearance.ink, .cyan)
    }

    @MainActor
    func testOnlyManualSourceSelectionCarriesToTheNextItem() throws {
        let controller = ModuleExternalSubtitleController(loader: { _ in ModuleSubtitleTimeline(cues: []) })
        let one = ModuleRemoteSubtitleTrack(url: try XCTUnwrap(URL(string: "https://source.example.invalid/one.vtt")), label: "English", language: "en", format: .vtt, headers: [:])
        let two = ModuleRemoteSubtitleTrack(url: try XCTUnwrap(URL(string: "https://source.example.invalid/two.vtt")), label: "English", language: "en", format: .vtt, headers: [:])
        controller.configure(tracks: [one])
        controller.select(one, rememberForSession: false)
        XCTAssertTrue(controller.isRequested)
        controller.configure(tracks: [two])
        XCTAssertNil(controller.selectedTrackID)
        XCTAssertFalse(controller.isRequested)
        controller.select(two)
        controller.configure(tracks: [one])
        XCTAssertEqual(controller.selectedTrackID, one.id)
        controller.stop()
    }
}


// Batch 06I: Theme IDs are persisted preferences and must be stable.
final class KinetiqThemeExperienceTests: XCTestCase {
    func testThirteenOriginalThemesHaveDistinctIdentities() {
        let all = KinetiqVisualTheme.allCases
        XCTAssertEqual(all.count, 13)
        XCTAssertEqual(Set(all.map(\.rawValue)).count, all.count)
        for theme in all {
            XCTAssertFalse(theme.name.isEmpty)
            XCTAssertEqual(theme.stageColors.count, 3)
            XCTAssertGreaterThan(theme.heroHeight, 200)
        }
    }

    func testLegacyThemeValuesNeverChange() {
        XCTAssertEqual(KinetiqVisualTheme.storageKey, "kinetiq.visualTheme.v1")
        XCTAssertEqual(KinetiqVisualTheme.signature.rawValue, "signature")
        XCTAssertEqual(KinetiqVisualTheme.cinema.rawValue, "cinema")
        XCTAssertEqual(KinetiqVisualTheme.anime.rawValue, "anime")
        XCTAssertEqual(KinetiqVisualTheme.aurora.rawValue, "aurora")
        XCTAssertEqual(KinetiqVisualTheme.nocturne.rawValue, "nocturne")
    }

    func testMediaModesRouteToCorrectDestination() {
        XCTAssertEqual(HomeContentRoute.resolve(mode: .manga, isLocalLibrarySelected: true, sourceAvailable: true), .manga)
        XCTAssertEqual(HomeContentRoute.resolve(mode: .video, isLocalLibrarySelected: true, sourceAvailable: false), .localVideo)
        XCTAssertEqual(HomeContentRoute.resolve(mode: .video, isLocalLibrarySelected: false, sourceAvailable: true), .remoteVideo)
    }
}