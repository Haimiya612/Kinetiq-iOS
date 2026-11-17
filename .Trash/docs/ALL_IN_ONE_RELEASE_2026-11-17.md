# Kinetiq All-in-One Power Center — 17 November 2026

## What this ZIP is

This is a complete source-tree replacement based exclusively on the user's
`Kinetiq-iOS-main.zip`, with the original Xcode project, assets, tests and
documentation preserved. It is **not** an IPA. The research files are retained
under `docs/research/` for every proposal not yet implemented.

The four original tabs remain Home, Favorites, Downloads and Settings. There is
no replacement navigation root or second player engine. Source identities,
module runtime, subtitle bridge and automatic PiP are preserved. In particular,
the current Discord RPC transport and settings implementation are untouched.

## Implemented in this integration

| Area | Working scope | Entry point |
| --- | --- | --- |
| Kinetiq Brain | Private grounded natural-language inventory guide and live AniList catalog search; **opt-in multi-turn Apple Intelligence chat** on eligible iOS 26+ devices only, never passed a dump of watch history or filenames. Explicit catalog searches retain real-source attribution | Home toolbar; Module Player → More → Brain; Settings → Anime Discovery |
| Cross-source Scene Passport | Saves private source/episode/language/running-time anchors every ~7 seconds while playable. Offers explicit user-initiated seek across *confirmed* Source Passport links only if language, episode number and duration match | Module Player → More → Scene Passport |
| Scene bookmarks | Save a timestamp with optional note; jump among same-episode, same-language bookmarks; browse/delete stored bookmarks | Module Player → More; Settings → Playback → Scene Memory |
| Module Player Power Deck | Configurable ±5/10/15/30/60-second jump, undo previous seek, exact hh:mm:ss jump, Study/Cinema speed presets, native-caption temporary rewind, A/B loop, bookmark navigation, linked-source resume, shareable spoiler-safe timecode and direct Brain entry | Module Player → More |
| Player Action Finder | Searchable action sheet with 35 real commands for transport, skip, rates, A/B loops, rewind captions, retry, sleep, bookmarks, Binge Guard, Brain and study. Unavailable commands are disabled | Module Player → More → Find a player action |
| Binge Guard | Persistent autoplay on/off preference plus session-only pause-after-current/2/3 episodes; completion-driven counting, no false counts for server retries or seeks | Module Player → More → Binge Guard |
| Recovery Center | Private bounded error history for real source resolution and AVPlayer failures, automatic retries, manual retries and fallback choices. Safe error codes and status only; share sanitized report or clear history | Module Player → More → Recovery Center; Settings → Playback |
| Japanese Study Deck | Manually authored phrase/translation/context flashcards, safe episode/timecode links, deterministic offline spaced review, CSV export with formula-injection defense | Module Player → More → Study Deck; Settings → Playback |
| Quality Forge | Non-destructive AVFoundation HEVC conversion of locally imported, authorized video; battery, disk, temperature and duration checks; preview and export converted MOV | Settings → Power Center → Quality Forge |
| Sync Vault | Manual cross-device transport via JSON in Files/AirDrop, opt-in export, import preview and merge. Transfers favorites, per-episode progress, confirmed links, scene timestamps, bookmarks and optional theme; deliberately excludes credentials, URLs and media | Settings → Power Center → Sync Vault |
| Viewing Insights | Device-only progress, favorites per source, integrity-checked offline counts, usage and scene-record statistics | Settings → Power Center → Viewing Insights |
| Library Doctor | On-demand read-only import audit: total storage, unwatched items, largest videos, SHA-256 verified duplicate groups, bounded full-file hash scans and count-only share report | Settings → Power Center → Library Doctor |
| Travel Vault manifest | Export a portable JSON report of ready/failed saved episodes, per-episode language, quality, recorded byte size and subtitle count. Optional title/source-name redaction; no stream URL, token, cookie or local filesystem path | Downloads → Travel Vault → Portable offline manifest |
| Watch Plans | Create local watch appointments with title, episode, start time and note; share an invitation through iOS or display a scannable QR code. Plans can be included in Sync Vault transfers. This does not claim live group playback | Settings → Power Center → Watch Plans |
| Regression tests | Cross-source matching, mismatched cuts/language, private archive encoding, rejected invalid Scene Passports | `KinetiqTests/KinetiqPowerCenterContractTests.swift` |

## Important boundaries — these are NOT implemented yet

- **Universal AI access:** On supported Apple Intelligence devices, the opt-in
  on-device system language model is used for conversational prompts; other
  devices retain the grounded local and AniList search features. This model
  has no verified access to source playback or the internet; its prose is not
  mislabeled as live metadata. No hosted model is configured.
- **Real-time watch rooms:** Shareable timecode invitations are implemented,
  but not synchronized playback, presence, reactions or chat. Those require a
  lawful media-access model plus an approved SharePlay route or backend.
