# Kinetiq All-in-One Experience — integration handoff (2026-11-16)

This folder is designed to be applied as **one complete repository update**.
It retains the pre-existing 06O season-download work and 06P1 cross-source
search/favorites work, plus their corrections, and adds a small set of cohesive
features across Home, Favorites, Downloads, Settings, Core, and tests.

## What is included

| Experience | Entry point | What it actually does |
| --- | --- | --- |
| Fast all-source search | Home → Search | Existing rolling, four-worker search across all installed **trusted** video sources. It preserves each returned item, even if names, IDs or posters match. This update adds imported local files to the **All sources** scope and names failed modules with a retry action. |
| Source switching | Favorites → source-change icon | Retains 06P1's all-module or one-module selection. Playback is launched from the chosen result; source-specific watch history remains untouched. |
| Source Passport | Favorites → source-change icon → Source Passport | Suggests exact-title saved copies and similarly named imported media. Adds an identity connection **only** when the user confirms it. Offers exhaustive all-source lookup without collapsing duplicate results. It does not infer equivalent seasons/episodes or automatically migrate watch progress. |
| Kinetiq Compass | Home → Search → sparkles, or Settings → Anime Discovery | Searches public AniList anime metadata with title/genre/completion/episode-count rules, then opens a full module search for the selected real title. No generative model or paid AI API. |
| Private unwatched inventory | Compass → My imported library | Lists videos in the app's imported `Documents/KinetiqMedia` folder, checks saved local progress, remembers 97%-complete playback and manual watched markers, and can open a local video. **No scanning of other apps, Photos, or arbitrary iCloud folders.** |
| Saved-for-later radar | Compass → Saved for later | Lists source favorites with no *recorded* playback start and opens full-source title searches. This is an estimate; it cannot claim to know everything watched outside Kinetiq. |
| Travel Vault | Downloads → airplane | Checks each saved episode/season part for a present, nonempty local payload and saved external subtitles, groups them by show/source, and reports problems before travel. Airplane Mode iPhone playback must still be tested. |
| Season and episode downloads | Downloads | Preserves already-integrated 06O capabilities, quality controls, existing file/manifest verification, and native playback paths. |
| Discord Presence Lab | Settings → Discord | The existing experimental unofficial-token implementation, credential storage, activity formats, poster previews, and sync behavior are **unchanged**. No tokens are copied into Compass or telemetry. |

## Privacy, search completeness, and integrity

- No all-source result is hidden or merged because of name, media type, same ID,
  suspected duplication, or connection. The module runtime can return errors,
  be uninstalled/untrusted, or omit results; these are not evidence a title
  does not exist. Failed module names are shown after a search.
- All-source searches only execute installed, trusted modules. Untrusted modules
  are never silently executed; enabling one remains an explicit user action.
- Compass makes an optional HTTPS request to `https://graphql.anilist.co`
  with the **textual public discovery query only**. It does not send file
  names, saved favorites, watch progress, source credentials, or Discord data.
- Media connections are navigation metadata, not a rewrite of provider IDs,
  playback queues, or watched state. No automatic cross-edition progress sync.
- Imported local files are sandbox-scoped; iOS does not permit an app to
  indiscriminately inspect a device's other private app folders.
- A nonempty, existing download is not necessarily decodable after reboot.
  A device-level Airplane Mode test is still required.

## Build and verification

Target: Swift 5, iOS 17+, `Kinetiq.xcodeproj`, `Kinetiq` scheme, existing
ZIPFoundation package. New files are explicitly added to `project.pbxproj`.

### Run on GitHub Actions / Xcode

1. In Working Copy, replace/merge files **preserving their directories**, 
   including `Kinetiq.xcodeproj/project.pbxproj`. Commit the complete update
   together; do not selectively install the `.swift` files without the project.
2. Run the existing Kinetiq GitHub Actions iOS build, tests, and IPA workflow.
3. Confirm `KinetiqCompassContractTests` and the existing discovery/download
   tests pass. Inspect the **first actual compiler error** if CI fails.
4. On your iPhone, exercise these acceptance cases:

   - [ ] Search a known title across all sources and verify every returned
     edition remains individually listed (including duplicate names).
   - [ ] Repeat with one source, then test a failed source and its Retry control.
   - [ ] Import a video, search it with All sources, open it from Compass,
     manually mark watched/unwatched, and restart the app to verify persistence.
   - [ ] Search `completed romance under 12 episodes` in Compass. Public
     metadata results should appear; tapping one should search every module.
   - [ ] Favorite a title, open Source Passport, connect/unlink a genuine match,
     change source, and verify original source playback history remains intact.
   - [ ] Download an episode, open Travel Vault, check subtitle status; test
     actual playback in Airplane Mode, after an app restart.
   - [ ] Test season download selections and the 06O `bytes` CI fix.
   - [ ] Test player, PiP, subtitles, navigation and the existing experimental
     Discord Presence Lab without altering the stored token.

### Boundaries / not yet implemented

This handoff is **not** a verified Xcode build or a completed replacement for
every long-term roadmap item. The development environment used to prepare it
does not contain Apple's Xcode/iOS SDK, so Swift compilation and device
testing must run in Actions and on the phone. These are future design ideas,
not completed features in this ZIP:

- An actual on-device/cloud generative language model with follow-up dialogue.
- Automatic personalized cross-media recommendations from watch-time embeddings.
- Automatic title/season/episode equivalence and cross-module resume migration.
- Remote cross-device progress sync and multi-user social/watch-party servers.
- Transcoding/compression claiming the same perceived quality at a fixed
  dramatically smaller size. ZIP archives do not meaningfully shrink video
  that is already encoded with H.264/HEVC/AV1. Real savings require optional
  re-encoding with quality/bitrate tradeoffs, battery/CPU estimates and
  appropriate content rights.
- A guarantee that every external video source always responds or plays.

## Relevant API documentation

- AniList media queries: https://docs.anilist.co/guide/graphql/queries/media
- AniList rate limits: https://docs.anilist.co/guide/rate-limiting

