"""M03 source-contract checks. These do not replace native Xcode/XCTest."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_one_application_notice_banner_owner():
    files = list((ROOT / "Kinetiq").rglob("*.swift"))
    owners = [str(file.relative_to(ROOT)) for file in files
              if "KinetiqNoticeBannerHost()" in file.read_text(encoding="utf-8")]
    assert owners == ["Kinetiq/App/KinetiqApp.swift"]


def test_repository_batch_notification_group_key_is_stable():
    text = source("Kinetiq/Features/Modules/ModuleSourcesView.swift")
    assert 'groupKey: "batch.install.\\(repo.id)"' in text
    assert 'groupKey: "batch.install.\\(repo.id).\\(UUID().uuidString)"' not in text


def test_source_title_guard_blocks_before_episode_extraction():
    runtime = source("Kinetiq/Features/Modules/ModuleRuntime.swift")
    guarded = runtime.index("KinetiqSourceTitleSafety.needsConfirmation(")
    next_extract = runtime.index('handler: "extractEpisodes"', guarded)
    assert guarded < next_extract
    assert "acceptedAlternateSourceTitle = true" in runtime


def test_provider_results_are_not_silently_deduplicated():
    runtime = source("Kinetiq/Features/Modules/ModuleRuntime.swift")
    assert "let unique = originalItems.filter" not in runtime
    assert "ForEach(Array(items.enumerated()), id: \\.offset)" in runtime
    home = source("Kinetiq/Features/Home/HomeView.swift")
    assert "ForEach(Array(matches.enumerated()), id: \\.offset)" in home


def test_keyboard_search_paths_explicitly_resign_focus():
    home = source("Kinetiq/Features/Home/HomeView.swift")
    browser = source("Kinetiq/Features/Modules/ModuleRuntime.swift")
    compass = source("Kinetiq/Features/Discovery/KinetiqSmartDiscovery.swift")
    assert "textFieldFocused = false" in home
    assert "searchFocused = false" in home
    assert "searchIsFocused = false" in browser
    assert "queryFieldFocused = false" in compass
    assert "resignFirstResponder" in home and "resignFirstResponder" in browser


def test_m03_is_reversible_and_source_scoped():
    text = source("Kinetiq/Features/Modules/ModulePlayerView.swift")
    assert "KinetiqManualChapterStore" in text
    assert "mediaKey == mediaKey && $0.episodeKey == episodeKey" in text
    assert "Undo Seek returns" in text
    assert "Unlock Player" in text
    assert "Wrong anime or episode playing?" in text
