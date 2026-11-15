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
        XCTAssertEqual(activity["name"] as? String, "Blue Box Season 2")
        XCTAssertEqual(activity["application_id"] as? String,
                       KinetiqDiscordActivity.applicationID)
        XCTAssertEqual(activity["details"] as? String, "Blue Box Season 2")
        XCTAssertEqual(activity["state"] as? String, "Episode 3 · SUB")
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
        XCTAssertEqual(activity?["state"] as? String, "Episode 3 · SUB · Paused")
    }

    func testSignedOrPrivateArtworkIsNeverSent() {
        for url in [
            "https://img.example.org/cover.jpg?token=secret",
            "file:///private/cover.jpg",
            "http://img.example.org/cover.jpg",
            "https://user:password@img.example.org/cover.jpg"
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
