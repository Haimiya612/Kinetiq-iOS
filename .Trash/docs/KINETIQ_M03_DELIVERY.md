# Kinetiq M03 — Player Pro / Episode Navigator + screenshot-driven fixes

**Development package:** 17 November 2026. **Application version:** still `0.3.0`. **Swift:** 5 mode. **Minimum iOS:** 17.0. **Delivery:** one cumulative full-source ZIP using the latest uploaded `Kinetiq-iOS-main 4.zip`. GitHub was not modified.

## Three requested fixes

1. **Wrong anime opens / provider identity mismatches.** `KinetiqSourceTitleSafety` compares selected and source-returned series titles during `extractDetails`. Clearly conflicting titles block automatic episode loading and show a diagnostic with a manual alternate-title override. That is conservative for legitimate Japanese/English aliases. Provider search rows no longer silently deduplicate reused IDs, and the affected SwiftUI grids assign distinct per-row identities. A new manual “Wrong anime or episode playing?” control pauses playback and records a local server-health failure, without changing module names, hiding sources, or switching to an arbitrary episode. **A CDN can still return an incorrect video while advertising the expected title; reliable video-content identification is not possible from every remote HLS stream.** The user-report path is the fallback until individual source bugs are diagnosed.
2. **Two “Repository Installation Finished” banners.** The app now owns a single normal `KinetiqNoticeBannerHost`, rather than also drawing copies in Modules/Settings/Update Center. Batch install group keys are stable per repository, allowing the existing 15-second coalescing policy to work; pending/current duplicate content is updated in place. One RGB theme decision banner remains separate by design.
3. **Keyboard Search key does not dismiss.** Global All Sources search, source-specific search, module-browser search, Compass, and Brain submission explicitly resign focus; standard button submissions also dismiss. Search itself still runs normally; local-file-only search does not start a network request.

## New M03 Player Pro capabilities

- Touch-control lock; one visible **Unlock Player** button remains tappable to prevent accidental lockout.
- User-configurable double-tap seek (5/10/15/30/60s) with invalid-setting fallback.
- Press and hold the video for temporary 2× playback; release restores the previous speed. Optional toggle in More; unavailable while paused, locked, or in a panel.
- Optional remaining-time clock on the timeline.
- Player Episodes/Queue lists search by episode number or descriptive title and filter all/sub/dub while preserving provider ordering.
- Private manual segment markers: Opening, Recap, Ending/Credits. Mark a start and end per source/series/episode, skip to an explicitly saved end, undo the seek, delete markers, persist after restart. No automatic detection or cross-edition timing assumptions.
- “Wrong anime or episode playing?” manual local reliability report, with pause and confirm-before-changing server health.
- Preserves prior M01/M02 power controls: exact timecodes, Quick Deck 48 actions, bookmarks, A/B repeat, seek undo, PiP, subtitles, server health, offline episode/season downloads and Quality Forge sample workflow.

## Verification

- `swiftc -frontend -parse` succeeds across active Swift sources and XCTest files on a Linux Swift 6.2 parser (syntax only, **not** iOS type checking).
- Local repository Python checks: **20 passed**, including 6 M03-specific wiring checks.
- A standalone Foundation-only Swift executable ran the actual normalized title identity matching functions with 4 representative cases: all passed.
- `plutil -lint` on `project.pbxproj`: OK.
- Original active source files retained; original Discord integration source and `Kinetiq.xcodeproj/project.pbxproj` unchanged (verified by SHA-256 when packaging).
- ZIP file integrity, byte-for-byte extraction, manifest and SHA-256 verification: documented in the delivery manifest.
- **No macOS Xcode compile, no GitHub Actions run, no signed/unsigned IPA and no iPhone regression were performed here.** Native UI and XCTest pass remain required.

## Scope accounting — M03 mega-batch, 70 references

The feature ledger assigns **R001–R032** and **B001–B038** to M03. They remain permanently retained in the included research blueprints. This is **not a claim that all 70 reference entries are implemented**. This delivery adds a focused subset and tightens already-coded navigation/repeat/seek controls. Still pending or conditional: frame-exact reverse step, true decoded scrub thumbnails, calibrated smart-speed heuristics, native embedded chapters, provider-supported intro/credits auto-detection, arbitrary franchise watch orders and other catalogued abilities. Unsupported capabilities must never be presented as working toggles.

## Preservation and import

- All four tabs: Home, Favorites, Downloads, Settings.
- Original Discord RPC transport, settings, account token storage, artwork and status handling are untouched.
- Original source identity and no-hidden-results search; local media versus streaming-module histories remain separate.
- App version `0.3.0`, iOS 17 minimum and Swift 5 project mode unchanged.
- No changes pushed to GitHub.

On iPhone, extract the ZIP and copy **the contents** of `Kinetiq-iOS-main/` into the root of your existing GitSync checkout; preserve `.git` and do not nest an extra project directory. Commit/push, check the Actions run, and use `M03_IPHONE_ACCEPTANCE.md`. If CI fails, fix the first compiler error before attempting functional acceptance tests.
