"""Dependency-free self-test for the Kinetiq roadmap merge script."""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("roadmap_merge", ROOT / "scripts/update_roadmap_8_repos.py")
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)


class RoadmapMergerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stub = "\n\n".join([
            "# Kinetiq -- Development Roadmap",
            "\n".join(merge.PHASES),
            "# Current Development Status\n\n**Current focus:** Original work.\n\n"
            "**Working baseline:** previous commit.\n\n- [ ] Keep original unfinished task.\n"
            "- [x] Keep original finished task.",
            "# Reference Research\n\n## Synthetiq Player\n\nsource\n\n"
            "## Kinetiq\n\nsource\n\n---\n",
        ]) + "\n"
        cls.extension = (ROOT / "docs/ROADMAP_8_REPOSITORY_2026-11-08.md").read_text()

    def test_preserves_original_12_phase_headings_and_checkboxes(self):
        result = merge.update(self.stub, self.extension)
        for phase in merge.PHASES:
            self.assertEqual(sum(line == phase for line in result.splitlines()), 1)
        self.assertIn("- [ ] Keep original unfinished task.", result)
        self.assertIn("- [x] Keep original finished task.", result)

    def test_idempotent(self):
        result = merge.update(self.stub, self.extension)
        self.assertEqual(result, merge.update(result, self.extension))

    def test_separates_streaming_and_manga(self):
        result = merge.update(self.stub, self.extension)
        self.assertIn("# Phase 6 -- Streaming Engine", result)
        self.assertIn("# Phase 7 -- Manga & Image Reader", result)
        self.assertIn("07A -- Loose-file source importer", result)

    def test_new_reference_section_and_status_exactly_once(self):
        result = merge.update(self.stub, self.extension)
        self.assertEqual(result.count(merge.REF_BEGIN), 1)
        self.assertEqual(result.count(merge.REF_END), 1)
        self.assertEqual(result.count(merge.STATUS_BEGIN), 1)
        self.assertEqual(result.count(merge.STATUS_END), 1)
        self.assertEqual(result.count(merge.BEGIN), 1)
        self.assertEqual(result.count(merge.END), 1)

    def test_refuses_unknown_roadmap(self):
        with self.assertRaises(ValueError):
            merge.update("# unrelated", self.extension)

    def test_bad_markers_fail_closed(self):
        with self.assertRaises(ValueError):
            merge.update(self.stub.replace("# Reference Research", merge.BEGIN + "\n# Reference Research"), self.extension)


if __name__ == "__main__":
    unittest.main()
