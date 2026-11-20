"""Offline contract tests for the GitHub ZIP importer (no GitHub auth needed)."""

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = PROJECT_ROOT / ".github/workflows/import-kinetiq-zip.yml"


def import_python_code():
    contents = WORKFLOW.read_text(encoding="utf-8")
    script = contents.split("python3 - <<'PY'\n", 1)[1]
    script = script.split("\n          PY", 1)[0]
    return textwrap.dedent(script)


def complete_files():
    result = {
        "Kinetiq.xcodeproj/project.pbxproj": "// !$*UTF8*$!\nPBXProject\n",
        "Kinetiq/App/KinetiqApp.swift": "import SwiftUI\n",
        "Kinetiq/Features/Modules/ModulePlayerView.swift": "import SwiftUI\n",
        "docs/ROADMAP.md": "# Roadmap\n",
        "KinetiqTests/SmokeTests.swift": "import XCTest\n",
        "README.md": "# Replaced source\n",
        ".github/workflows/evil.yml": "# ignored, should never be installed\n",
    }
    for index in range(25):
        result[f"Kinetiq/Core/ImportFixture{index}.swift"] = "import Foundation\n"
    return result


class ZIPImporterContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        (self.repo / ".github/workflows").mkdir(parents=True)
        (self.repo / ".github/workflows/existing.yml").write_text("keep me")
        (self.repo / "Kinetiq").mkdir()
        (self.repo / "Kinetiq/OldFeature.swift").write_text("old")
        self.files = complete_files()

    def archive(self, entries=None):
        with zipfile.ZipFile(self.repo / "Kinetiq-update.zip", "w", zipfile.ZIP_DEFLATED) as output:
            for name, contents in (entries or self.files).items():
                output.writestr("Kinetiq-iOS-main/" + name, contents)

    def execute(self):
        environ = dict(os.environ, GITHUB_WORKSPACE=str(self.repo),
                       KINETIQ_ZIP_PATH="Kinetiq-update.zip")
        return subprocess.run([sys.executable, "-c", import_python_code()],
                              cwd=self.repo, env=environ, capture_output=True, text=True)

    def test_full_import_removes_stale_swift_and_preserves_workflows(self):
        self.archive()
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertFalse((self.repo / "Kinetiq/OldFeature.swift").exists())
        self.assertTrue((self.repo / "Kinetiq/Core/ImportFixture24.swift").exists())
        self.assertEqual((self.repo / ".github/workflows/existing.yml").read_text(), "keep me")
        self.assertFalse((self.repo / ".github/workflows/evil.yml").exists())
        self.assertFalse((self.repo / "Kinetiq-update.zip").exists())

    def test_rejects_incomplete_zip_without_touching_existing_source(self):
        self.archive({"Kinetiq/App/KinetiqApp.swift": "import SwiftUI\n"})
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing", result.stderr + result.stdout)
        self.assertTrue((self.repo / "Kinetiq/OldFeature.swift").exists())

    def test_rejects_parent_directory_traversal(self):
        self.files["../../outside.txt"] = "unsafe"
        self.archive()
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsafe", result.stderr + result.stdout)
        self.assertTrue((self.repo / "Kinetiq/OldFeature.swift").exists())

    def test_rejects_duplicate_case_insensitive_paths(self):
        self.files["kinetiq/core/importfixture0.SWIFT"] = "duplicate"
        self.archive()
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate", result.stderr + result.stdout)
        self.assertTrue((self.repo / "Kinetiq/OldFeature.swift").exists())


if __name__ == "__main__":
    unittest.main()
