import Foundation
import XCTest
@testable import Kinetiq

@MainActor
final class KinetiqPlayerPersonalizationTests: XCTestCase {
    private func defaults(_ prefix: String) -> UserDefaults {
        UserDefaults(suiteName: "KinetiqPersonalization.\(prefix).\(UUID().uuidString)")!
    }

    func testQuickDeckPinDeduplicationAndMaximum() {
        let raw = ["playPause", "playPause", "seekBack10", "unknown"] +
            Array(repeating: "nextEpisode", count: 12)
        let normalized = KinetiqQuickDeckPolicy.normalized(raw)
        XCTAssertEqual(normalized, [.playPause, .seekBack10, .nextEpisode])
        XCTAssertEqual(KinetiqPlayerAction.allCases.count, 48)
        XCTAssertEqual(Set(KinetiqPlayerAction.allCases.map(\.title)).count, 48)
        XCTAssertEqual(KinetiqQuickDeckPolicy.maximumPins, 8)
    }

    func testQuickDeckPersistsOrderingWithoutChangingSourceOrDiscord() {
        let suite = defaults("order")
        let first = KinetiqPlayerQuickDeckStore(defaults: suite)
        first.restoreDefaults()
        XCTAssertTrue(first.add(.aspectFit))
        XCTAssertFalse(first.add(.aspectFit))
        first.move(.aspectFit, direction: -1)
        let copied = KinetiqPlayerQuickDeckStore(defaults: suite)
        XCTAssertEqual(first.pinned, copied.pinned)
        XCTAssertEqual(copied.pinned.count, 7)
        copied.remove(.aspectFit)
        XCTAssertFalse(KinetiqPlayerQuickDeckStore(defaults: suite).pinned.contains(.aspectFit))
    }

    func testQuickDeckRejectsMoreThanEightActions() {
        let suite = defaults("limit")
        let deck = KinetiqPlayerQuickDeckStore(defaults: suite)
        deck.restoreDefaults()
        XCTAssertTrue(deck.add(.aspectFit))
        XCTAssertTrue(deck.add(.aspectFill))
        XCTAssertFalse(deck.add(.rateSlow))
        XCTAssertEqual(deck.pinned.count, 8)
        deck.move(.playPause, direction: -1)
        XCTAssertEqual(deck.pinned.first, .playPause)
    }

