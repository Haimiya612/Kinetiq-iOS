"""Static M04 integration checks; native iOS compilation is still required."""
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def swift(path):
    return (ROOT / path).read_text(encoding="utf-8")


class M04Contracts(unittest.TestCase):
    def test_unchanged_app_version(self):
        pbx = swift("Kinetiq.xcodeproj/project.pbxproj")
        self.assertIn("MARKETING_VERSION = 0.3.0", pbx)
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 17.0", pbx)

    def test_substudio_compiled_into_app_target(self):
        pbx = swift("Kinetiq.xcodeproj/project.pbxproj")
        self.assertIn("KinetiqSubStudio.swift in Sources", pbx)
        self.assertIn("A16E05000000000000000002);", pbx)

    def test_foreground_notice_has_one_owner(self):
        app = swift("Kinetiq/App/KinetiqApp.swift")
        self.assertEqual(app.count("KinetiqNoticeBannerHost()"), 1)
        self.assertIn("KinetiqPassThroughNoticeWindow", app)
        self.assertIn("override func hitTest", app)

    def test_control_confirmation_is_only_on_transport(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn("pendingTransportChange = .previous", player)
        self.assertIn("pendingTransportChange = .next", player)
        self.assertIn("Play previous episode?", player)
        self.assertIn("Keep Watching", player)
        self.assertIn(".lockControlsAction {", player)
        chrome = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        self.assertIn("configured.onLockControls = action", chrome)

    def test_seamless_handoff_and_original_loader_both_exist(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn("if hasPresentedVideoOnce", player)
        self.assertIn("KinetiqModuleLoadingScene(", player)
        self.assertIn("Opening \\(session.currentEpisodeTitle)", player)

    def test_second_and_third_tracks_are_not_fabricated(self):
        studio = swift("Kinetiq/Features/Modules/KinetiqSubStudio.swift")
        self.assertIn("case secondary", studio)
        self.assertIn("case tertiary", studio)
        self.assertIn("ModuleSubtitleLoader.load(track)", studio)
        self.assertIn("CFStringTokenizer", studio)
        self.assertIn("func transcript(for slot:", studio)
        self.assertIn("func search(_ phrase:", studio)
        self.assertIn("func readabilityPercentage", studio)
        self.assertIn('CFLocaleCreate(kCFAllocatorDefault, "ja_JP")', studio)
        self.assertIn("CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0", studio)
        self.assertNotIn("kCFStringTokenizerTokenNone", studio)

    def test_more_stays_complete_but_collapsed(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn("Show Advanced Tools", player)
        self.assertIn("if showAdvancedOptions", player)
        self.assertIn("Find a player action", player)
        self.assertIn("powerDeck", player)


if __name__ == "__main__":
    unittest.main()
