import XCTest
import Foundation
@testable import Kinetiq

final class OfflineDownloadContractTests: XCTestCase {
    func testSizeEstimatesNeverInventUnknownStreamDimensions() {
        XCTAssertNil(KinetiqOfflineSizeEstimate.approximateBytes(minutes: nil, peakBitRate: 2_000_000))
        XCTAssertNil(KinetiqOfflineSizeEstimate.approximateBytes(minutes: 24, peakBitRate: nil))
        XCTAssertNil(KinetiqOfflineSizeEstimate.approximateBytes(minutes: -1, peakBitRate: 2_000_000))
        XCTAssertNil(KinetiqOfflineSizeEstimate.approximateBytes(minutes: 24, peakBitRate: .infinity))
        XCTAssertEqual(KinetiqOfflineSizeEstimate.approximateBytes(minutes: 24,
            peakBitRate: 2_000_000), 360_000_000)
    }

    func testQueueReorderOnlyChangesWaitingJobsAndPersistsTheirRelativePriority() {
        func item(_ id: String, _ state: KinetiqOfflineState) -> KinetiqOfflineEntry {
            KinetiqOfflineEntry(
                id: id, sourceID: "module", sourceName: "Module", animeID: "anime",
                animeTitle: "Anime", episodeID: id, episodeNumber: id,
                language: "sub", artworkURL: nil, format: .file,
                quality: "Original", createdAt: .now, state: state,
                progress: 0, localPath: nil, bytes: 0, resumeSeconds: 0, error: nil
            )
        }
        let entries = [item("one", .queued), item("active", .downloading),
                       item("two", .queued), item("finished", .ready), item("three", .queued)]
        let higher = KinetiqOfflineQueueOrder.moved(entries, id: "three", towardFront: true)
        XCTAssertEqual(higher.map(\.id), ["one", "active", "three", "finished", "two"])
        XCTAssertEqual(KinetiqOfflineQueueOrder.moved(entries, id: "one", towardFront: true).map(\.id),
                       entries.map(\.id))
        XCTAssertEqual(KinetiqOfflineQueueOrder.moved(entries, id: "active", towardFront: false).map(\.id),
                       entries.map(\.id))
        XCTAssertEqual(KinetiqOfflineQueueOrder.moved(entries, id: "two", towardFront: false).map(\.id),
                       ["one", "active", "three", "finished", "two"])
    }