    func testContextualSkipNeverUsesAnotherSourceOrEpisode() {
        let intro = KinetiqManualChapter(
            mediaKey: "source-A|roshidere", episodeKey: "season1-episode1",
            kind: .opening, start: 65, end: 152,
            streamKey: "cdn-a|server 1|hls", expectedDuration: 1430)
        XCTAssertNotNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [intro], mediaKey: "source-A|roshidere", episodeKey: "season1-episode1",
            streamKey: "cdn-a|server 1|hls", position: 90, duration: 1430))
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [intro], mediaKey: "source-B|roshidere", episodeKey: "season1-episode1",
            streamKey: "cdn-a|server 1|hls", position: 90, duration: 1430))
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [intro], mediaKey: "source-A|roshidere", episodeKey: "season1-episode2",
            streamKey: "cdn-a|server 1|hls", position: 90, duration: 1430))
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [intro], mediaKey: "source-A|roshidere", episodeKey: "season1-episode1",
            streamKey: "cdn-b|server 2|hls", position: 90, duration: 1430))
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [intro], mediaKey: "source-A|roshidere", episodeKey: "season1-episode1",
            streamKey: "cdn-a|server 1|hls", position: 90, duration: 1410))
        XCTAssertEqual(KinetiqChapterStreamIdentity.key(
            host: "CDN-A", label: "Server 1", type: "HLS"),
            KinetiqChapterStreamIdentity.key(
                host: "cdn-a", label: "server 1", type: "hls"))
        XCTAssertNotEqual(KinetiqChapterStreamIdentity.key(
            host: "CDN-A", label: "Server 1", type: "HLS"),
            KinetiqChapterStreamIdentity.key(
                host: "cdn-b", label: "server 2", type: "hls"))
    }

    func testSkipButtonOnlyAppearsWithinCompleteVerifiedSegment() {
        let recap = KinetiqManualChapter(
            mediaKey: "source|anime", episodeKey: "ep-4",
            kind: .recap, start: 11, end: 55,
            streamKey: "cdn|default|mp4", expectedDuration: 1400)
        let incomplete = KinetiqManualChapter(
            mediaKey: "source|anime", episodeKey: "ep-4",
            kind: .opening, start: 75, end: nil,
            streamKey: "cdn|default|mp4", expectedDuration: 1400)
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [recap, incomplete], mediaKey: "source|anime", episodeKey: "ep-4",
            streamKey: "cdn|default|mp4", position: 60, duration: 1400))
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [recap, incomplete], mediaKey: "source|anime", episodeKey: "ep-4",
            streamKey: "cdn|default|mp4", position: 20, duration: 45))
        XCTAssertEqual(KinetiqContextualSkipPolicy.eligibleChapter(
            [recap, incomplete], mediaKey: "source|anime", episodeKey: "ep-4",
            streamKey: "cdn|default|mp4", position: 20, duration: 1400)?.kind, .recap)
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            [recap, incomplete], mediaKey: "source|anime", episodeKey: "ep-4",
            streamKey: "cdn|default|mp4", position: 55, duration: 1400))
    }

    func testLegacyMarkersArePreservedButDoNotTriggerUnverifiedOverlays() {
        let suite = defaults("legacy-markers")
        let store = KinetiqManualChapterStore(defaults: suite)
        store.markStart(mediaKey: "provider|title", episodeKey: "episode",
                        kind: .opening, seconds: 55)
        XCTAssertTrue(store.markEnd(mediaKey: "provider|title", episodeKey: "episode",
                                    kind: .opening, seconds: 145))
        let reloaded = KinetiqManualChapterStore(defaults: suite)
        let old = reloaded.chapter(mediaKey: "provider|title", episodeKey: "episode",
                                   kind: .opening)
        XCTAssertNotNil(old)
        XCTAssertNil(KinetiqContextualSkipPolicy.eligibleChapter(
            reloaded.chapters, mediaKey: "provider|title", episodeKey: "episode",
            streamKey: "cdn|server|hls", position: 90, duration: 1450))
    }

    func testMarkersStaySeparateForServersWithinOneModule() {
        let suite = defaults("server-markers")
        let store = KinetiqManualChapterStore(defaults: suite)
        store.markStart(mediaKey: "AniWorld|title", episodeKey: "s1e1", kind: .opening,
                        seconds: 62, streamKey: "cdn-a|one|hls", expectedDuration: 1430)
        XCTAssertTrue(store.markEnd(mediaKey: "AniWorld|title", episodeKey: "s1e1",
                                    kind: .opening, seconds: 140, streamKey: "cdn-a|one|hls"))
        store.markStart(mediaKey: "AniWorld|title", episodeKey: "s1e1", kind: .opening,
                        seconds: 70, streamKey: "cdn-b|two|hls", expectedDuration: 1460)
        XCTAssertTrue(store.markEnd(mediaKey: "AniWorld|title", episodeKey: "s1e1",
                                    kind: .opening, seconds: 150, streamKey: "cdn-b|two|hls"))
        let restored = KinetiqManualChapterStore(defaults: suite)
        XCTAssertEqual(restored.chapter(mediaKey: "AniWorld|title", episodeKey: "s1e1",
                                        kind: .opening, streamKey: "cdn-a|one|hls")?.end, 140)
        XCTAssertEqual(restored.chapter(mediaKey: "AniWorld|title", episodeKey: "s1e1",
                                        kind: .opening, streamKey: "cdn-b|two|hls")?.end, 150)
    }

    func testManualMarkersPersistAndNeverOverwriteAnotherProvider() {
        let suite = defaults("chapter-scope")
        let store = KinetiqManualChapterStore(defaults: suite)
        store.markStart(mediaKey: "AniWorld|roshidere", episodeKey: "s1e1",
                        kind: .opening, seconds: 74)
        XCTAssertFalse(store.markEnd(mediaKey: "AniWorld|roshidere", episodeKey: "s1e1",
                                     kind: .opening, seconds: 74.5))
        XCTAssertTrue(store.markEnd(mediaKey: "AniWorld|roshidere", episodeKey: "s1e1",
                                    kind: .opening, seconds: 159))
        store.markStart(mediaKey: "OtherSource|roshidere", episodeKey: "s1e1",
                        kind: .opening, seconds: 80)
        XCTAssertTrue(store.markEnd(mediaKey: "OtherSource|roshidere", episodeKey: "s1e1",
                                    kind: .opening, seconds: 170))
        let restored = KinetiqManualChapterStore(defaults: suite)
        XCTAssertEqual(restored.chapter(mediaKey: "AniWorld|roshidere",
                                        episodeKey: "s1e1", kind: .opening)?.end, 159)
        XCTAssertEqual(restored.chapter(mediaKey: "OtherSource|roshidere",
                                        episodeKey: "s1e1", kind: .opening)?.end, 170)
        XCTAssertNil(restored.chapter(mediaKey: "AniWorld|roshidere",
                                      episodeKey: "s1e2", kind: .opening))
    }

    func testNextEpisodeOfferRequiresActualNextEpisodeAndCreditsEvidence() {
        XCTAssertFalse(KinetiqContextualSkipPolicy.nextEpisodeAvailable(
            position: 900, duration: 1400, hasNextEpisode: true, verifiedCredits: false))
        XCTAssertTrue(KinetiqContextualSkipPolicy.nextEpisodeAvailable(
            position: 900, duration: 1400, hasNextEpisode: true, verifiedCredits: true))
        XCTAssertFalse(KinetiqContextualSkipPolicy.nextEpisodeAvailable(
            position: 900, duration: 1400, hasNextEpisode: false, verifiedCredits: true))
        XCTAssertTrue(KinetiqContextualSkipPolicy.nextEpisodeAvailable(
            position: 1390, duration: 1400, hasNextEpisode: true, verifiedCredits: false))
        XCTAssertEqual(KinetiqContextualSkipPolicy.label(for: .opening), "Skip Intro")
        XCTAssertEqual(KinetiqContextualSkipPolicy.label(for: .recap), "Skip Recap")
        XCTAssertEqual(KinetiqContextualSkipPolicy.label(for: .ending), "Skip Credits")
    }

    func testSpoilerShieldProtectsUnwatchedAndStrictEpisodes() {
        XCTAssertFalse(KinetiqSpoilerShieldPolicy.shouldHideEpisode(
            watched: false, depth: .off, revealed: false))
        XCTAssertTrue(KinetiqSpoilerShieldPolicy.shouldHideEpisode(
            watched: false, depth: .unwatched, revealed: false))
        XCTAssertFalse(KinetiqSpoilerShieldPolicy.shouldHideEpisode(
            watched: true, depth: .unwatched, revealed: false))
        XCTAssertTrue(KinetiqSpoilerShieldPolicy.shouldHideEpisode(
            watched: true, depth: .strict, revealed: false))
        XCTAssertFalse(KinetiqSpoilerShieldPolicy.shouldHideEpisode(
            watched: false, depth: .strict, revealed: true))
        XCTAssertTrue(KinetiqSpoilerShieldPolicy.shouldProtectExtraSection(
            depth: .strict, explicitlyRevealed: false))
        XCTAssertFalse(KinetiqSpoilerShieldPolicy.shouldProtectExtraSection(
            depth: .strict, explicitlyRevealed: true))
    }
}
