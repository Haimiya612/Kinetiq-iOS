#!/usr/bin/env python3
"""Non-destructively merge the 2026 eight-repository findings into docs/ROADMAP.md.

Run from the root of Kinetiq-iOS. Idempotent, no external dependencies.
By default saves a backup on local writes. --no-backup is intended for CI.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

BEGIN = "<!-- KINETIQ_8_REPO_ROADMAP_2026_11_08_BEGIN -->"
END = "<!-- KINETIQ_8_REPO_ROADMAP_2026_11_08_END -->"
STATUS_BEGIN = "<!-- KINETIQ_8_REPO_STATUS_BEGIN -->"
STATUS_END = "<!-- KINETIQ_8_REPO_STATUS_END -->"
REF_BEGIN = "<!-- KINETIQ_8_REPO_REFERENCES_BEGIN -->"
REF_END = "<!-- KINETIQ_8_REPO_REFERENCES_END -->"

CURRENT_FOCUS = (
    "**Current focus:** Module reliability, source discovery and secure imports "
    "(Batch 05I physical-device baseline; unmerged 05J discovery/fixture "
    "candidate; 05K–05O hardening). Earlier Phase 2 and 11 verification "
    "requirements remain open."
)

STATUS = """**Research status (8 November 2026):** The eight-repository audit informed
new Batch 05I–05O engineering gates across existing Phases 5 and 6, with
Phase 7 reserved for manga. The checked-in app at
`4a74bbe73ac59d0e85b6bdaadd3e0faadb32be6b` supports much of the V3/V4
video runtime, but **does not yet have the separately prepared 0.4.0 discovery
candidate merged**. `Kinetiq-Modules` supplies 43 extracted current modules and
38 matching backup folders. Do not treat submitted ZIP files, static Swift parsing,
source-site resolution or anecdotal AniWorld success as a full CI/device pass.
See **Eight-Repository Integration Programme** below for the new detailed plan.
"""

REFERENCES = """## Eight-repository evidence snapshot (8 November 2026)