    func testPerSeriesStorageBudgetKeepsEverySourceSeparateAndHasNoStreamingSecrets() throws {
        let name = "kinetiq.m02.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(KinetiqOfflineSeriesBudget.limit(sourceID: "A", animeID: "one",
            defaults: defaults), 0)
        KinetiqOfflineSeriesBudget.setLimit(2, sourceID: "A", animeID: "one", defaults: defaults)
        XCTAssertEqual(KinetiqOfflineSeriesBudget.limit(sourceID: "A", animeID: "one",
            defaults: defaults), 2)
        XCTAssertEqual(KinetiqOfflineSeriesBudget.limit(sourceID: "A", animeID: "two",
            defaults: defaults), 0)
        XCTAssertEqual(KinetiqOfflineSeriesBudget.limit(sourceID: "B", animeID: "one",
            defaults: defaults), 0)
        KinetiqOfflineSeriesBudget.setLimit(0, sourceID: "A", animeID: "one", defaults: defaults)
        XCTAssertEqual(KinetiqOfflineSeriesBudget.limit(sourceID: "A", animeID: "one",
            defaults: defaults), 0)
        XCTAssertFalse(KinetiqOfflineSeriesBudget.key(sourceID: "A", animeID: "one").contains("one"))
    }

    func testTravelManifestExportsNoLocalPathsOrStreamSecrets() throws {
        let entry = savedEntry(format: .file, path: "/private/kinetiq/secret.mp4")
        let audit = KinetiqTravelAudit.inspect([entry])
        let named = KinetiqTravelManifest(results: audit, includeNames: true)
        let encoded = try JSONEncoder().encode(named)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertEqual(named.episodes.count, 1)
        XCTAssertEqual(named.episodes.first?.title, "Blue Box")
        XCTAssertFalse(text.contains("/private/"))
        XCTAssertFalse(text.contains("secret.mp4"))
        XCTAssertFalse(text.contains("Authorization"))
        XCTAssertFalse(text.contains("https://"))
        let anonymous = KinetiqTravelManifest(results: audit, includeNames: false)
        XCTAssertEqual(anonymous.episodes.first?.title, "Hidden title")
        XCTAssertEqual(anonymous.episodes.first?.source, "Hidden source")
    }

    func testSeasonBatchPolicyKeepsSourceEpisodeAndLanguageIdentity() {
        let subOnly = ModuleAnimeEpisode(id: "sub-1", number: "1",
            href: "/episode/1", subAvailable: true, dubAvailable: false)
        let bilingual = ModuleAnimeEpisode(id: "both-2", number: "2",
            href: "/episode/2", subAvailable: true, dubAvailable: true)
        let dubOnly = ModuleAnimeEpisode(id: "dub-3", number: "3",
            href: "/episode/3", subAvailable: false, dubAvailable: true)

        XCTAssertTrue(KinetiqOfflineBatchPolicy.supports(subOnly, language: "sub"))
        XCTAssertFalse(KinetiqOfflineBatchPolicy.supports(subOnly, language: "dub"))
        XCTAssertTrue(KinetiqOfflineBatchPolicy.supports(bilingual, language: "sub"))
        XCTAssertTrue(KinetiqOfflineBatchPolicy.supports(bilingual, language: "dub"))
        XCTAssertFalse(KinetiqOfflineBatchPolicy.supports(dubOnly, language: "sub"))
        XCTAssertTrue(KinetiqOfflineBatchPolicy.supports(dubOnly, language: "dub"))
        XCTAssertFalse(KinetiqOfflineBatchPolicy.supports(bilingual, language: "unknown"))
        XCTAssertGreaterThanOrEqual(KinetiqOfflineBatchPolicy.maximumEpisodes, 24)
        XCTAssertLessThanOrEqual(KinetiqOfflineBatchPolicy.maximumEpisodes, 100)
    }

    private func savedEntry(format: KinetiqOfflineFormat, path: String,
                            captions: [KinetiqSavedSubtitleTrack] = []) -> KinetiqOfflineEntry {
        KinetiqOfflineEntry(
            id: String(repeating: "d", count: 64),
            sourceID: "source", sourceName: "Source", animeID: "anime",
            animeTitle: "Blue Box", episodeID: "episode-1", episodeNumber: "1",
            language: "sub", artworkURL: nil, format: format, quality: "Original",
            createdAt: .now, state: .ready, progress: 1,
            localPath: path, bytes: 256, resumeSeconds: 0, error: nil,
            subtitleTracks: captions
        )
    }

    func testOfflineAuditRejectsMissingAndDamagedVideoFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetiq-offline-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("episode.mp4")
        let entry = savedEntry(format: .file, path: video.path)
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try Data().write(to: video)
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try Data("<!doctype html>".utf8).write(to: video)
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try Data([0, 0, 0, 16] + Array("ftypisom".utf8)).write(to: video)
        XCTAssertNil(KinetiqOfflineFileAudit.failureReason(for: entry))
    }

    func testOfflineAuditRequiresEverySavedSubtitleToBeIntact() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetiq-offline-captions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("episode.mp4")
        let subtitle = folder.appendingPathComponent("eng.vtt")
        let bytes = Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello".utf8)
        try Data([0, 0, 0, 16] + Array("ftypisom".utf8)).write(to: video)
        let caption = KinetiqSavedSubtitleTrack(label: "English", language: "en",
            format: "vtt", localPath: subtitle.path, bytes: Int64(bytes.count))
        let entry = savedEntry(format: .file, path: video.path, captions: [caption])
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try bytes.write(to: subtitle)
        XCTAssertNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try Data("WEBVTT".utf8).write(to: subtitle)
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
    }

    func testOfflineAuditRequiresANonemptyHLSPackage() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetiq-offline-hls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("episode.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let entry = savedEntry(format: .hls, path: package.path)
        XCTAssertNotNil(KinetiqOfflineFileAudit.failureReason(for: entry))
        try Data([1, 2, 3]).write(to: package.appendingPathComponent("segment.ts"))
        XCTAssertNil(KinetiqOfflineFileAudit.failureReason(for: entry))
    }

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
