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
