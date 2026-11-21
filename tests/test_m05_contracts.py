"""Static M05A safety wiring checks; not a substitute for Xcode."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def swift(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class M05Contracts(unittest.TestCase):
    def test_failed_player_has_portrait_safe_escape(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn('Label("Close Player", systemImage: "xmark.circle.fill")', player)
        self.assertIn('Label("Close", systemImage: "chevron.down")', player)
        self.assertIn('if playback.errorMessage != nil', player)
        self.assertIn('max(geometry.safeAreaInsets.top, 56)', player)

    def test_substudio_scrollable_sheet_replaces_menu(self):
        studio = swift("Kinetiq/Features/Modules/KinetiqSubStudio.swift")
        self.assertIn('.sheet(item: $pickingSlot)', studio)
        self.assertIn('.presentationDetents([.medium, .large])', studio)
        self.assertNotIn('Menu {\n                        Button("Off"', studio)
        self.assertIn('track.id != primaryTrackID', studio)
        self.assertIn('studio.select(track, for: slot)', studio)

    def test_substudio_caption_line_explicitly_returns_view(self):
        studio = swift("Kinetiq/Features/Modules/KinetiqSubStudio.swift")
        self.assertIn('let tint = softColors ? Color.white : color\n        return VStack(spacing: 2)', studio)

    def test_recommended_media_does_not_fabricate_matching_titles(self):
        home = swift("Kinetiq/Features/Home/HomeView.swift")
        self.assertIn('KinetiqCrossSourceSearchPolicy.relevance', home)
        self.assertIn('sourceHint(', home)
        self.assertIn('let newItems = decoded.filter', home)
        self.assertIn('"Find similar"', home)
        self.assertIn('Matching AniList title:', home)
        self.assertIn('!genre.isEmpty', home)
        self.assertIn('Finding titles for you', home)
        self.assertNotIn('Loading real catalogue', home)

    def test_brain_transcripts_opt_in_and_protected(self):
        brain = swift("Kinetiq/Features/Discovery/KinetiqBrain.swift")
        self.assertIn('keepLocalChat = false', brain)
        self.assertIn('Data(contentsOf: file)', brain)
        self.assertIn('.completeFileProtection', brain)
        self.assertIn('showingClearChatConfirmation', brain)
        self.assertNotIn('nativeBrain.respond(to: String', brain)

    def test_pip_auto_return_is_off_by_default(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        settings = swift("Kinetiq/Features/Settings/SettingsView.swift")
        self.assertIn('if returnPiPOnForeground && pictureInPicture.isActuallyActive', player)
        self.assertIn('pictureInPicture.stop()', player)
        self.assertIn('private var returnPiPOnForeground = false', settings)

    def test_discord_seek_burst_waits_and_does_not_publish_error_activity(self):
        rpc = swift("Kinetiq/Features/Integrations/KinetiqDiscordPresence.swift")
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn('recentSeekSamples.count >= 4', rpc)
        self.assertIn('now.addingTimeInterval(12)', rpc)
        self.assertIn('allowedAt = max(allowedAt, rapidSeekCooldownUntil)', rpc)
        self.assertIn('guard playback.hasFinishedPresentingFirstFrame', player)
        self.assertIn('playbackEnded()', player)

    def test_player_styles_share_xcode_compiled_chrome(self):
        chrome = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        settings = swift("Kinetiq/Features/Settings/SettingsView.swift")
        self.assertIn('enum KinetiqPlayerChromeStyle', chrome)
        self.assertIn('struct KinetiqPlayerAppearancePicker', chrome)
        self.assertIn('KinetiqPlayerAppearanceSettingsView()', settings)


if __name__ == '__main__':
    unittest.main()
