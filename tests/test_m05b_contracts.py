"""M05B static contract checks. Device behavior and Swift compilation need Xcode."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class M05BContracts(unittest.TestCase):
    def test_signature_preserved_and_new_chromes_distinct(self):
        swift = source("Kinetiq/Features/Modules/KinetiqUnifiedPlayer.swift")
        for style in ("signature", "cinema", "focus", "studio", "minimal", "classic"):
            self.assertIn(f"case {style} =", swift)
            self.assertIn(f"private var {style}Chrome: some View", swift)
        self.assertIn("if chromeStyle == .signature", swift)
        self.assertIn("signatureChrome", swift)

    def test_track_color_and_spacing_are_persistent(self):
        swift = source("Kinetiq/Features/Modules/KinetiqSubStudio.swift")
        self.assertIn('"kinetiq.substudio.m05b.lineGap"', swift)
        for slot in ("secondaryInk", "tertiaryInk", "romajiInk"):
            self.assertIn(f'"kinetiq.substudio.m05b.{slot}"', swift)
        self.assertIn("Restore subtitle layout defaults", swift)
        self.assertIn("Primary subtitle color", swift)

    def test_similar_anime_pages_and_dedupes(self):
        swift = source("Kinetiq/Features/Home/HomeView.swift")
        self.assertIn("private func loadNextPage() async", swift)
        self.assertIn("search(genreIntent, page: page)", swift)
        self.assertIn("Set(suggestions.map(\\.id))", swift)
        self.assertNotIn("suggestions = Array(picks.titles.filter { $0.id != selected.id }.prefix(18))", swift)

    def test_brain_library_opt_in_and_qualified_research(self):
        swift = source("Kinetiq/Features/Discovery/KinetiqBrain.swift")
        for value in ("thread-library.json", "Start a new conversation", "Rename conversation",
                      "Delete all saved Brain conversations?", "completeFileProtection",
                      "https://en.wikipedia.org/w/api.php", "https://api.themoviedb.org/3/search/",
                      "KinetiqTMDBCredentials.token()", "AniList public metadata"):
            self.assertIn(value, swift)

    def test_rpc_browsing_opt_in_and_playback_priority(self):
        swift = source("Kinetiq/Features/Integrations/KinetiqDiscordPresence.swift")
        self.assertIn('"kinetiq.discordPresenceLab.browsingM05B"', swift)
        self.assertIn("guard enabled, browsingEnabled, lastPreview == nil", swift)
        self.assertIn("func publishSceneIfNeeded", swift)
        self.assertIn("if browsingEnabled {", swift)
        self.assertIn("func playbackEnded()", swift)
        player = source("Kinetiq/Features/Modules/ModulePlayerView.swift")
        self.assertIn("presenceIntentRevision", player)


if __name__ == "__main__":
    unittest.main()
