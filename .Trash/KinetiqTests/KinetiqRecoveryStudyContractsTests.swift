import Foundation
import XCTest
@testable import Kinetiq

@MainActor
final class KinetiqRecoveryStudyContractsTests: XCTestCase {
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "KinetiqNewContracts.\(name).\(UUID().uuidString)")!
    }

    func testRecoveryHistoryKeepsCodesButNeverTokenBearingSourceStrings() throws {
        let defaults = isolatedDefaults("recovery")
        let store = KinetiqRecoveryStore(defaults: defaults)
        let now = Date()
        store.record(phase: .playback, outcome: .failed,
            code: "HTTP_PROVIDER_FAILURE", source: "https://cdn.example/stream?token=SECRET",
            episode: "7", httpStatus: 503, now: now)
        store.record(phase: .playback, outcome: .failed,
            code: "HTTP_PROVIDER_FAILURE", source: "https://cdn.example/stream?token=SECRET",
            episode: "7", httpStatus: 503, now: now.addingTimeInterval(15))
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.occurrences, 2)
        XCTAssertEqual(store.events.first?.httpStatus, 503)
        XCTAssertFalse(store.redactedReport.contains("SECRET"))
        XCTAssertFalse(store.redactedReport.contains("https://"))

        let restored = KinetiqRecoveryStore(defaults: defaults)
        XCTAssertEqual(restored.events.count, 1)
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
    }

    func testRecoveryCodesAreAllowlistedAndHTTPStatusBounded() {
        XCTAssertEqual(KinetiqRecoverySanitizer.code("failed?key=abc"), "FAILEDKEYABC")
        let store = KinetiqRecoveryStore(defaults: isolatedDefaults("status"))
        store.record(phase: .playback, outcome: .failed, code: "decode failure",
            source: "Source One", episode: "1", httpStatus: 900)
        XCTAssertNil(store.events.first?.httpStatus)
    }

    func testStudyDeckPersistsAndSchedulesDeterministically() {
        let defaults = isolatedDefaults("study")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let anchor = KinetiqSceneAnchor(mediaID: "7:example7", sourceName: "Source",
            episodeID: "episode-4", episodeNumber: "4", language: "sub",
            seconds: 370, duration: 1_400)
        let card = KinetiqStudyCard(series: "Blue Box", phrase: "ありがとう",
            meaning: "Thank you", context: "Short phrase", anchor: anchor, now: now)
        XCTAssertTrue(card.isValid)
        let again = KinetiqStudyScheduler.reviewed(card, grade: .again, at: now)
        XCTAssertEqual(again.dueAt.timeIntervalSince(now), 600, accuracy: 0.1)
        let easy = KinetiqStudyScheduler.reviewed(card, grade: .easy, at: now)
        XCTAssertEqual(easy.dueAt.timeIntervalSince(now), 3 * 86_400, accuracy: 0.1)

        let store = KinetiqStudyStore(defaults: defaults)
        store.add(series: "Blue Box", phrase: "ありがとう", meaning: "Thank you",
            context: "Short phrase", anchor: anchor)
        store.add(series: "Blue Box", phrase: "ありがとう", meaning: "Thank you",
            context: "Short phrase", anchor: anchor)
        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(KinetiqStudyStore(defaults: defaults).cards.count, 1)
        XCTAssertTrue(store.cards[0].anchor?.episodeNumber == "4")
    }

    func testStudyCSVProtectsSpreadsheetAndNeverExportsStreamAddresses() {
        let card = KinetiqStudyCard(series: "Series", phrase: "=SUM(1,2)",
            meaning: "Formula-like text", context: "Manual note", anchor: nil)
        let csv = KinetiqStudyCSV.export([card])
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\""))
        XCTAssertTrue(csv.contains("Formula-like text"))
        XCTAssertFalse(csv.contains("https://"))
        XCTAssertFalse(csv.contains("Authorization"))
    }

    func testBingeGuardCountsOnlyCompletedEpisodesAndHonorsAutoplayOff() {
        let normal = KinetiqBingeGuardPolicy.completedEpisode(remaining: nil, autoplay: true)
        XCTAssertTrue(normal.advance)
        XCTAssertNil(normal.remaining)

        let first = KinetiqBingeGuardPolicy.completedEpisode(remaining: 3, autoplay: true)
        XCTAssertTrue(first.advance)
        XCTAssertEqual(first.remaining, 2)
        let second = KinetiqBingeGuardPolicy.completedEpisode(remaining: 2, autoplay: true)
        XCTAssertTrue(second.advance)
        XCTAssertEqual(second.remaining, 1)
        let last = KinetiqBingeGuardPolicy.completedEpisode(remaining: 1, autoplay: true)
        XCTAssertFalse(last.advance)
        XCTAssertNil(last.remaining)
        XCTAssertFalse(KinetiqBingeGuardPolicy.completedEpisode(remaining: 4, autoplay: false).advance)
    }

    func testActionFinderHasUniqueSearchableWorkingCommands() {
        let actions = KinetiqPlayerAction.allCases
        XCTAssertGreaterThan(actions.count, 30)
        XCTAssertEqual(Set(actions.map(\.title)).count, actions.count)
        XCTAssertTrue(actions.contains(.recovery))
        XCTAssertTrue(actions.contains(.study))
        XCTAssertTrue(actions.contains(.copyDiagnostics))
    }
}
