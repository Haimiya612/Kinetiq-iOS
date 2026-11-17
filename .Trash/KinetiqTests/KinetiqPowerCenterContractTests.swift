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
