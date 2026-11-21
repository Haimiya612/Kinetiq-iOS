"""Corrective M05B-R2 code contracts; the Swift build must still run on CI."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def swift(path):
    return (ROOT / path).read_text(encoding="utf-8")


class M05BR2Contracts(unittest.TestCase):
    def test_redesigned_header_uses_portrait_safe_inset(self):
        code = swift("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        self.assertIn("redesignedChrome(isPortrait: geometry.size.height > geometry.size.width)", code)
        self.assertIn(".padding(.top, max(safeAreaInsets.top, 62))", code)
        self.assertIn("if chromeStyle == .signature", code)

    def test_color_controls_exactly_name_three_tracks_plus_optional_romaji(self):
        code = swift("Kinetiq/Features/Modules/KinetiqSubStudio.swift")
        for text in ("Track 1 · Primary subtitle", "Track 2 · Secondary subtitle",
                     "Track 3 · Tertiary subtitle", "Optional fourth line"):
            self.assertIn(text, code)
        self.assertIn("if showRomaji {", code)

    def test_web_search_uses_real_provider_and_keychain(self):
        code = swift("Kinetiq/Features/Discovery/KinetiqBrain.swift")
        self.assertIn("https://api.search.brave.com/res/v1/web/search", code)
        self.assertIn("X-Subscription-Token", code)
        self.assertIn("kSecClassGenericPassword", code)
        self.assertIn('("web search ", .web)', code)
        self.assertIn('("wikipedia ", .wikipedia)', code)
        self.assertIn("let aliases: [String]", code)

    def test_rpc_pauses_when_buffering_and_browsing_retired(self):
        player = swift("Kinetiq/Features/Modules/ModulePlayerView.swift")
        rpc = swift("Kinetiq/Features/Integrations/KinetiqDiscordPresence.swift")
        self.assertIn("if wantsToPlay {", player)
        self.assertNotIn("if wantsToPlay && waitingOrPlaying", player)
        self.assertIn("browsingEnabled = false", rpc)
        self.assertIn("now.addingTimeInterval(12)", rpc)


if __name__ == "__main__":
    unittest.main()
