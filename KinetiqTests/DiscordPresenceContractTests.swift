import Foundation
import XCTest
@testable import Kinetiq

/// Offline contract tests. These do not authenticate a user or imply that
/// Discord accepts unofficial Rich Presence updates on an iPhone.
final class DiscordPresenceContractTests: XCTestCase {
    private func playback(
        poster: String? = "https://img.example.org/posters/blue-box.jpg",
        playing: Bool = true
    ) -> KinetiqPresencePlayback {
        KinetiqPresencePlayback(
            animeTitle: "Blue Box Season 2", episodeNumber: "3",
            episodeTitle: "A New Promise", language: "sub",
            posterURL: poster.flatMap(URL.init(string:)),
            position: 120, duration: 1_440, isPlaying: playing,
            isPictureInPicture: false
        )
    }

    func testWatchingPresenceCarriesAppIDAnimeTitleEpisodeAndPublicPoster() throws {
        let value = KinetiqDiscordActivity.payload(
            for: playback(), now: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(value["op"] as? Int, 3)
        let body = try XCTUnwrap(value["d"] as? [String: Any])
        let activity = try XCTUnwrap((body["activities"] as? [[String: Any]])?.first)
        XCTAssertEqual(activity["type"] as? Int, 3)
        XCTAssertEqual(activity["name"] as? String, "Kinetiq")
        XCTAssertEqual(activity["application_id"] as? String,
                       KinetiqDiscordActivity.applicationID)
        XCTAssertEqual(activity["details"] as? String, "Blue Box Season 2")
        XCTAssertEqual(activity["state"] as? String, "Episode 3: A New Promise · SUB")
        let poster = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(poster["large_image"], "https://img.example.org/posters/blue-box.jpg")
        let timestamps = try XCTUnwrap(activity["timestamps"] as? [String: Int])
        XCTAssertEqual(timestamps["start"], 1_880_000)
        XCTAssertEqual(timestamps["end"], 3_320_000)
    }

    func testPlaybackClockFormatsElapsedAndHourLongEpisodes() {
        XCTAssertEqual(KinetiqDiscordActivity.clock(0), "00:00")
        XCTAssertEqual(KinetiqDiscordActivity.clock(754.9), "12:34")
        XCTAssertEqual(KinetiqDiscordActivity.clock(3_723), "1:02:03")
        XCTAssertEqual(KinetiqDiscordActivity.clock(.infinity), "00:00")
    }

    func testAllSixDiscordActivityTypesCanBeSelected() throws {
        XCTAssertEqual(KinetiqDiscordActivityType.allCases.map(\.rawValue), Array(0...5))
        for type in KinetiqDiscordActivityType.allCases {
            let streamingURL = type == .streaming ? URL(string: "https://twitch.tv/kinetiq") : nil
            let value = KinetiqDiscordActivity.payload(
                for: playback(), activityType: type, streamingURL: streamingURL
            )
            let body = try XCTUnwrap(value["d"] as? [String: Any])
            let activity = try XCTUnwrap((body["activities"] as? [[String: Any]])?.first)
            XCTAssertEqual(activity["type"] as? Int, type.rawValue, "Wrong code for \(type.title)")
            if type == .streaming {
                XCTAssertEqual(activity["url"] as? String, "https://twitch.tv/kinetiq")
            }
        }
    }

    func testHeadingStylesKeepKinetiqNameAndAnimeInDetails() throws {
        for style in KinetiqDiscordNameStyle.allCases {
            let value = KinetiqDiscordActivity.payload(for: playback(), nameStyle: style)
            let activity = try XCTUnwrap(
                ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
            )
            XCTAssertEqual(activity["name"] as? String, style.rawValue)
            XCTAssertEqual(activity["details"] as? String, "Blue Box Season 2")
            XCTAssertEqual(activity["state"] as? String, "Episode 3: A New Promise · SUB")
        }
    }

    func testRegisteredArtOverridesRemotePosterWithoutChangingMetadata() throws {
        let value = KinetiqDiscordActivity.payload(for: playback(),
            nameStyle: .onKinetiq, registeredPosterKey: "ALYA_POSTER")
        let activity = try XCTUnwrap(
            ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(activity["name"] as? String, "on Kinetiq")
        let assets = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(assets["large_image"], "alya_poster")
        XCTAssertNil(KinetiqDiscordActivity.registeredAssetKey("../../secret"))
        XCTAssertNil(KinetiqDiscordActivity.registeredAssetKey("https://example.org/image.png"))
        XCTAssertNil(KinetiqDiscordActivity.registeredAssetKey(String(repeating: "a", count: 65)))
    }

    func testStreamingNeedsGenuineTwitchOrYouTubeURL() throws {
        for raw in [
            "http://twitch.tv/example", "https://twitch.tv.evil.example/live",
            "https://youtube.com@evil.example/watch", "https://example.org/watch"
        ] {
            XCTAssertNil(KinetiqDiscordActivity.validStreamingURL(raw))
        }
        XCTAssertNotNil(KinetiqDiscordActivity.validStreamingURL("https://www.youtube.com/watch?v=abc"))

        let value = KinetiqDiscordActivity.payload(for: playback(), activityType: .streaming)
        let body = try XCTUnwrap(value["d"] as? [String: Any])
        let activity = try XCTUnwrap((body["activities"] as? [[String: Any]])?.first)
        XCTAssertEqual(activity["type"] as? Int, 3, "Streaming without a URL must fall back to Watching")
        XCTAssertNil(activity["url"])
    }

    func testCustomStatusUsesItsOwnPresentationWithoutRichCard() throws {
        let value = KinetiqDiscordActivity.payload(for: playback(), activityType: .custom)
        let body = try XCTUnwrap(value["d"] as? [String: Any])
        let activity = try XCTUnwrap((body["activities"] as? [[String: Any]])?.first)
        XCTAssertEqual(activity["type"] as? Int, 4)
        XCTAssertTrue((activity["state"] as? String)?.contains("Blue Box Season 2") == true)
        let emoji = try XCTUnwrap(activity["emoji"] as? [String: String])
        XCTAssertEqual(emoji["name"], "🍿")
        XCTAssertNil(activity["assets"])
        XCTAssertNil(activity["timestamps"])
    }

    func testPublicMetadataPosterCanOverrideProviderPoster() throws {
        let value = KinetiqDiscordActivity.payload(
            for: playback(poster: "https://images.example.org/old-cover.jpg"),
            posterOverride: URL(string: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/example.jpg")
        )
        let activity = try XCTUnwrap(
            ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
        )
        let poster = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertTrue(poster["large_image"]?.contains("s4.anilist.co") == true)
    }

    func testDiscordMediaProxyResponseBecomesRichPresenceArtwork() throws {
        let response = Data("""
        [{"url":"https://s4.anilist.co/cover.jpg","external_asset_path":"external/abc123/https/s4.anilist.co/cover.jpg"}]
        """.utf8)
        let image = try XCTUnwrap(KinetiqDiscordExternalArtwork.proxyIdentifier(from: response))
        XCTAssertEqual(image, "mp:external/abc123/https/s4.anilist.co/cover.jpg")

        let value = KinetiqDiscordActivity.payload(
            for: playback(), mediaProxyPoster: image
        )
        let activity = try XCTUnwrap(
            ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
        )
        let assets = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(assets["large_image"], image,
                       "Use Discord's registered mp: path, not the original HTTPS image URL")
        XCTAssertEqual(activity["state"] as? String, "Episode 3: A New Promise · SUB")
    }

    func testSquareArtworkUsesHighQualityAttentionAwareCrop() throws {
        let original = try XCTUnwrap(URL(string: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/anime.jpg"))
        let square = try XCTUnwrap(KinetiqDiscordArtworkRenderer.renderedURL(
            for: original, style: .smartSquare
        ))
        let query = try XCTUnwrap(URLComponents(url: square, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(square.host, "wsrv.nl")
        XCTAssertEqual(values["url"], original.absoluteString)
        XCTAssertEqual(values["w"], "1024")
        XCTAssertEqual(values["h"], "1024")
        XCTAssertEqual(values["fit"], "cover")
        XCTAssertEqual(values["a"], "attention")
        XCTAssertEqual(values["output"], "jpg")
        XCTAssertEqual(values["q"], "94")
        XCTAssertTrue(KinetiqDiscordArtworkRenderer.isGeneratedURL(square))
    }

    func testFullPosterFramingAndOriginalFallback() throws {
        let original = try XCTUnwrap(URL(string: "https://images.example.org/poster.jpg"))
        let framed = try XCTUnwrap(KinetiqDiscordArtworkRenderer.renderedURL(
            for: original, style: .fullPoster
        ))
        let values = Dictionary(uniqueKeysWithValues: try XCTUnwrap(
            URLComponents(url: framed, resolvingAgainstBaseURL: false)?.queryItems
        ).compactMap { item in item.value.map { (item.name, $0) } })
        XCTAssertEqual(values["fit"], "contain")
        XCTAssertEqual(values["cbg"], "171717")
        XCTAssertTrue(KinetiqDiscordArtworkRenderer.isGeneratedURL(framed))
        XCTAssertEqual(KinetiqDiscordArtworkRenderer.renderedURL(
            for: original, style: .original
        ), original)
    }

    func testImageServiceCannotProxySecretURLsOrArbitraryTransformations() throws {
        let signedURL = try XCTUnwrap(URL(string: "https://images.example.org/poster.jpg?token=secret"))
        XCTAssertNil(KinetiqDiscordArtworkRenderer.renderedURL(for: signedURL, style: .smartSquare))
        let localURL = try XCTUnwrap(URL(string: "https://192.168.0.1/private.jpg"))
        XCTAssertNil(KinetiqDiscordArtworkRenderer.renderedURL(for: localURL, style: .fullPoster))
        let arbitrary = try XCTUnwrap(URL(string:
            "https://wsrv.nl/?url=https://images.example.org/poster.jpg&w=1024&h=1024&fit=cover&a=attention&output=jpg&q=30"
        ))
        XCTAssertFalse(KinetiqDiscordArtworkRenderer.isGeneratedURL(arbitrary))
        XCTAssertFalse(KinetiqDiscordArtworkRenderer.isGeneratedURL(try XCTUnwrap(URL(string:
            "https://wsrv.nl/?url=https://images.example.org/poster.jpg?token=secret&w=1024&h=1024&fit=cover"
        ))))
    }

    func testDeveloperPortalAssetStillOverridesResolvedMediaProxy() throws {
        let value = KinetiqDiscordActivity.payload(
            for: playback(), registeredPosterKey: "ALYA_POSTER",
            mediaProxyPoster: "mp:external/abc123/https/s4.anilist.co/cover.jpg"
        )
        let activity = try XCTUnwrap(
            ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
        )
        let assets = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(assets["large_image"], "alya_poster")
    }

    func testMalformedProxyIdentifiersAreNeverUsed() {
        let invalid = [
            "https://s4.anilist.co/cover.jpg", "mp:external/", "mp:attachments/123",
            "mp:external/x\nAuthorization: token",
            String(repeating: "z", count: 301)
        ]
        for value in invalid {
            XCTAssertNil(KinetiqDiscordActivity.mediaProxyAsset(value), value)
        }
        let malformed = [
            Data("[]".utf8), Data("[{\"external_asset_path\":\"https://bad.example\"}]".utf8),
            Data("{\"external_asset_path\":\"external/id\"}".utf8)
        ]
        for response in malformed {
            XCTAssertNil(KinetiqDiscordExternalArtwork.proxyIdentifier(from: response))
        }
    }

    func testUnsafeMetadataPosterFallsBackToProviderPoster() throws {
        let value = KinetiqDiscordActivity.payload(
            for: playback(), posterOverride: URL(string: "https://unsafe.example/cover.jpg?token=private")
        )
        let activity = try XCTUnwrap(
            ((value["d"] as? [String: Any])?["activities"] as? [[String: Any]])?.first
        )
        let poster = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(poster["large_image"], "https://img.example.org/posters/blue-box.jpg")
    }

    func testPausingRemovesRunningTimer() {
        let value = KinetiqDiscordActivity.payload(for: playback(playing: false))
        let body = value["d"] as? [String: Any]
        let activity = (body?["activities"] as? [[String: Any]])?.first
        XCTAssertNil(activity?["timestamps"])
        XCTAssertEqual(activity?["state"] as? String, "Episode 3: A New Promise · SUB · Paused")
    }

    func testSeekingAndTemporaryBufferingDoNotAppearAsUserPauses() {
        // AVPlayer can temporarily stop reporting .playing on each +10s seek.
        // A stream already playing is still considered playing while the
        // player's requested state is Play, even if its observed status lags.
        XCTAssertTrue(KinetiqPresencePlaybackIntent.isPlaying(
            requestedPlayback: true,
            hasStartedCurrentItem: true,
            playerReportsPlaying: false
        ))
        XCTAssertTrue(KinetiqPresencePlaybackIntent.isPlaying(
            requestedPlayback: true,
            hasStartedCurrentItem: false,
            playerReportsPlaying: true
        ))
        XCTAssertFalse(KinetiqPresencePlaybackIntent.isPlaying(
            requestedPlayback: true,
            hasStartedCurrentItem: false,
            playerReportsPlaying: false
        ), "An episode that never started must not claim to be playing")
        XCTAssertFalse(KinetiqPresencePlaybackIntent.isPlaying(
            requestedPlayback: false,
            hasStartedCurrentItem: true,
            playerReportsPlaying: true
        ), "Pressing Pause must win even before AVPlayer catches up")
    }

    func testEpisodeTitleFallsBackForGenericTitlesAndReservesLanguageSuffix() {
        let generic = KinetiqPresencePlayback(
            animeTitle: "Anime", episodeNumber: "1", episodeTitle: "Episode 1",
            language: "sub", posterURL: nil, position: 2, duration: 20,
            isPlaying: true, isPictureInPicture: false
        )
        XCTAssertEqual(KinetiqDiscordActivity.state(for: generic), "Episode 1 · SUB")

        let prefixed = KinetiqPresencePlayback(
            animeTitle: "Anime", episodeNumber: "3", episodeTitle: "Episode 3: A New Promise",
            language: "sub", posterURL: nil, position: 2, duration: 20,
            isPlaying: true, isPictureInPicture: false
        )
        XCTAssertEqual(KinetiqDiscordActivity.state(for: prefixed),
                       "Episode 3: A New Promise · SUB")

        let long = KinetiqPresencePlayback(
            animeTitle: "Anime", episodeNumber: "2",
            episodeTitle: String(repeating: "A Very Long Episode Title ", count: 6),
            language: "dub", posterURL: nil, position: 4, duration: 90,
            isPlaying: false, isPictureInPicture: false
        )
        let value = KinetiqDiscordActivity.state(for: long)
        XCTAssertLessThanOrEqual(value.count, 128)
        XCTAssertTrue(value.hasPrefix("Episode 2: "))
        XCTAssertTrue(value.hasSuffix(" · DUB · Paused"))
    }

    func testSignedOrPrivateArtworkIsNeverSent() {
        for url in [
            "https://img.example.org/cover.jpg?token=secret",
            "file:///private/cover.jpg",
            "http://img.example.org/cover.jpg",
            "https://user:password@img.example.org/cover.jpg",
            "https://192.168.1.20/poster.jpg",
            "https://images.internal/poster.jpg"
        ] {
            XCTAssertNil(KinetiqDiscordActivity.publicArtwork(for: playback(poster: url)))
        }
    }

    func testPayloadNeverContainsCredentialField() throws {
        let value = KinetiqDiscordActivity.payload(for: playback())
        let json = try JSONSerialization.data(withJSONObject: value)
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertFalse(text.contains("token"))
        XCTAssertFalse(text.contains("authorization"))
    }
}
