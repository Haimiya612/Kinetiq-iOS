# Kinetiq M02 — Offline Control / Travel Vault / Quality Forge + UI Repairs

**Development package:** 17 November 2026.  **Application version:** still `0.3.0`.  **Swift:** 5.0.  **Deployment:** iOS 17.0.

This is a cumulative full-source project based on the owner's latest `Kinetiq-iOS-main 3.zip` upload; it includes the earlier work and the additions described below. The GitHub repository was not modified.

## Three screenshot-driven repairs

1. **Discord activity repeats “Episode 1”.** Some source episode titles contain multiple identifiers (`Episode 1: S1E1: Episode 1: ...`). `KinetiqEpisodeMetadataMatching.displayTitle` now removes matching repeated prefixes while keeping the descriptive episode title. **The unofficial Discord Gateway method, credentials, poster selection, status transport, and Discord integration files were not changed.** This is a shared metadata-presentation repair with regression tests.
2. **Compass keyboard remains open.** Search field now uses SwiftUI focus state, clears focus on either keyboard Search or the visible Search button, and permits interactive scroll dismissal.
3. **Two checkmarks on My List.** The checked `Label` already has a checkmark symbol. The redundant `✓` in its text was removed. Favoriting logic and storage were not changed.

## M02 additions (source-coded, native tests pending)

- **Season download scope:** Full eligible list (existing limit 60) or the next 1/3/5 *missing* episodes. The selection excludes already queued/ready episodes and preserves the module's episode IDs and Sub/Dub distinction. This prepares a bounded batch now, not a permanent auto-download subscription.
- **Season status:** Shows how many episodes in the selected language are already saved, queued/transferring, or failed. The progress denominator is frozen at queue-preparation start rather than changing as episodes are enqueued.
- **Queue prioritization:** Waiting jobs can be moved earlier/later; order persists inside the original `downloads.json` index and is used by `startNextQueued`. Already-running background tasks are not reordered.
- **Per-title storage caps:** Off, 1, 2, 5, 10 or 20 GB; keyed by a SHA-256 digest of source and anime identity. The cap blocks *new* downloads if recorded ready bytes already exceed it. It cannot accurately predict unknown future sizes.
- **Start policies:** Optional charging-only and night-only (22:00–07:00 local) gates for *newly queued* tasks. These are rechecked when the app becomes active or charging status changes. Existing iOS background transfers may continue; **iOS does not promise to wake the app at 22:00**. There is an explicit Re-evaluate button.
- **Download screen:** Shows ready, queued and actively transferring counts; queued order controls are accessible.
- **Size estimate:** Uses source-provided episode duration and advertised HLS peak bitrate when both are known. Displays a rough peak-rate calculation, or “Size unknown”—never a fictitious exact size. MP4 with unknown bitrate remains unknown.
- **Travel Vault:** Opt-in native playback checks for up to 60 ready episodes per run. MP4 checks decode a real local video frame; HLS checks AVFoundation local asset playability and is **not** labeled verified full-playback. Cancel supported, outcomes shown per episode. Airplane Mode, after-restart, audio and subtitle playback still need user testing.
- **Quality Forge:** New 30-second HEVC sample encode for eligible imported videos. Review the original and sample playback before a full re-encode. Input and original remain untouched. Sample file size is explicitly not compared directly against full-source bytes or represented as a trustworthy final-file prediction.
- **Regression tests:** Added queue order, series budget isolation, bitrate estimate, and repeated episode-label cases in existing XCTest files.

## Preserved exactly

- Four tabs: Home / Favorites / Downloads / Settings.
- Original module identities and all-source search without hiding duplicated titles.
- Current native player, PiP, external subtitle bridge, local/library separation, player styles and existing theme selections.
- Discord RPC code and credential storage. No new account token mechanism was introduced.
- Xcode `project.pbxproj`; no new Swift source files requiring project registration.
- Version `0.3.0` and existing iOS 17 / Swift 5 project settings.

## M02 feature-ledger coverage (41 reference IDs)

The M02 mega-batch owns **research R123–R138 and blueprint B162–B186**, total 41 original references. This delivery **does not claim all 41 are finished**. Already coded foundations include MP4/HLS episode/season queues, background downloads, subtitle sidecars, portable manifest, native HEVC conversion and basic budget/quality controls. This delivery strengthens scheduling decisions, user queue order, series selection/budgets, on-device compatibility probes and 30-second compression comparison. Remaining M02 items include a persistent rolling keep-N auto-download subscription with source refresh, automatic corrupt-file repair after restart, truly scheduled/background-aware future work, full HLS audio track validation, exact size estimates, authorized server-assisted transcoding, full original-vs-converted A/B visual diff, and iOS Live Activities. Such features are **still planned or conditional**, never silently omitted.

## Validation performed in this environment

- Swift source and test files: `swiftc -frontend -parse` completed for all active Swift files (syntax only; not an iOS typecheck).
- Xcode project structure: `plutil -lint Kinetiq.xcodeproj/project.pbxproj`: OK.
- Local repository Python checks: **14 passed**.
- Standalone Swift/Foundation execution confirmed that repeated Discord episode prefixes render as one clean title.
- ZIP file list and CRC/integrity must be verified during final packaging; see archive manifest/checksum.
- **No Xcode, macOS simulator, GitHub Actions or iPhone acceptance run performed here.** The next GitHub Actions run is required to confirm actual Swift typechecking and XCTest.

## Import in GitSync on iPhone

1. Back up the current checkout (GitSync can also revert to a known commit).
2. Extract `Kinetiq-M02-Cumulative-0.3.0.zip`. Inside is one `Kinetiq-iOS-main/` root.
3. Replace/move the **contents of that root** into the root of the existing GitSync checkout. Do not nest a second project folder. Preserve the checkout's `.git` folder and commit history.
4. Confirm `Kinetiq.xcodeproj/project.pbxproj` exists at checkout root, along with `Kinetiq/`, `KinetiqTests/`, `docs/`, `scripts/` and `.github/`.
5. Commit/push using GitSync, inspect the next `Kinetiq iOS CI` workflow. If it fails, share the first compiler/test error; we will fix the actual cause before adding more changes.

The uploaded project contained a `.Trash/` directory of duplicate/obsolete copies and generated `__pycache__` files. These are **intentionally not packed** into the new source ZIP. No active project files were discarded.
