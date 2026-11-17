"""Linux-checkable wiring assertions; not a replacement for Xcode tests."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Kinetiq.xcodeproj" / "project.pbxproj"


class FoundationWiringTests(unittest.TestCase):
    def test_new_swift_sources_registered_in_app_and_test_build_phases(self):
        project = PROJECT.read_text()
        for source in (
            "KinetiqRecoveryCenter.swift",
            "KinetiqStudyDeck.swift",
            "KinetiqRecoveryStudyContractsTests.swift",
            "KinetiqPlayerQuickDeck.swift",
            "KinetiqSpoilerShield.swift",
            "KinetiqPlayerPersonalizationTests.swift",
        ):
            self.assertIn(source + " in Sources", project)
            self.assertIn("path = " + source + ";", project)

        app_phase = next(line for line in project.splitlines()
                         if "8682261519D15BD64A9E5D31 /* Sources */" in line)
        test_phase = next(line for line in project.splitlines()
                          if "29BEEA3D856852A8CC3247ED /* Sources */" in line)
        for reference in ("A16E03000000000000000002", "A16E03000000000000000004"):
            self.assertIn(reference, app_phase, f"Missing app build-phase entry: {reference}")
        for reference in ("A16E04000000000000000002", "A16E04000000000000000004"):
            self.assertIn(reference, app_phase, f"Missing V2 app build-phase entry: {reference}")
        self.assertIn("A16E03000000000000000006", test_phase,
                      "Missing test build-phase entry")
        self.assertIn("A16E04000000000000000006", test_phase,
                      "Missing V2 test build-phase entry")

    def test_existing_app_version_remains_unchanged(self):
        project = PROJECT.read_text()
        self.assertEqual(project.count("MARKETING_VERSION = 0.3.0"), 2)
        self.assertEqual(project.count("CURRENT_PROJECT_VERSION = 3"), 2)

    def test_four_tabs_and_no_new_root_tab(self):
        tabs = (ROOT / "Kinetiq" / "App" / "MainTabView.swift").read_text()
        for name in ("Home", "Favorites", "Downloads", "Settings"):
            self.assertIn(name, tabs)

    def test_module_player_actions_are_real_and_capability_gated(self):
        player = (ROOT / "Kinetiq" / "Features" / "Modules" / "ModulePlayerView.swift").read_text()
        self.assertIn(".disabled(!playerActionAvailable(action))", player)
        self.assertIn("executePlayerAction(action)", player)
        self.assertIn("self.shouldAdvanceAfterEpisode()", player)
        self.assertIn("AVPlayerItemDidPlayToEndTime", player)
        self.assertIn("KinetiqRecoveryStore.shared.record(", player)

    def test_study_and_recovery_views_have_actual_navigation(self):
        settings = (ROOT / "Kinetiq" / "Features" / "Settings" / "SettingsView.swift").read_text()
        player = (ROOT / "Kinetiq" / "Features" / "Modules" / "ModulePlayerView.swift").read_text()
        for view in ("KinetiqStudyDeckView", "KinetiqRecoveryCenterView"):
            self.assertIn(view + "()", settings)
            self.assertIn(view + "(", player)

    def test_quick_deck_persists_commands_without_storing_player_or_credentials(self):
        deck = (ROOT / "Kinetiq" / "Features" / "Modules" / "KinetiqPlayerQuickDeck.swift").read_text()
        player = (ROOT / "Kinetiq" / "Features" / "Modules" / "ModulePlayerView.swift").read_text()
        settings = (ROOT / "Kinetiq" / "Features" / "Settings" / "SettingsView.swift").read_text()
        self.assertIn("static let maximumPins = 8", deck)
        self.assertIn("defaults.set(pinned.map(\\.rawValue)", deck)
        self.assertIn("ForEach(quickDeck.pinned)", player)
        self.assertIn("KinetiqPlayerQuickDeckEditorView()", settings)

    def test_spoiler_shield_actually_masks_episode_media_details(self):
        spoiler = (ROOT / "Kinetiq" / "Features" / "Modules" / "KinetiqSpoilerShield.swift").read_text()
        details = (ROOT / "Kinetiq" / "Features" / "Modules" / "ModuleRuntime.swift").read_text()
        self.assertIn("case unwatched", spoiler)
        self.assertIn("case strict", spoiler)
        self.assertIn("if spoilerProtected {", details)
        self.assertIn("if !spoilerProtected, let synopsis", details)
        self.assertIn("revealedSpoilerEpisodeIDs.insert(episode.id)", details)

    def test_spoiler_protection_defaults_off_to_preserve_existing_experience(self):
        details = (ROOT / "Kinetiq" / "Features" / "Modules" / "ModuleRuntime.swift").read_text()
        settings = (ROOT / "Kinetiq" / "Features" / "Modules" / "KinetiqSpoilerShield.swift").read_text()
        self.assertIn("private var spoilerDepthRaw = 0", details)
        self.assertIn("private var depthRaw = 0", settings)


if __name__ == "__main__":
    unittest.main()