- [Synthetiq production Player modules](https://github.com/kas021/Synthetiq-Modules)
- [Synthetiq TEST Player modules and cryptographic regressions](https://github.com/kas021/Module-Testing-PL)
- [Synthetiq Manga Sources](https://github.com/Synthetiq-HQ/synthetiq-manga-sources)
- [AROKI declarative connectors](https://github.com/kas021/AROKI-Connectors)
- [AROKI testing connectors](https://github.com/kas021/Testing-Modules-AR)
- [AnyGo source adapters](https://github.com/kas021/AnyGo-Sources)
- [FRAnime testing modules](https://github.com/kas021/Testing-Modules-1-2-3-4)
- [Kinetiq-Modules extracted Synthetiq Player archive](https://github.com/Haimiya612/Kinetiq-Modules)

Research snapshot only: module versions, releases, trust and provider availability
can change. The integration programme above gives scope and acceptance tests.
"""

PHASES = (
    "# Phase 1 -- Foundation & Application Architecture",
    "# Phase 2 -- Playback & Player Experience",
    "# Phase 3 -- Advanced Media Library",
    "# Phase 4 -- Discovery & Content Catalogue",
    "# Phase 5 -- Kinetiq Module Engine",
    "# Phase 6 -- Streaming Engine",
    "# Phase 7 -- Manga & Image Reader",
    "# Phase 8 -- Music Experience",
    "# Phase 9 -- Personal Media Servers & Living Room Experience",
    "# Phase 10 -- Offline, Downloads & Synchronization",
    "# Phase 11 -- Personalization & Advanced Settings",
    "# Phase 12 -- Release, Testing & Optimization",
)


def tagged(content: str, begin: str, end: str) -> str:
    return begin + "\n\n" + content.strip() + "\n\n" + end


def insert_or_replace(text: str, *, begin: str, end: str,
                      section: str, anchor: str, before: bool = True) -> str:
    wrapped = tagged(section, begin, end)
    if begin in text or end in text:
        if text.count(begin) != 1 or text.count(end) != 1:
            raise ValueError("Malformed/duplicated roadmap update markers")
        pattern = re.escape(begin) + r"[\s\S]*?" + re.escape(end)
        return re.sub(pattern, lambda _: wrapped, text, count=1)
    if text.count(anchor) != 1:
        raise ValueError(f"Expected unique roadmap insertion anchor: {anchor!r}")
    if before:
        return text.replace(anchor, wrapped + "\n\n" + anchor, 1)
    return text.replace(anchor, anchor + "\n\n" + wrapped + "\n", 1)


def update(original: str, extension: str) -> str:
    if not all(x in original for x in PHASES):
        raise ValueError("This does not resemble the Kinetiq 12-phase master roadmap")
    if "# Reference Research" not in original or "# Current Development Status" not in original:
        raise ValueError("Current Development Status / Reference Research anchor missing")

    # Keep the original phase checkboxes, their precise requirements and ordering.
    result = original
    result = re.sub(r"(?m)^\*\*Current focus:\*\*[^\n]*$", CURRENT_FOCUS, result, count=1)
    if "**Working baseline:**" in result:
        result = result.replace("**Working baseline:**", "**Earlier 03G baseline:**", 1)

    result = insert_or_replace(
        result, begin=STATUS_BEGIN, end=STATUS_END,
        section=STATUS, anchor="# Current Development Status\n", before=False,
    )
    result = insert_or_replace(
        result, begin=BEGIN, end=END, section=extension,
        anchor="# Reference Research\n", before=True,
    )
    result = insert_or_replace(
        result, begin=REF_BEGIN, end=REF_END, section=REFERENCES,
        anchor="## Kinetiq\n", before=True,
    )

    # Invariants: all phases, original checklist entries, baseline sections survive.
    if not all(sum(line == p for line in result.splitlines()) == 1 for p in PHASES):
        raise ValueError("Roadmap phase identity or count unexpectedly changed")
    if result.count("- [ ]") < original.count("- [ ]"):
        raise ValueError("An existing unfinished roadmap requirement was removed")
    if result.count("- [x]") < original.count("- [x]"):
        raise ValueError("An existing completed roadmap item was removed")
    if "# Phase 7 -- Manga & Image Reader" not in result:
        raise ValueError("Phase 7 manga was lost")
    return result if result.endswith("\n") else result + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Kinetiq-iOS repository root")
    parser.add_argument("--output", type=Path, default=None, help="Alternative output file, leaving repo untouched")
    parser.add_argument("--no-backup", action="store_true", help="Do not create original-roadmap backup")
    parser.add_argument("--check", action="store_true", help="Validate and show statistics without writing")
    args = parser.parse_args()
    root = args.root.resolve()
    roadmap = root / "docs/ROADMAP.md"
    addition = root / "docs/ROADMAP_8_REPOSITORY_2026-11-08.md"
    if not roadmap.is_file() or not addition.is_file():
        parser.error("Both docs/ROADMAP.md and docs/ROADMAP_8_REPOSITORY_2026-11-08.md are required")
    original = roadmap.read_text(encoding="utf-8")
    extension = addition.read_text(encoding="utf-8")
    updated = update(original, extension)
    digest = hashlib.sha256(updated.encode("utf-8")).hexdigest()
    print(f"Original: {len(original.splitlines())} lines; revised: {len(updated.splitlines())} lines")
    print(f"Original checkboxes: {original.count('- [ ]')} open, {original.count('- [x]')} done")
    print(f"Updated SHA-256: {digest}")
    if args.check:
        return 0
    output = args.output.resolve() if args.output else roadmap
    output.parent.mkdir(parents=True, exist_ok=True)
    if output == roadmap and original != updated and not args.no_backup:
        backup = root / "docs/ROADMAP.before-8repo-update.md"
        if not backup.exists():
            backup.write_text(original, encoding="utf-8")
            print(f"Saved pre-update snapshot: {backup}")
    if output.is_file() and output.read_text(encoding="utf-8") == updated:
        print("Already up to date; nothing written")
        return 0
    output.write_text(updated, encoding="utf-8")
    print(f"Wrote: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
