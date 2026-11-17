# Kinetiq — repository and batch reconciliation (16 November 2026)

This is a **source audit**, not a claim that GitHub Actions compiled or the
physical iPhone accepted any new change. The iOS baseline is
`Haimiya612/Kinetiq-iOS@b5e832ca0d8d1f6720f06f89df07b6108c81f358`.
The Batch 06O season queue edits accompanying this report are local changes
*after* that commit and have not been pushed to GitHub.

## What was inspected

| Repository | Purpose | Finding |
| --- | --- | --- |
| [Kinetiq-iOS](https://github.com/Haimiya612/Kinetiq-iOS) | Native iOS | Four-tab SwiftUI shell, local and module players, module library, per-episode MP4/HLS offline store, metadata enrichment and Discord integration in source. The old README and Phase 10 checkboxes described an earlier state. |
| [Kinetiq-Modules](https://github.com/Haimiya612/Kinetiq-Modules) | Unified module catalogue | Eight upstream catalogues combined in metadata. The checked-in snapshot contains 152 entries; only 43 are video ZIP candidates (3 local + 40 upstream). `npm test`: 5 passed; `npm run check`: passed. Neither proves device playback. |
| [Kinetiq](https://github.com/Haimiya612/Kinetiq) | Kotlin/Quest/Android project | A distinct planned platform with its own roadmap. Do not mark iOS functionality complete from Kotlin code or delete its roadmap as a duplicate. |
| [VRPQuest](https://github.com/Haimiya612/VRPQuest) | Upstream Kotlin fork | Not a Kinetiq-iOS implementation or a completed batch. Do not merge its code into iOS to satisfy an iOS checkbox. |

The iOS `docs/ROADMAP.md` contains 12 phases plus a historically dated
eight-repository research section. Its old 05I–05O candidate statuses and
provisional 0.4.0 wording do not describe the current state of `main`.
`Kinetiq-Modules` labels its eight-repository catalogue work **Batch 07A**;
that is *not* the iOS roadmap's Phase 7 manga reader. Keep those namespaces
separate in future planning.

## Duplicate and overlapping work to stop reimplementing

| Original descriptions/batches | Action | Acceptance still needed |
| --- | --- | --- |
| Phase 1 four tabs and Phase 3 Home/Library navigation | **Implemented once; both checkboxes reconciled** | Future media-library *data unification* belongs to 06P, not another tab redesign |
| Phase 2 and Phase 6 audio/subtitle/quality, PiP and player retry | Keep a single native player implementation and one reusable verification suite | Quality support differs by stream; offline and PiP subtitle combinations still need source/device checks |
| Phase 3 Favorites vs 03A–03D remote history/Favorites | Existing local/module favorites stores remain; no second favorites UI | Link matching titles cautiously under shared 06P media identity |
| Phase 4 discovery versus 05J/05K/06Q | Reuse existing source browsing, metadata, calendar and pagination work | Device test cross-source search, pagination, trailers, and ambiguous title matches |
| Phase 5 repository management versus 05L–05O/06S | Reuse module installation and update center; don't rebuild catalogue ingestion | Signed provenance, verified rollback, trust policy, module isolation, live compatibility certification |
| Phase 10 downloads versus 06K/06N/06O | Keep current `KinetiqOfflineDownloadStore`; extend it for seasons | Airplane Mode, HLS/media selections, background recovery, storage pressure |
| Phase 11 themes versus earlier overhaul batches | Keep settings-owned theme preferences and existing Home/Player redesign work | Each full theme and system component needs iPhone layout/accessibility regression |
| `Kinetiq-Modules` 07A federation versus iOS Phase 7 | **Catalogue complete as a separate project; no duplicate 8-upstream merge batch** | Actual manga/novel runtime/reader and adapters still missing |

Historical batch numbers document deliveries, not acceptance of every task in
their named phase. No unchecked manga/music/cloud/task is being marked done
simply because metadata or a placeholder is visible.

## Verified in source vs unresolved

**Verified from source and local tests:**

- `MainTabView.swift` defines Home, Favorites, Downloads and Settings.
- `HomeView.swift` contains the module picker, Video/Manga selection, and
  a local-library entry point. Manga remains placeholder UI.
- `KinetiqOfflineDownloads.swift` has background MP4 sessions, HLS asset
  sessions, persistent download entries, queue/pause/resume/remove, size
  records, offline file checks, and individual episode/source IDs.
- `KinetiqOfflineViews.swift` presents per-episode quality/track options and
  the new season queue-preparation workflow.
- The `Kinetiq-Modules` checks described above pass in Node 24.
- `Kinetiq-iOS`'s six Python roadmap-merger tests pass locally.

**Not proven:**

- iOS Swift compilation in this Linux environment (no Xcode/Swift toolchain).
- Current unsigned IPA quality, code-signing, PiP, subtitles, local library
  matching, batch download completion, or real offline playback on iPhone.
- Source-specific failures: user reports Synthetiq Flux broken, MegaKino
  fixed; current live URLs and modules must be retested before changing that.
- Compatibility of any module just because its ZIP is listed and hashed.

## Next unique work packages

1. **06O — Offline acceptance:** Test one MP4 and one HLS on iPhone in
   Airplane Mode; test restart, cancellation, resume, subtitle selection,
   quality, storage and the new season queue. Record source/episode IDs and
   failures without publishing protected stream URLs.
2. **06P — Unified media identity:** Introduce linked provider references
   while preserving module ID, local file ID, language and episode progress.
   Ask for user confirmation when two titles are ambiguous.
3. **06Q — Discovery verification:** Test calendar all-source navigation,
   automatic browsing, trailer handling, and actual metadata coverage.
4. **06R — Source-safe player recovery:** Retry/fail over only when series,
   season, episode, language and playback position are proven to match.
5. **06S — Package/runtime certification:** Publisher trust and signatures,
   safe updates/rollback and per-module live iOS test matrix.
6. **Phase 7/8:** Reader and dedicated music engine after 06O/06P are sound.

## Kinetiq offline package and compression proposal

The desired experience is a small offline copy that reopens normally at
720p/1080p with subtitles. **A ZIP cannot create a dramatically smaller but
bit-for-bit identical copy of an already compressed video** in general.
Quality and storage must be treated as a measured tradeoff.

Recommended architecture:

1. Prefer a provider's genuinely available lower-bitrate HLS rendition.
   The current app's Storage Saver setting already selects advertised
   variants; fixed-bitrate MP4s do not become smaller just by choosing it.
2. For authorized files that permit re-encoding, experiment with native
   HEVC/H.265 conversion using `AVAssetReader`/`AVAssetWriter` or supported
   export presets. Benchmark sample clips on a *physical iPhone* for
   artifacts, subtitles, battery, temperature, encoding time and file size.
   A 1080p dimension may stay 1080p even with fewer encoded bits, but exact
   image quality cannot be guaranteed.
3. Store a **Kinetiq offline manifest** for title/source/episode metadata,
   actual codec, duration, resolution, bytes, captions and integrity. Keep
   the playable native MP4 or Apple HLS `.movpkg` as files; AVPlayer should
   receive a normal file/asset URL. A ZIP is suitable for optional import or
   export, not direct random-access playback or HLS segment delivery.
4. Avoid simultaneous originals and converted duplicates without capacity
   checks; use atomic replacement only after the new file plays and passes
   checksum/metadata validation. Preserve original playback progress.
5. Never bypass DRM, export keys, or media-provider restrictions. Compress
   only media the user is authorized to keep and process.

Illustrative bitrate math (not a predicted result): for a 24-minute episode,
5 Mbps of video data is about 900 MB; 1.5 Mbps is about 270 MB before audio,
subtitles and container overhead. A 70% *bitrate* reduction is not a 70%
*quality-preserving* guarantee. Some anime scenes retain attractive quality
at substantially lower bitrates; others show visible artifacts.

## Device acceptance for season downloads

- [ ] A source with explicitly labelled Season 1 exposes **Download Season 1**.
- [ ] A flat source list shows **All Listed Episodes**, with no invented S1.
- [ ] Sub/Dub availability is checked per episode and never auto-switched.
- [ ] Queueing an existing episode does not produce a duplicate entry.
- [ ] Resolve and queue failures identify the episode, while other episodes
  can continue preparing.
- [ ] The 60-episode ceiling is enforced; dismissing/stopping only prevents
  further queue preparation and does not cancel already queued downloads.
- [ ] Background transfers persist across app restart, but unfinished batch
  *resolution* is not falsely claimed to resume itself.
- [ ] Real MP4 and HLS downloads work offline, including applicable subtitles,
  correct resolution, and cleanup after deletion.

References: [Apple AVFoundation offline HLS](https://developer.apple.com/documentation/avfoundation/using-avfoundation-to-play-and-persist-http-live-streams),
[Apple background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background),
[Apple media export](https://developer.apple.com/documentation/avfoundation/avassetexportsession),
and the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