- **Automatic cloud/device sync:** Manual user-controlled transfer works; no
  server-backed automatic synchronization, encryption layer or account system
  is falsely claimed. JSON backups are readable and should be shared privately.
- **Perfect cross-source handoff:** Verified-metadata seek is implemented;
  differences in video cuts or subtitle offsets require additional indexing
  and human confirmation. No unverified fuzzy matching.
- **Lossless extreme compression:** HEVC re-encoding can reduce storage on
  some inputs but is lossy and may be larger. A ZIP wrapper cannot dramatically
  shrink an already compressed MP4 without loss. The original is never deleted.
- **48/200+ player and catalog proposals:** The research blueprints contain a
  comprehensive target catalog (including clip editing, translation, dialogue
  enhancement, intro markers, richer AI search, accessibility, room controls,
  codec support, and native manga). They are **preserved** as planning records,
  not represented as already-shipped controls.

## Testing and shipping gates

Available here: six existing Python roadmap-merger tests plus five new
source-wiring checks pass; new Swift
contract tests have been added to the `KinetiqTests` Xcode target. A full iOS
build and physical-device checks are **not possible on the Linux construction
host**; the archive should not be called CI-pass before GitHub Actions runs.

After importing the ZIP in GitSync and committing, run the existing Xcode test
and unsigned IPA workflows; verify specifically:

1. Home/Favorites/Downloads/Settings, theme switches and launch/navigation.
2. Current Discord status/presence before and during module playback.
3. Module server selection, native HLS/MP4 seek, PiP and subtitles.
4. More → Power Deck; configurable seek, undo seek, exact timecode, A/B repeat,
   bookmark notes/jumps, stop/restart; no loop leaking across episodes.
5. Confirm two equivalent Source Passport entries; play same language/episode
   from both; ensure unlinked, dubbed and mismatched-length versions do not jump.
6. Local Brain queries, imported-vs-downloaded storage totals and AniList results; Airplane Mode should leave local
   answers functional while online catalog requests fail gracefully. On an
   eligible iOS 26 Apple Intelligence device, opt into conversation, ask two
   follow-ups, reset context and confirm no private inventory is sent. On an
   unsupported device, the toggle must be disabled with an explanation.
7. Quality Forge on an owned HEVC-compatible file; check resulting audio,
   captions, size and duration; cancellation must retain original.
8. Export a Sync Vault file, import on a second install, review preview/merge;
   check that module credentials and Discord RPC stay on the device.
9. Offline downloads and season queue, Airplane Mode, restart, subtitle sidecars
   and storage integrity in the existing Travel Vault. Export both named and
   redacted manifests; inspect the JSON for absence of private paths and links.
10. In More → Action Finder, search for seek, repeat, subtitles, retry and Brain.
    Verify buttons operate on the actual player; disabled commands cannot run.
11. Turn off autoplay and finish an episode; confirm no next episode starts.
    Then set Pause after 2 and verify exactly one advance and one stop.
12. Force an actual playback failure and observe one sanitized Recovery Center
    entry. Check privacy, event deduplication, report sharing, and clearing.
13. Make a Study Deck card at a playing scene, review Again/Good/Easy, restart
    the app, verify persistence and episode-safe jump, and export valid CSV.

## Integration map

New source files registered in `Kinetiq.xcodeproj/project.pbxproj`:

- `Kinetiq/Core/Media/KinetiqContinuity.swift`
- `Kinetiq/Core/Media/KinetiqSyncVault.swift`
- `Kinetiq/Features/Discovery/KinetiqBrain.swift`
- `Kinetiq/Features/Discovery/KinetiqNativeBrain.swift`
- `Kinetiq/Features/Library/KinetiqLibraryDoctor.swift`
- `Kinetiq/Features/Discovery/KinetiqViewingInsights.swift`
- `Kinetiq/Features/Downloads/KinetiqQualityForge.swift`
- `Kinetiq/Features/Social/KinetiqWatchPlans.swift`
- `KinetiqTests/KinetiqPowerCenterContractTests.swift`
- `Kinetiq/Features/Modules/KinetiqRecoveryCenter.swift`
- `Kinetiq/Features/Discovery/KinetiqStudyDeck.swift`
- `KinetiqTests/KinetiqRecoveryStudyContractsTests.swift`

Existing files edited: `MainTabView.swift` (safe per-episode sync merge),
`HomeView.swift` (Brain shortcut),
`ModulePlayerView.swift` (new contextual controls and continuity saves),
`SettingsView.swift` (navigation), `project.pbxproj`, and roadmap documentation.
The existing unified player helper file that was deliberately excluded from
the target remains excluded; including it would redeclare player types.

## Research preservation

`docs/research/KINETIQ_JACKPOT_RESEARCH_MASTERPLAN_2026-11-16.md` preserves
the original long-form product and 200+ control inventory, and
`docs/research/Kinetiq_2026_Master_Feature_Blueprint.pdf` preserves the
26-page competitor, wish-list, architecture and accessibility research.
Proposals not coded remain explicitly in scope for future implementation.
