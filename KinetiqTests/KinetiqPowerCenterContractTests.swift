import XCTest
@testable import Kinetiq

@MainActor
final class KinetiqPowerCenterContractTests: XCTestCase {
    func testLibraryDoctorHashesFileContentsNotNames() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinetiqDoctorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = temporary.appendingPathComponent("episode-one.mp4")
        let same = temporary.appendingPathComponent("renamed-episode.mp4")
        let different = temporary.appendingPathComponent("different.mp4")
        try Data("one clip".utf8).write(to: first)
        try Data("one clip".utf8).write(to: same)
        try Data("two clip".utf8).write(to: different)

        XCTAssertEqual(try KinetiqLibraryAuditor.fingerprint(url: first),
                       try KinetiqLibraryAuditor.fingerprint(url: same))
        XCTAssertNotEqual(try KinetiqLibraryAuditor.fingerprint(url: first),
                          try KinetiqLibraryAuditor.fingerprint(url: different))
    }

    func testM03PlayerGestureIntervalsAndFallback() {
        for interval in [5, 10, 15, 30, 60] {
            XCTAssertEqual(KinetiqPlayerSeekPolicy.safeInterval(interval), interval)
        }
        XCTAssertEqual(KinetiqPlayerSeekPolicy.safeInterval(-4), 10)
        XCTAssertEqual(KinetiqPlayerSeekPolicy.safeInterval(999), 10)
    }

    func testPrivateManualChapterMarkersDoNotMixEpisodesOrSources() {
        let domain = "KinetiqM03ChapterTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: domain)!
        defer { suite.removePersistentDomain(forName: domain) }
        let store = KinetiqManualChapterStore(defaults: suite)
        store.markStart(mediaKey: "sourceA:roshidere", episodeKey: "ep1",
                        kind: .opening, seconds: 32)
        XCTAssertFalse(store.markEnd(mediaKey: "sourceA:roshidere", episodeKey: "ep1",
                                     kind: .opening, seconds: 31))
        XCTAssertTrue(store.markEnd(mediaKey: "sourceA:roshidere", episodeKey: "ep1",
                                    kind: .opening, seconds: 120))
        XCTAssertTrue(store.chapter(mediaKey: "sourceA:roshidere", episodeKey: "ep1",
                                     kind: .opening)?.isSkippable == true)
        XCTAssertNil(store.chapter(mediaKey: "sourceA:roshidere", episodeKey: "ep2", kind: .opening))
        XCTAssertNil(store.chapter(mediaKey: "sourceB:roshidere", episodeKey: "ep1", kind: .opening))
        XCTAssertEqual(KinetiqManualChapterStore(defaults: suite).chapter(
            mediaKey: "sourceA:roshidere", episodeKey: "ep1", kind: .opening)?.end, 120)
    }

    func testRepositoryNoticesCoalesceAcrossRepeatedInstallResults() {
        let domain = "KinetiqM03Notices.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let center = KinetiqNoticeCenter(defaults: defaults, schedulesAutoDismiss: false)
        center.post(.warning, title: "Repository Installation Finished",
                    message: "32 installed, 1 failed", groupKey: "batch.install.repo-a")
        center.post(.warning, title: "Repository Installation Finished",
                    message: "32 installed, 1 failed", groupKey: "batch.install.repo-a")
        XCTAssertEqual(center.history.count, 1)
        XCTAssertEqual(center.history.first?.occurrences, 2)
        XCTAssertEqual(center.current?.occurrences, 2)
        XCTAssertEqual(center.pendingCount, 0)
    }

    func testExactTimecodeParserRejectsInvalidInput() {
        XCTAssertEqual(KinetiqTimecodeParser.seconds(from: "42"), 42)
        XCTAssertEqual(KinetiqTimecodeParser.seconds(from: "12:34"), 754)
        XCTAssertEqual(KinetiqTimecodeParser.seconds(from: "01:02:03"), 3_723)
        XCTAssertNil(KinetiqTimecodeParser.seconds(from: "-01:30"))
        XCTAssertNil(KinetiqTimecodeParser.seconds(from: "1:60"))
        XCTAssertNil(KinetiqTimecodeParser.seconds(from: "1:2:60"))
        XCTAssertNil(KinetiqTimecodeParser.seconds(from: "one minute"))
    }

    private func sampleAnchor(
        episode: String = "1", language: String = "sub", duration: Double = 1_400
    ) -> KinetiqSceneAnchor {
        KinetiqSceneAnchor(mediaID: "7:sourceAanime1", sourceName: "Source A",
            episodeID: "episode-1", episodeNumber: episode, language: language,
            seconds: 700, duration: duration)
    }

    func testCrossSourceResumeRequiresConfirmedLinkAndMatchingCut() {
        let anchor = sampleAnchor()
        XCTAssertNil(KinetiqContinuityMatcher.candidate(anchor,
            targetMediaID: "7:sourceBanime1", connectedIDs: [],
            episodeNumber: "1", language: "sub", duration: 1_400))

        let allowed = KinetiqContinuityMatcher.candidate(anchor,
            targetMediaID: "7:sourceBanime1", connectedIDs: [anchor.mediaID],
            episodeNumber: "1", language: "sub", duration: 1_402)
        XCTAssertNotNil(allowed)
        XCTAssertEqual(allowed?.mappedSeconds ?? 0, 701, accuracy: 0.1)

        XCTAssertNil(KinetiqContinuityMatcher.candidate(anchor,
            targetMediaID: "7:sourceBanime1", connectedIDs: [anchor.mediaID],
            episodeNumber: "2", language: "sub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(anchor,
            targetMediaID: "7:sourceBanime1", connectedIDs: [anchor.mediaID],
            episodeNumber: "1", language: "dub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(anchor,
            targetMediaID: "7:sourceBanime1", connectedIDs: [anchor.mediaID],
            episodeNumber: "1", language: "sub", duration: 1_520))
    }

    func testEpisodeIdentityGuardRejectsSeasonAndEditionMixups() {
        XCTAssertEqual(KinetiqEpisodeIdentity.parse("S01E04"),
                       .regular(season: 1, episode: 4))
        XCTAssertEqual(KinetiqEpisodeIdentity.parse("Season 1 Episode 4"),
                       .regular(season: 1, episode: 4))
        XCTAssertEqual(KinetiqEpisodeIdentity.parse("OVA 4"),
                       .alternate(kind: "ova", number: 4))
        XCTAssertNil(KinetiqEpisodeIdentity.parse("4.5"))

        let confirmedSource = sampleAnchor(episode: "S1E4")
        let otherID = "7:sourceBanime1"
        let confirmedLinks: Set<String> = [confirmedSource.mediaID]
        XCTAssertNotNil(KinetiqContinuityMatcher.candidate(confirmedSource,
            targetMediaID: otherID, connectedIDs: confirmedLinks,
            episodeNumber: "Season 1 Episode 4", language: "sub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(confirmedSource,
            targetMediaID: otherID, connectedIDs: confirmedLinks,
            episodeNumber: "S2E4", language: "sub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(confirmedSource,
            targetMediaID: otherID, connectedIDs: confirmedLinks,
            episodeNumber: "4", language: "sub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(confirmedSource,
            targetMediaID: otherID, connectedIDs: confirmedLinks,
            episodeNumber: "OVA 4", language: "sub", duration: 1_400))
        XCTAssertNil(KinetiqContinuityMatcher.candidate(sampleAnchor(episode: "OVA 4"),
            targetMediaID: otherID, connectedIDs: confirmedLinks,
            episodeNumber: "4", language: "sub", duration: 1_400))
    }

    func testSourceFlightEvidenceRanksWithoutSuppressingAlternatives() {
        let suite = "KinetiqServerFlightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let health = ModuleServerHealthStore(defaults: defaults)
        let first = ModuleResolvedStream(title: "Episode 4", label: "Server A",
            url: URL(string: "https://cdn-a.example.org/episode4.m3u8")!,
            headers: [:], streamType: "hls")
        let second = ModuleResolvedStream(title: "Episode 4", label: "Server B",
            url: URL(string: "https://cdn-b.example.org/episode4.m3u8")!,
            headers: [:], streamType: "hls")

        XCTAssertTrue(health.status(for: first, sourceID: "module-a", sourceName: "Module A")
            .contains("No verified playback"))
        health.recordSuccess(second, sourceID: "module-a", sourceName: "Module A",
            startupSeconds: 1.5)
        let ranked = health.ordered([first, second], sourceID: "module-a",
            sourceName: "Module A")
        XCTAssertEqual(ranked.map(\.label), ["Server B", "Server A"])
        XCTAssertTrue(health.status(for: second, sourceID: "module-a", sourceName: "Module A")
            .contains("Host played"))
        health.recordFailure(second, sourceID: "module-a", sourceName: "Module A")
        XCTAssertTrue(health.status(for: second, sourceID: "module-a", sourceName: "Module A")
            .contains("Host failed"))
        XCTAssertEqual(health.ordered([first, second], sourceID: "module-a",
            sourceName: "Module A").count, 2)
    }

    func testServerPinIsPrivatePersistentAndScopedToTitleAndLanguage() {
        let suite = "KinetiqServerPinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ModuleServerPreferenceStore(defaults: defaults)
        let first = ModuleResolvedStream(title: "Episode 4", label: "Server A",
            url: URL(string: "https://cdn-a.example.org/episode4.m3u8")!,
            headers: [:], streamType: "hls")
        let second = ModuleResolvedStream(title: "Episode 4", label: "Server B",
            url: URL(string: "https://cdn-b.example.org/episode4.m3u8")!,
            headers: [:], streamType: "hls")

        preferences.setPinned(second, sourceID: "module-a", sourceName: "Module A",
            mediaID: "anime-4", language: "sub")
        XCTAssertEqual(preferences.ordered([first, second], sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub")
            .map(\.label), ["Server B", "Server A"])
        XCTAssertEqual(preferences.ordered([first, second], sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-5", language: "sub")
            .map(\.label), ["Server A", "Server B"])
        XCTAssertEqual(preferences.ordered([first, second], sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "dub")
            .map(\.label), ["Server A", "Server B"])

        let restored = ModuleServerPreferenceStore(defaults: defaults)
        XCTAssertTrue(restored.isPinned(second, sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub"))
        XCTAssertTrue(preferences.isAutomaticFallbackEnabled(sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub"))
        preferences.setAutomaticFallbackEnabled(false, sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub")
        let restoredFallback = ModuleServerPreferenceStore(defaults: defaults)
        XCTAssertFalse(restoredFallback.isAutomaticFallbackEnabled(sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub"))
        XCTAssertTrue(restoredFallback.isAutomaticFallbackEnabled(sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "dub"))
        preferences.setAutomaticFallbackEnabled(true, sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub")
        XCTAssertTrue(preferences.isAutomaticFallbackEnabled(sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub"))
        let saved = String(decoding: defaults.data(
            forKey: "kinetiq.module.serverPreferences.v1") ?? Data(), as: UTF8.self)
        XCTAssertFalse(saved.contains("cdn-b.example.org"))
        XCTAssertFalse(saved.contains("Server B"))
        preferences.setPinned(nil, sourceID: "module-a", sourceName: "Module A",
            mediaID: "anime-4", language: "sub")
        XCTAssertFalse(preferences.isPinned(second, sourceID: "module-a",
            sourceName: "Module A", mediaID: "anime-4", language: "sub"))
    }

    func testPortableSyncSnapshotRoundTripHasNoStreamCredentials() throws {
        let archive = KinetiqSyncArchive(schema: 1, generatedAt: Date(), titles: [],
            anchors: [sampleAnchor()], bookmarks: [], connections: [], theme: nil)
        let bytes = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(KinetiqSyncArchive.self, from: bytes)
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.anchors.count, 1)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Authorization"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("http"))
    }

    func testSceneStoreRejectsInvalidAnchors() {
        let suiteName = "KinetiqPowerCenterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = KinetiqContinuityStore(defaults: defaults)
        store.record(sampleAnchor())
        store.record(sampleAnchor(duration: .nan))
        XCTAssertEqual(store.anchors.count, 1)
    }

    func testWatchPlansPersistAsPrivateInvitationsWithoutStreamLinks() {
        let suiteName = "KinetiqWatchPlansTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = KinetiqWatchPlanStore(defaults: defaults)
        store.add(series: "Blue Box", episode: "7", start: Date(), note: "No spoilers")
        XCTAssertEqual(store.plans.count, 1)
        let restored = KinetiqWatchPlanStore(defaults: defaults)
        XCTAssertEqual(restored.plans.first?.series, "Blue Box")
        XCTAssertTrue(restored.plans.first?.invitation.contains("No spoilers") == true)
        XCTAssertFalse(restored.plans.first?.invitation.contains("http") == true)
    }
}
