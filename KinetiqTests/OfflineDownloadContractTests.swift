import XCTest
import Foundation
@testable import Kinetiq

final class OfflineDownloadContractTests: XCTestCase {
    private func stream(_ url: String, type: String = "mp4",
                        headers: [String: String] = [:]) -> ModuleResolvedStream {
        ModuleResolvedStream(title: "Episode", label: "Server",
            url: URL(string: url)!, headers: headers, streamType: type)
    }

    func testEpisodeIdentityIsStableAndSourceScoped() {
        let first = KinetiqOfflineEntry.identity(
            sourceID: "source-A", animeID: "anime", episodeID: "episode-5", language: "sub")
        XCTAssertEqual(first, KinetiqOfflineEntry.identity(
            sourceID: "source-A", animeID: "anime", episodeID: "episode-5", language: "sub"))
        XCTAssertNotEqual(first, KinetiqOfflineEntry.identity(
            sourceID: "source-B", animeID: "anime", episodeID: "episode-5", language: "sub"))
        XCTAssertNotEqual(first, KinetiqOfflineEntry.identity(
            sourceID: "source-A", animeID: "anime", episodeID: "episode-5", language: "dub"))
        XCTAssertNotEqual(first, KinetiqOfflineEntry.identity(
            sourceID: "source-A", animeID: "anime", episodeID: "episode-6", language: "sub"))
        XCTAssertEqual(first.count, 64)
    }

