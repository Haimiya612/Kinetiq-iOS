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
        XCTAssertEqual(activity["application_id"] as? String,
                       KinetiqDiscordActivity.applicationID)
        XCTAssertEqual(activity["details"] as? String, "Blue Box Season 2")
        XCTAssertEqual(activity["state"] as? String, "Episode 3 · SUB")
        let poster = try XCTUnwrap(activity["assets"] as? [String: String])
        XCTAssertEqual(poster["large_image"], "https://img.example.org/posters/blue-box.jpg")
        let timestamps = try XCTUnwrap(activity["timestamps"] as? [String: Int])
        XCTAssertEqual(timestamps["start"], 1_880)
        XCTAssertEqual(timestamps["end"], 3_320)
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
