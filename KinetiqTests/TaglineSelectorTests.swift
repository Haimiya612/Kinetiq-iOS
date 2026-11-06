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