    func testDirectHTTPSStreamsDoNotNeedOfflineManifestOptIn() {
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/video.mp4?token=private")), .file)
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/master.m3u8", type: "hls")), .hls)
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/play?id=5", type: "M3U8")), .hls)
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/play?id=5", type: "video/mp4; codecs=avc1")), .file)
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/play?id=5", type: "video/quicktime")), .file)
        // Legitimate stream CDNs often differ from the source module host.
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://other.example.org/video.mp4")), .file)
        XCTAssertNil(KinetiqOfflineEligibility.format(
            for: stream("http://media.example.org/video.mp4")))
        XCTAssertNil(KinetiqOfflineEligibility.format(
            for: stream("https://user:secret@media.example.org/video.mp4")))
        XCTAssertNil(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/embed/abcd", type: "embed")))
        XCTAssertEqual(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/master.m3u8", type: "hls",
                        headers: ["Referer": "https://provider.example.org"])), .hls)
        XCTAssertNil(KinetiqOfflineEligibility.format(
            for: stream("https://media.example.org/page", type: "html")))
    }

    func testQualityOnlyChoosesActualAdvertisedVariants() {
        let variants = [
            ModuleVideoQualityOption(width: 640, height: 360, peakBitRate: 700_000),
            ModuleVideoQualityOption(width: 1280, height: 720, peakBitRate: 2_500_000),
            ModuleVideoQualityOption(width: 1920, height: 1080, peakBitRate: 5_000_000)
        ]
        XCTAssertNil(KinetiqOfflineEligibility.selectedVariant(
            variants, quality: .original, customID: nil))
        XCTAssertEqual(KinetiqOfflineEligibility.selectedVariant(
            variants, quality: .saver, customID: nil)?.height, 360)
        XCTAssertEqual(KinetiqOfflineEligibility.selectedVariant(
            variants, quality: .balanced, customID: nil)?.height, 720)
        XCTAssertEqual(KinetiqOfflineEligibility.selectedVariant(
            variants, quality: .high, customID: nil)?.height, 1080)
        XCTAssertEqual(KinetiqOfflineEligibility.selectedVariant(
            variants, quality: .custom, customID: "1280x720")?.height, 720)
        XCTAssertNil(KinetiqOfflineEligibility.selectedVariant(
            [], quality: .high, customID: nil))
    }

    @MainActor
    func testFileAndHLSHaveRetainedBackgroundSessionsForBothNetworkPolicies() {
        let store = KinetiqOfflineDownloadStore.shared
        for format in [KinetiqOfflineFormat.file, .hls] {
            XCTAssertTrue(store.isBackgroundSessionAvailable(format: format, wifiOnly: true))
            XCTAssertTrue(store.isBackgroundSessionAvailable(format: format, wifiOnly: false))
        }
    }

    func testOfflineIndexStoresNoStreamCredentials() throws {
        let entry = KinetiqOfflineEntry(
            id: String(repeating: "a", count: 64),
            sourceID: "module-source", sourceName: "Source",
            animeID: "anime", animeTitle: "Anime",
            episodeID: "5", episodeNumber: "5", language: "sub",
            artworkURL: nil, format: .file, quality: "Original",
            createdAt: Date(timeIntervalSince1970: 0), state: .queued,
            progress: 0, localPath: nil, bytes: 0,
            resumeSeconds: 0, error: nil
        )
        let data = try JSONEncoder().encode([entry])
        let saved = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(saved.contains("Authorization"))
        XCTAssertFalse(saved.contains("token="))
        XCTAssertFalse(saved.contains("cookie="))
        XCTAssertEqual(try JSONDecoder().decode([KinetiqOfflineEntry].self, from: data)[0].episodeNumber, "5")
        XCTAssertNil(try JSONDecoder().decode([KinetiqOfflineEntry].self, from: data)[0].episodeTitle)
    }

    @MainActor
    func testOfflineSessionUsesTheExactModulePlaybackContract() {
        let entry = KinetiqOfflineEntry(
            id: String(repeating: "f", count: 64),
            sourceID: "original-source", sourceName: "Original Source",
            animeID: "roshidere", animeTitle: "Roshidere",
            episodeID: "episode-5", episodeNumber: "5", language: "sub",
            artworkURL: nil, format: .file, quality: "Original",
            createdAt: .now, state: .ready, progress: 1,
            localPath: "/missing", bytes: 1024, resumeSeconds: 0, error: nil
        )
        let session = ModuleEpisodePlaybackSession(offline: entry,
            url: URL(fileURLWithPath: "/nonexistent-offline-episode.mp4"), subtitleTracks: [])
        XCTAssertEqual(session.sourceID, "original-source")
        XCTAssertEqual(session.sourceName, "Original Source")
        XCTAssertEqual(session.currentEpisode?.id, "episode-5")
        XCTAssertNil(session.currentEpisode?.title)
        XCTAssertEqual(session.currentStream?.streamType, "mp4")
        XCTAssertEqual(session.currentStream?.url.scheme, "file")
        XCTAssertEqual(session.availableStreams.count, 1)
    }

    func testSavedSubtitleMetadataSurvivesEncoding() throws {
        var entry = KinetiqOfflineEntry(
            id: String(repeating: "b", count: 64),
            sourceID: "s", sourceName: "s", animeID: "a", animeTitle: "a",
            episodeID: "e", episodeNumber: "5", language: "sub",
            artworkURL: nil, format: .hls, quality: "Original",
            createdAt: .now, state: .ready, progress: 1,
            localPath: "/offline", bytes: 200, resumeSeconds: 30, error: nil
        )
        entry.subtitleTracks = [
            KinetiqSavedSubtitleTrack(label: "English CC", language: "en",
                format: "vtt", localPath: "/app/subtitles/00.vtt", bytes: 140),
            KinetiqSavedSubtitleTrack(label: "Deutsch", language: "de",
                format: "srt", localPath: "/app/subtitles/01.srt", bytes: 200)
        ]
        let restored = try JSONDecoder().decode(KinetiqOfflineEntry.self,
            from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.subtitleTracks.count, 2)
        XCTAssertEqual(restored.subtitleTracks.map(\.format), ["vtt", "srt"])
    }

    @MainActor
    func testEpisodeTitleSurvivesOfflinePersistenceAndPlayback() throws {
        let entry = KinetiqOfflineEntry(
            id: String(repeating: "c", count: 64),
            sourceID: "source", sourceName: "Anikage",
            animeID: "jjk", animeTitle: "Jujutsu Kaisen",
            episodeID: "episode-1", episodeNumber: "1",
            episodeTitle: "Ryomen Sukuna", language: "sub",
            artworkURL: nil, format: .file, quality: "Original",
            createdAt: .now, state: .ready, progress: 1,
            localPath: "/video.mp4", bytes: 42, resumeSeconds: 0, error: nil
        )
        let decoded = try JSONDecoder().decode(KinetiqOfflineEntry.self,
            from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.episodeTitle, "Ryomen Sukuna")
        let session = ModuleEpisodePlaybackSession(offline: decoded,
            url: URL(fileURLWithPath: "/video.mp4"), subtitleTracks: [])
        XCTAssertEqual(session.currentEpisode?.title, "Ryomen Sukuna")
        XCTAssertTrue(session.currentEpisode?.subAvailable == true)
        XCTAssertFalse(session.currentEpisode?.dubAvailable == true)
    }
}
