"""Static M04 integration checks; native iOS compilation is still required."""
import unittest
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def swift(path):
    return (ROOT / path).read_text(encoding="utf-8")


class M04Contracts(unittest.TestCase):
    def test_shared_chrome_explicit_initializer_wires_every_action(self):
        chrome = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        self.assertIn("init(\n        safeAreaInsets:", chrome)
        for name in (
            "safeAreaInsets", "title", "playing", "busy", "aspectFill",
            "pictureInPictureAvailable", "displayedTime", "duration",
            "elapsedLabel", "durationLabel", "panels", "airPlayControl",
            "onClose", "onStartPictureInPicture", "onLockControls",
            "onToggleAspect", "onPrevious", "onRewind", "onTogglePlay",
            "onForward", "onNext", "onSeekChanged", "onSeekEditingChanged",
            "onPanelSelected"
        ):
            self.assertIn(f"self.{name} = {name}", chrome)

    def test_shared_chrome_has_single_compiled_definition(self):
        # Regression for run #205: the fixed source existed on GitHub, but
        # Xcode compiled a different, outdated inline copy of the same type.
        pbx = swift("Kinetiq.xcodeproj/project.pbxproj")
        chrome = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        for view_name in (
            "KinetiqUnifiedPlayerChrome",
            "KinetiqUnifiedPlayerOptionsFrame",
            "KinetiqUnifiedPlayerFailureOverlay",
        ):
            self.assertEqual(len(re.findall(r"struct " + view_name + r"(?:<|:)", chrome)), 1)
            self.assertNotIn("struct " + view_name, player)
        self.assertRegex(pbx, r"/\* KinetiqUnifiedPlayer\.swift in Sources \*/ = \{isa = PBXBuildFile")
        self.assertRegex(pbx, r"/\* KinetiqUnifiedPlayer\.swift \*/ = \{isa = PBXFileReference")
        build_phase = re.search(r"8682261519D15BD64A9E5D31 /\* Sources \*/ = \{isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);", pbx, re.S)
        self.assertIsNotNone(build_phase)
        self.assertEqual(build_phase.group(1).count("A16E06000000000000000002"), 1)

    def test_all_swift_app_sources_are_registered(self):
        pbx = swift("Kinetiq.xcodeproj/project.pbxproj")
        missing = [path.name for path in (ROOT / "Kinetiq").rglob("*.swift")
                   if not re.search(r"/\* " + re.escape(path.name) + r" \*/ = \{isa = PBXFileReference", pbx)]
        self.assertEqual(missing, [], "Swift source files missing from Xcode project: " + ", ".join(missing))

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
        self.assertIn("onLockControls: {", player)
        chrome = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        self.assertIn("let onLockControls: (() -> Void)?", chrome)
        self.assertIn("self.onLockControls = onLockControls", chrome)
        self.assertNotIn("func lockControlsAction", chrome)
        library = swift("Kinetiq/Features/Library/LibraryView.swift")
        self.assertIn("onLockControls: nil", library)

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
        self.assertIn('CFLocaleIdentifier("ja_JP" as CFString)', studio)
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
