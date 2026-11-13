# Kinetiq -- Development Roadmap

Kinetiq is an independent, native iOS media platform designed to bring video,
anime, manga, images, music, and personal media sources into one unified
experience.

The product direction is simple:

**Build the media experience people want, without limiting Kinetiq to the
capabilities of another player.**

Kinetiq is heavily inspired by Synthetiq Player, particularly its unified
media experience, extensible content ecosystem, and approach to bringing
different media types together.

Synthetiq Player is an important product reference. Its public documentation,
store listings, and module contract are useful sources of product and
architecture requirements. Kinetiq will implement its own native systems,
visual identity, architecture, and security model.

Kinetiq is not intended to be a rebranded copy of another application.
The goal is to build upon the ideas that make modern media platforms useful
and create an even more capable, flexible, and polished experience.

---

# Product Principles

1. **Native first:** Prioritize native iOS technologies and APIs.
2. **Performance:** Avoid unnecessary overhead and prioritize smooth operation.
3. **Privacy:** Keep personal media and user data under the user's control.
4. **Local first:** Local media management must remain useful without an account.
5. **Modularity:** Build systems that can be extended without rewriting the application.
6. **Reliability:** Preserve existing functionality when introducing new features.
7. **Recoverability:** Provide clear errors and recovery paths instead of silent failures.
8. **Security:** Verify external content and packages wherever supported.
9. **Consistency:** Maintain a unified design language across all media experiences.
10. **Independent identity:** Kinetiq has its own implementation and visual identity.
11. **No fake functionality:** Controls must perform their advertised actions.
12. **Testability:** Every major feature must have a testing strategy before being considered complete.

Kinetiq will not copy proprietary source code, assets, or private
implementations from other applications.

---

# Phase 1 -- Foundation & Application Architecture

**Goal:** Establish a reliable foundation for the entire application.

## Application

- [x] Create the native iOS application using SwiftUI.
- [x] Establish the main application structure.
- [x] Implement primary tab navigation.
- [x] Establish the initial Kinetiq design language.
- [x] Create the Kinetiq app icon and visual identity.
- [x] Implement appearance selection.
- [x] Implement persistent appearance preferences.
- [x] Implement launch tagline selection.
- [x] Implement the What's New system.
- [x] Show What's New only when unseen release notes exist.
- [x] Pin the What's New continuation action to the bottom of its presentation.

## Development Infrastructure

- [ ] Refine the primary navigation around four destinations: Home, Favorites, Downloads, and Settings.
- [ ] Merge the local Library experience into Home instead of dedicating a bottom-navigation destination to it.
- [ ] Add a source/module picker at the top of Home, below the Dynamic Island and safe-area region.
- [ ] Add a Video/Manga mode switch directly below the source picker.
- [ ] Keep the navigation architecture extensible for a future fifth destination.

- [x] Configure the GitHub repository.
- [x] Configure GitHub Actions.
- [x] Configure simulator testing.
- [x] Configure unsigned iOS builds.
- [x] Configure unsigned IPA packaging.
- [x] Configure CI artifact uploads.
- [ ] Establish a consistent project-wide logging system.
- [ ] Establish a shared error-reporting architecture.
- [ ] Improve project-wide code organization.
- [ ] Expand automated test coverage.
- [ ] Audit accessibility across all screens.
- [ ] Establish reusable loading, empty, and error states.

**Status:** Foundation established. Architectural cleanup remains ongoing.

---

# Phase 2 -- Playback & Player Experience

**Goal:** Build a reliable, polished native media player before expanding
into remote content and additional media categories.

## Core Playback

- [x] Integrate AVPlayer.
- [x] Implement local video playback.
- [x] Build a full-screen player interface.
- [x] Implement playback controls.
- [x] Implement playback speed selection.
- [x] Implement aspect-ratio controls.
- [x] Implement audio track selection.
- [x] Implement embedded subtitle selection.
- [x] Implement a sleep timer.
- [x] Import videos through Files.
- [x] Import videos through Photos.
- [x] Keep imported video files in the application's local media directory.

## Playback Memory

- [x] Implement persistent playback history.
- [x] Remember the last playback position.
- [x] Automatically resume from saved positions.
- [x] Add Continue Watching to Home.
- [x] Display playback progress indicators.
- [x] Detect completed media.
- [x] Automatically remove completed entries from Continue Watching.
- [x] Preserve playback history after app restarts.
- [x] Limit stored playback history to a bounded number of entries.
- [x] Validate restored history data.

## Queue Management

- [x] Implement persistent playback queues.
- [x] Implement Next and Previous.
- [x] Implement queue selection.
- [x] Implement queue removal.
- [x] Implement queue reordering.
- [x] Implement Play Next.
- [x] Implement Shuffle.
- [x] Implement Repeat Off.
- [x] Implement Repeat All.
- [x] Implement Repeat One.
- [x] Preserve the current queue item when reordering.
- [x] Persist queue state.
- [x] Add a queue panel to the player.
- [x] Handle unavailable queue files.

## Player Experience

- [ ] Generate and cache local video thumbnails for both Library and Home's Continue Watching cards.
- [ ] Persist generated thumbnail files so they survive app restarts and are not regenerated unnecessarily.
- [ ] Associate thumbnails with stable media identifiers and invalidate them when media changes or is removed.
- [ ] Prefer source/module-provided episode artwork for remote media when available.
- [ ] Generate a representative frame from a playable remote stream when source artwork is unavailable and the stream permits it.
- [ ] Provide a consistent artwork fallback for media without a usable thumbnail.
- [ ] Display technical video resolution.
- [ ] Display local file size.
- [ ] Display file format and duration.
- [ ] Implement Picture-in-Picture support.
- [ ] Integrate the native AirPlay route picker.
- [ ] Implement double-tap seeking.
- [ ] Display seek feedback.
- [ ] Implement a playback retry path that replaces failed AVPlayerItems.
- [ ] Provide a way to skip a failed queue item.
- [ ] Add external subtitle file support for SRT and WebVTT.
- [ ] Synchronize external subtitles with the active media item and playback timeline.
- [ ] Combine embedded and external subtitle tracks in one player selection interface.
- [ ] Detect media capabilities from the currently loaded item and its source/module.
- [ ] Show only playback options supported by the current media and source.
- [ ] Detect and expose selectable audio tracks, subtitle tracks, and alternate video tracks when available.
- [ ] Detect available HLS quality variants and provide Auto and manual quality selection when supported.
- [ ] Keep quality selection unavailable for fixed-quality local files and sources without selectable variants.
- [ ] Add automatic Picture-in-Picture activation when the user leaves the app during active playback.
- [ ] Configure the playback audio session and background playback requirements for reliable automatic PiP.
- [ ] Preserve playback and player state when transitioning from the full-screen player into PiP.
- [ ] Render selected external SRT and WebVTT subtitles inside the system PiP video presentation.
- [ ] Respect the player's subtitle setting in PiP: selected subtitles appear, while Off suppresses them.
- [ ] Ensure external subtitle rendering in PiP remains synchronized through seeking, pausing, resuming, and queue changes.
- [ ] Add subtitle appearance customization.
- [ ] Add chapter and timestamp navigation.
- [ ] Add configurable seek intervals.
- [ ] Add playback gesture preferences.
- [ ] Improve playback interruption handling.
- [ ] Add detailed playback diagnostics.
- [ ] Improve playback performance and stability.
- [ ] Test playback on physical devices.
- [ ] Test common containers and codecs.
- [ ] Test high-resolution and high-frame-rate media.
- [ ] Test long-duration playback and memory usage.
- [ ] Test AirPlay and Picture-in-Picture on physical hardware.

**Status:** Core local playback, playback memory, and queue management
are implemented. The advanced player experience remains in progress.

---

# Phase 3 -- Advanced Media Library

**Goal:** Turn the local library into a complete personal media management
system.

## Organization

- [ ] Merge the local Library into the Home experience while retaining a dedicated in-Home library destination/view.
- [ ] Implement the Home source/module picker.
- [ ] Implement the Video/Manga mode switch beneath the source picker.
- [ ] Implement media categories.
- [ ] Implement the Favorites destination and its saved-media collection.
- [ ] Implement favorites for local media and, later, module-provided media.
- [ ] Implement custom collections.
- [ ] Implement playlists for local video.
- [ ] Add sorting options.
- [ ] Add filtering options.
- [ ] Implement library search.
- [ ] Add recently added media.
- [ ] Add recently played media.
- [ ] Add media detail pages.
- [ ] Add bulk selection and actions.
- [ ] Add duplicate media detection.
- [ ] Support multiple import locations.
- [ ] Improve Files and Photos integration.

## Images and Photos

- [ ] Support importing still images from Files.
- [ ] Support importing still images from Photos.
- [ ] Create an image library.
- [ ] Generate image thumbnails.
- [ ] Implement a full-screen image viewer.
- [ ] Support zoom and image scaling.
- [ ] Support image metadata.
- [ ] Add image collections.
- [ ] Add image favorites.

## Storage

- [ ] Display local library storage usage.
- [ ] Add cache management.
- [ ] Add storage cleanup tools.
- [ ] Detect missing files.
- [ ] Detect inaccessible files.
- [ ] Add import progress.
- [ ] Improve large-file import reliability.
- [ ] Add safe cancellation for long-running imports.

---

# Phase 4 -- Discovery & Content Catalogue

**Goal:** Build a unified discovery experience for different types of media.

## Discovery

- [ ] Implement the Discover interface.
- [ ] Add featured content sections.
- [ ] Add trending content sections.
- [ ] Implement cross-category search.
- [ ] Create media detail pages.
- [ ] Support movies and television series.
- [ ] Support seasons and episodes.
- [ ] Implement watchlists.
- [ ] Add recently updated content.
- [ ] Integrate metadata providers.
- [ ] Implement recommendations.
- [ ] Connect discovery results to playback and reading.

## Catalogue Architecture

- [ ] Define a common media-item model.
- [ ] Define metadata-provider interfaces.
- [ ] Define artwork-provider interfaces.
- [ ] Implement metadata caching.
- [ ] Implement image caching.
- [ ] Handle missing metadata gracefully.
- [ ] Support multiple metadata providers.
- [ ] Avoid coupling catalogue data to a specific source module.

---

# Phase 5 -- Kinetiq Module Engine

**Goal:** Build a secure, extensible module ecosystem.

This phase must be researched and designed before implementation.
The Synthetiq public module documentation provides a useful reference for
module packaging, content types, runtime contracts, and source resolution.

Kinetiq should not become dependent on another application's private
implementation. The goal is to support a documented, independently
implemented adapter architecture.

## Repository Management

- [ ] Implement repository management.
- [ ] Support adding external repositories.
- [ ] Parse repository indexes.
- [ ] Parse repository manifests.
- [ ] Validate repository URLs.
- [ ] Build a module catalogue.
- [ ] Display module descriptions.
- [ ] Display module versions.
- [ ] Display module changelogs.
- [ ] Support default repositories.
- [ ] Support private repositories.
- [ ] Handle unavailable repositories.
- [ ] Cache repository metadata.

## Package Format

- [ ] Define the Kinetiq module package format.
- [ ] Define a versioned JSON manifest.
- [ ] Define package identity and version rules.
- [ ] Define module entry points.
- [ ] Define module dependencies.
- [ ] Define supported content types.
- [ ] Define package size limits.
- [ ] Define runtime resource limits.
- [ ] Define module compatibility rules.
- [ ] Publish a module creation guide.
- [ ] Publish example modules.
- [ ] Publish a module validation tool.

## Content Types

- [ ] Video modules.
- [ ] Image modules.
- [ ] Text and novel modules.
- [ ] Music modules.
- [ ] Live-stream modules.
- [ ] Define common content models.
- [ ] Define content-specific extraction interfaces.

## Runtime

- [ ] Research JavaScript runtime options.
- [ ] Define the host-to-module API.
- [ ] Define request and response models.
- [ ] Define networking permissions.
- [ ] Define timeout limits.
- [ ] Define response-size limits.
- [ ] Define concurrency limits.
- [ ] Define memory limits.
- [ ] Define cancellation behavior.
- [ ] Implement runtime isolation.
- [ ] Prevent modules from accessing unrelated application data.
- [ ] Implement runtime diagnostics.
- [ ] Implement module crash recovery.

## Source Resolution

- [ ] Define search handlers.
- [ ] Define detail handlers.
- [ ] Define episode handlers.
- [ ] Define stream-resolution handlers.
- [ ] Define chapter handlers.
- [ ] Define image extraction handlers.
- [ ] Define text extraction handlers.
- [ ] Define source-specific configuration.
- [ ] Define request-header handling.
- [ ] Define redirect handling.
- [ ] Define stream validation.
- [ ] Keep playback inside Kinetiq's native playback engine.

## Installation and Management

- [ ] Implement module installation.
- [ ] Implement module uninstallation.
- [ ] Implement module updates.
- [ ] Add version management.
- [ ] Implement compatibility checks.
- [ ] Handle dependencies.
- [ ] Display installation progress.
- [ ] Display update progress.
- [ ] Maintain installation history.
- [ ] Implement package rollback.

## Security

- [ ] Implement SHA-256 package verification.
- [ ] Implement signature verification where supported.
- [ ] Establish repository trust management.
- [ ] Define module permissions.
- [ ] Define module capabilities.
- [ ] Restrict file-system access.
- [ ] Restrict sensitive application APIs.
- [ ] Protect user credentials.
- [ ] Prevent credential exfiltration.
- [ ] Validate all module responses.
- [ ] Audit the runtime sandbox.
- [ ] Document security limitations.

## Synthetiq Compatibility Research

Public Synthetiq module documentation describes:

- A ZIP-based package.
- A JSON manifest.
- A JavaScript entry point.
- A versioned module contract.
- Video, image, and text content types.
- Search and detail extraction handlers.
- Episode and stream extraction for video.
- Chapter and image extraction for image content.
- Chapter and text extraction for text content.
- Runtime capability limits.
- A repository index that references downloadable packages.

Research tasks:

- [ ] Obtain and inspect the complete public technical contract.
- [ ] Identify the exact manifest requirements.
- [ ] Identify runtime behavior and supported JavaScript APIs.
- [ ] Identify networking behavior.
- [ ] Identify response and error conventions.
- [ ] Identify package validation rules.
- [ ] Build a compatibility matrix.
- [ ] Implement a compatibility adapter where technically possible.
- [ ] Test compatible modules individually.
- [ ] Document unsupported functionality.
- [ ] Avoid claiming compatibility until real runtime tests pass.

**Important:** A compatible manifest is not sufficient to establish runtime
compatibility. Search results, details, and episode extraction are not proof
that a resolved stream can actually play.

Compatibility with third-party modules depends on documented runtime
requirements, technical compatibility, signatures, and applicable
permissions. Kinetiq will not bypass security checks or redistribute
packages without authorization.

---

# Phase 6 -- Streaming Engine

**Goal:** Connect external content sources to Kinetiq's native playback engine.

## Stream Support

- [ ] Implement HTTP streaming.
- [ ] Support HLS.
- [ ] Support direct MP4 playback.
- [ ] Support supported remote media formats.
- [ ] Implement adaptive streaming quality.
- [ ] Add manual quality selection.
- [ ] Display available stream qualities.
- [ ] Support external subtitle sources.
- [ ] Support required request headers.
- [ ] Implement secure session handling.
- [ ] Implement stream validation.
- [ ] Add server selection.
- [ ] Implement playback failover.
- [ ] Improve network error recovery.
- [ ] Add caching where appropriate.
- [ ] Implement playback diagnostics.

## Playback Integration

- [ ] Connect module resolution to AVPlayer.
- [ ] Keep module networking separate from the player UI.
- [ ] Support stream metadata.
- [ ] Support audio-track metadata.
- [ ] Support subtitle metadata.
- [ ] Support episode navigation.
- [ ] Support source switching.
- [ ] Preserve playback history across source changes.
- [ ] Preserve queue behavior for remote streams.

**Architecture principle:** Modules resolve content. Kinetiq validates,
loads, and plays it.

---

# Phase 7 -- Manga & Image Reader

**Goal:** Introduce a complete reading experience.

## Library and Discovery

- [ ] Create a dedicated manga library.
- [ ] Integrate manga discovery.
- [ ] Implement manga detail pages.
- [ ] Support chapters.
- [ ] Display reading progress.
- [ ] Add favorites.
- [ ] Add reading lists.
- [ ] Add recently read content.

## Reader

- [ ] Build a dedicated image reader.
- [ ] Support vertical scrolling.
- [ ] Support horizontal page navigation.
- [ ] Implement right-to-left reading.
- [ ] Add zoom and image scaling.
- [ ] Implement page navigation.
- [ ] Remember reading position.
- [ ] Add bookmarks.
- [ ] Support offline reading.
- [ ] Add image preloading.
- [ ] Add reading preferences.
- [ ] Integrate compatible image modules.

## Text Reading

- [ ] Build a text and novel reader.
- [ ] Support chapter navigation.
- [ ] Remember reading position.
- [ ] Add typography preferences.
- [ ] Add themes.
- [ ] Add bookmarks.
- [ ] Add reading progress.

---

# Phase 8 -- Music Experience

**Goal:** Expand Kinetiq into a complete music platform.

- [ ] Build a music library.
- [ ] Support artists and albums.
- [ ] Retrieve music metadata.
- [ ] Generate album artwork.
- [ ] Implement playback queues.
- [ ] Support playlists.
- [ ] Add shuffle and repeat.
- [ ] Support background audio.
- [ ] Integrate iOS Now Playing.
- [ ] Support Lock Screen controls.
- [ ] Support audio output routing.
- [ ] Remember playback history.
- [ ] Integrate compatible music modules.

---

# Phase 9 -- Personal Media Servers & Living Room Experience

**Goal:** Allow users to access their personal media libraries remotely
and use Kinetiq across their Apple devices.

## Server Management

- [ ] Implement server management.
- [ ] Support server authentication.
- [ ] Browse remote media libraries.
- [ ] Support remote playback.
- [ ] Retrieve remote metadata.
- [ ] Display server connection status.
- [ ] Investigate supported discovery protocols.
- [ ] Securely store server credentials.
- [ ] Support standard media server protocols.
- [ ] Implement connection diagnostics.
- [ ] Handle unavailable servers.
- [ ] Support multiple server profiles.

## Apple TV

- [ ] Research a dedicated tvOS target.
- [ ] Design a remote-first interface.
- [ ] Implement a TV library.
- [ ] Implement TV playback.
- [ ] Implement favorites and history.
- [ ] Implement playback progress.
- [ ] Design secure device pairing.
- [ ] Implement device-to-device transfer.
- [ ] Support transferring favorites and playback progress.
- [ ] Test local network transfer.
- [ ] Test remote-control navigation.

---

# Phase 10 -- Offline, Downloads & Synchronization

**Goal:** Make media accessible across different network conditions
and devices.

## Downloads

- [ ] Add Downloads as a primary bottom-navigation destination.
- [ ] Implement a download manager.
- [ ] Support download queues.
- [ ] Display download progress.
- [ ] Support pausing downloads.
- [ ] Support resuming downloads.
- [ ] Support cancelling downloads.
- [ ] Resume interrupted downloads.
- [ ] Validate downloaded files.
- [ ] Display download sizes.
- [ ] Add storage management.
- [ ] Support offline playback.

## Synchronization

- [ ] Define a synchronization model.
- [ ] Synchronize playback history.
- [ ] Synchronize favorites.
- [ ] Synchronize library information.
- [ ] Investigate iCloud synchronization.
- [ ] Handle synchronization conflicts.
- [ ] Support multiple devices.
- [ ] Implement backup and restore.
- [ ] Define account requirements.
- [ ] Keep local-only mode available.
- [ ] Make cloud functionality optional.

---

# Phase 11 -- Personalization & Advanced Settings

**Goal:** Give users control over their Kinetiq experience.

- [ ] Add customizable Home sections.
- [ ] Implement theme selection.
- [ ] Add accent color customization.
- [ ] Add playback preferences.
- [ ] Add subtitle preferences.
- [ ] Add language preferences.
- [ ] Allow default quality selection.
- [ ] Allow default module selection.
- [ ] Add privacy settings.
- [ ] Add storage settings.
- [ ] Add diagnostic settings.
- [ ] Add cache preferences.
- [ ] Add accessibility preferences.
- [ ] Add configurable player gestures.
- [ ] Add configurable seek intervals.
- [ ] Add library layout preferences.

---

# Phase 12 -- Release, Testing & Optimization

**Goal:** Prepare Kinetiq for a stable and reliable release.

## Testing

- [ ] Expand unit tests.
- [ ] Add integration tests.
- [ ] Add UI tests.
- [ ] Test module installation.
- [ ] Test module updates.
- [ ] Test module compatibility.
- [ ] Test playback on physical devices.
- [ ] Test different media formats.
- [ ] Test network interruptions.
- [ ] Test offline functionality.
- [ ] Test synchronization.
- [ ] Test AirPlay.
- [ ] Test Picture-in-Picture.
- [ ] Test accessibility.
- [ ] Test long-duration playback.

## Optimization

- [ ] Improve startup performance.
- [ ] Optimize memory usage.
- [ ] Improve battery efficiency.
- [ ] Optimize image loading.
- [ ] Optimize video loading.
- [ ] Audit application security.
- [ ] Review accessibility.
- [ ] Improve error reporting.
- [ ] Profile scrolling performance.
- [ ] Profile playback performance.
- [ ] Test cache eviction.

## Release

- [ ] Establish release versioning.
- [ ] Finalize the update log system.
- [ ] Prepare release documentation.
- [ ] Establish release channels.
- [ ] Complete final quality assurance.
- [ ] Prepare store assets.
- [ ] Complete final privacy review.
- [ ] Complete final security review.

---

# Current Development Status


<!-- KINETIQ_8_REPO_STATUS_BEGIN -->

**Research status (8 November 2026):** The eight-repository audit informed
new Batch 05I–05O engineering gates across existing Phases 5 and 6, with
Phase 7 reserved for manga. The checked-in app at
`4a74bbe73ac59d0e85b6bdaadd3e0faadb32be6b` supports much of the V3/V4
video runtime, but **does not yet have the separately prepared 0.4.0 discovery
candidate merged**. `Kinetiq-Modules` supplies 43 extracted current modules and
38 matching backup folders. Do not treat submitted ZIP files, static Swift parsing,
source-site resolution or anecdotal AniWorld success as a full CI/device pass.
See **Eight-Repository Integration Programme** below for the new detailed plan.

<!-- KINETIQ_8_REPO_STATUS_END -->

**Current focus:** Module reliability, source discovery and secure imports (Batch 05I physical-device baseline; unmerged 05J discovery/fixture candidate; 05K–05O hardening). Earlier Phase 2 and 11 verification requirements remain open.

**Earlier 03G baseline:** `d065edd9f23347f9f37bbdbb6e9d185909a2ab5c` on `main`,
inspected on 7 November 2026. The implementation has advanced beyond the older
phase checklist. An unchecked task remains planned or awaiting its required
verification; source-code presence alone does not certify completion.

The inspected baseline contains source code for:

- Four bottom destinations: Home, Favorites, Downloads, and Settings.
- Local Library access within Home, the source picker, and Video/Manga mode controls.
- Existing local playback, queue, import, thumbnail, and subtitle systems.
- Batch 01: module compatibility adapters and a player using the local player's visual design.
- Batch 02: stream/server selection, diagnostics, and recovery paths.
- Batch 03A: source-specific anime Favorites and Recent Episodes.
- Batch 03B: global anime Favorites and remote Continue Watching.
- Batch 03C: anime discovery controls and shared artwork caching.
- Batch 03D: source-specific episode/language progress, watched state, and continuation controls.
- Batch 03E: optional module SRT/WebVTT metadata, selection and in-app rendering.
- Batch 03F: HLS quality preferences, 20 quality test cases and the restored 18
  subtitle test cases. All five repository files match the 03F delivery.

These observations describe source code, not a fresh build or device acceptance
result. Manga reading, downloads, cloud synchronization, metadata providers, and
all other unchecked requirements retain their places in the roadmap.

## Phase progression and verification gates

Batch numbers identify deliveries, not completed roadmap phases. Work follows the
phase dependencies below; overlapping foundations (such as Phase 6 streaming for
Phase 2 playback) can be developed together. Before starting each batch, inspect
the latest code and the earlier phases' unchecked tasks. Distinguish missing code
from implemented code that still needs verification, so features are not rebuilt
or silently skipped. Add discovered gaps to their owning phase and retain every
existing requirement.

| Phase | Next implementation or verification gate |
| --- | --- |
| 1 — Foundation | Verify the four-tab/source navigation, shared states and project configuration; track accessibility and architecture cleanup. |
| 2 — Playback | Finish and verify quality controls, subtitle preferences, automatic PiP, external PiP subtitles, interruptions and gestures. |
| 3 — Library | Audit existing Favorites/search/sorting first, then address remaining collections, playlists, bulk actions, images and storage tools. |
| 4 — Discovery | Verify anime discovery before expanding common catalogue models, movies/series, metadata and recommendations. |
| 5 — Modules | Test actual source contracts and playback; close compatibility, lifecycle, diagnostics, trust and additional-content-type gaps. |
| 6 — Streaming | Verify real HLS/MP4 playback, quality preferences, headers, subtitles, failover and history; distinguish server choices from quality choices. |
| 7 — Manga/Reader | Begin after the relevant image-module contract and discovery path are understood; deliver chapters, reader and reading progress incrementally. |
| 8 — Music | Build on verified audio/background playback and library foundations. |
| 9 — Servers/TV | Add protocol/authentication and remote-library foundations before device-transfer and tvOS expansion. |
| 10 — Downloads/Sync | Implement real queues/storage/offline playback before optional synchronization and conflict handling. |
| 11 — Personalization | Deliver preferences alongside the features they control; retain a later audit of all remaining settings. |
| 12 — Stabilization/Release | Test throughout development; defer full Actions debugging as requested, then require build/device/compatibility evidence before release. |

Batch 03F is on `main`. Batch 03G adds subtitle appearance and language preferences.
Batch 03H is planned for automatic PiP and background playback, subject to the
latest code audit. External subtitles inside system PiP require a separate
rendering investigation. Follow with a stabilization checkpoint and an audit of
remaining Phase 3–6 gaps before committing to a manga batch number. No later
phase or previously planned feature is removed by this sequence.

A phase is not complete merely because its replacement files were delivered.
Applicable exit evidence includes Swift compilation, executed regression tests,
real source/device acceptance and documented remaining limitations.

## Batch 03D -- Episode Progress and Continue Watching

**Implementation status:** Replacement source prepared; iOS validation pending.

Scope is based on two gaps in the inspected 03C baseline: remote history kept
only one episode/language position per title, and completed episodes could stay
in Continue Watching.

- Keep independent episode progress per source, anime, episode, and Sub/Dub language.
- Migrate the existing saved collection without resetting Favorites or its latest
  valid playback position. Earlier positions already overwritten by 03B cannot
  be reconstructed.
- Record watched state at the existing 97% completion threshold or a real end event.
- Offer per-language Mark Watched / Mark Unwatched actions in anime details.
- Show episode progress, watched counts, episode-number search, and watched filters.
- Resume an available unfinished episode, otherwise offer the first unwatched
  playable episode in the source's own order.
- Hide finished episodes from Continue Watching. Hiding a card or removing a
  Recent Episodes entry retains its underlying episode progress and artwork.
- Preserve same-language position during server recovery; use independent saved
  progress when changing Sub/Dub.
- Save progress on pause, completed seeking, leaving the active app, handoff, and close.

The existing collection remains bounded to 400 titles; episode history is bounded
to 8,000 records across retained titles, with older records pruned first. Watched
marks remain until explicitly reset or removed by those storage limits. Replaying
a watched episode does not silently mark it unwatched.

Validation required before closing the relevant roadmap tasks:

- [ ] Run the added migration, persistence, completion, and continuation XCTest cases.
- [ ] Compile and link the full app with the project's Xcode configuration.
- [ ] Exercise Sub/Dub switching, episode changes, server recovery, and app restarts on iPhone.
- [ ] Verify details layout, scrolling, accessibility, and the unchanged player controls on iPhone.
- [ ] Recheck real module search → details → episode → stream → playback.

Full GitHub Actions build debugging is temporarily deferred to stabilization.
Local Swift syntax parsing and source-consistency checks are recorded in
`docs/BATCH_03D.md`. They do not replace Swift type checking, simulator tests,
module compatibility tests, or physical-device playback verification.


## Batch 03E -- Module Subtitle Tracks

**Implementation status:** Replacement source prepared; compilation, XCTest, and
physical-device validation pending.

The 03D module player exposes embedded AVPlayer subtitle tracks, but its stream
model does not retain external subtitle descriptors. This batch adds optional
source subtitle metadata and in-app SRT/WebVTT rendering to the existing player.

- Decode supported `subtitles`, `tracks`, and `captions` metadata without changing
  the existing direct URL, flat label/URL, or alternative-server stream inputs.
- Display embedded and source subtitles in the existing Subtitles panel with Off,
  loading state, sanitized errors, and retry.
- Fetch only the chosen subtitle file; bound body size and cue count, restrict
  credential forwarding, cancel superseded requests, and keep subtitle URLs in memory.
- Follow AVPlayer time through seeking, pausing, rate changes, and episode/server
  transitions; clear the previous stream's cues before loading new ones.
- Retain an external language choice within the current player session when the
  new stream supplies a matching track. Off stays Off through stream transitions.
- Preserve the existing local subtitle implementation, player controls, four tabs,
  source identities, Favorites, and Batch 03D playback history.

External subtitle metadata is an optional Kinetiq extension: the retrieved public
Synthetiq guide does not define these fields. Availability depends on actual module
output. This batch does not manufacture subtitle URLs or modify source modules.
The in-app text overlay does not render in system PiP or remote AirPlay video.
Native PiP subtitle rendering, subtitle appearance customization, timing offsets,
ASS/SSA/TTML, and broader format support remain separate future work.

- [ ] Execute the new `ModuleRemoteSubtitleTests` cases in the existing test target.
- [ ] Validate HTTPS downloads, redirects, cancellation, and provider headers with real subtitle sources.
- [ ] Test selection, Off, backwards seeking, overlapping cues, episode transitions, and server recovery on iPhone.
- [ ] Confirm no regression to embedded subtitles, local subtitles, playback history, or existing player controls.

See `docs/BATCH_03E.md` for the optional metadata schema, verification limits, and
acceptance checklist. All earlier roadmap requirements remain in place.


## Batch 03F -- HLS Quality Preferences

**Owning phases:** Phase 2 (Playback) and Phase 6 (Streaming).
**Implementation status:** Replacement source prepared; Xcode, XCTest and device
validation pending. This does not close the manual-quality roadmap tasks.

- Discover the active AVURLAsset's native HLS variants asynchronously, without
  rewriting playlists or introducing a separate source-networking path.
- Add Auto and advertised resolution preferences to the existing Playback panel.
  Label manual choices “Up to …”; Apple treats these as preferences, not strict
  resolution locks. Show current presentation dimensions separately.
- Group equal resolutions, display known peak bitrates, and omit manual choices
  for empty/single-resolution ladders. Unknown peaks do not become invented caps.
- Apply preferences to the current player item without seeking or replacing it.
  Reset to Auto on episode/server changes; persistent defaults remain Phase 11.
- Bound metadata processing and detection UI wait time; ignore stale results after
  handoff/close and offer retry without treating metadata failure as playback failure.
- Restore the 18 missing 03E subtitle tests and add 20 quality regression cases.
  None have been executed in the current environment.

Discovered follow-up gaps are retained explicitly:

- [ ] Validate preferred versus observed HLS quality under low bandwidth and buffered playback on iPhone.
- [ ] Investigate exact variant locking without losing alternate audio, subtitles, live behavior or source credentials.
- [ ] Support useful quality choices for bitrate-only ladders without resolution metadata.
- [ ] Assess codec, HDR and frame-rate capability reporting without claiming every advertised variant is playable.
- [ ] Validate quality discovery cancellation, timeout, retry and stale-result handling with AVFoundation.
- [ ] Execute the restored 03E tests and the new 03F quality tests in the existing test target.

See `docs/BATCH_03F.md` for the implementation boundaries and acceptance steps.

## Batch 03G — Subtitle Preferences

Phases 2 and 11 share this batch. The source is prepared for Xcode and device verification.
Settings → Playback → Subtitles contains the saved language, text size, colour, background
and a preview. The local and module players use the saved language for available tracks.
The module player can also match captions supplied by a source. Its Sub/Dub audio stream
choice remains a separate control.

Automatic uses the system's embedded selection. Off disables optional tracks. An exact
language tag takes priority over a compatible primary language. Equal matches prefer
embedded captions. An in-player choice takes priority for the session, and “Use saved
subtitle default” resumes automatic matching.

Appearance applies to Kinetiq's source captions and native WebVTT text style rules.
Other native formats use the system renderer. See `docs/BATCH_03G.md` for acceptance steps.

- [ ] Run the preference XCTest cases and verify persistence after a full app relaunch.
- [ ] Test exact, regional and missing language matches, manual overrides and required native tracks on iPhone.
- [ ] Check source SRT/WebVTT and embedded WebVTT appearance, system accessibility settings, queue changes and server recovery.
- [ ] Connect the existing local SRT/WebVTT import and saved file-selection helpers to the local player's Subtitles panel.

---

<!-- KINETIQ_8_REPO_ROADMAP_2026_11_08_BEGIN -->

# Eight-Repository Integration Programme -- November 2026

**Research checkpoint:** 8 November 2026. **Scope:** Phases 2, 4, 5, 6, 7, 8, 10, 11 and 12.
**Kinetiq reference:** [`main` at `4a74bbe73ac59d0e85b6bdaadd3e0faadb32be6b`](https://github.com/Haimiya612/Kinetiq-iOS/tree/4a74bbe73ac59d0e85b6bdaadd3e0faadb32be6b).
**Principle:** The original twelve phases and all previous unchecked tasks remain in force. This section adds engineering detail and acceptance gates; it does not override or silently complete earlier work.

## Decision record and verification status

The audit compared eight GitHub repositories, repository manifests/indexes, selected full source files and relevant tests/docs. It was **not** an exhaustive line-by-line audit of every file, a cryptographic certification, a live-website availability guarantee or an iPhone playback pass. Do not label those activities complete until their evidence exists.

- **Preserve the working native video path.** Kinetiq already has JavaScriptCore, `fetchv2`, timed calls, cookies, redirects, stream-header parsing, native AVPlayer, quality preferences, subtitles and server-health history. **AniWorld has reportedly begun playing on the user's device**, which is encouraging anecdotal evidence, not a reproducible regression certificate. Never discard the player/runtime to implement another module format.
- **Correct the discovery contract.** Synthetiq One, Synthetiq Anime, Synthetiq Flux and AniWorld expose optional `discoveryHome()` and `discoveryFeed(feedId, page)`. Source-provided Home sections are distinct from `searchResults` and must not be fabricated from genre suggestions.
- **Separate distribution formats.** Player `repository.json` + ZIP + local `module.json`/`index.js`, Manga Sources `index.json` + loose manifests/entry scripts, AROKI declarative signed connector indexes and AnyGo source JSON are *different contracts*. No importer should guess one format from another.
- **Separate integrity from authenticity.** A valid package SHA-256 and manual user approval do not authenticate a publisher. Signed catalogs require known, independently pinned public keys and exact canonical-message verification; unsigned community catalogs must remain visibly separate.
- **Report the evidence level.** Distinguish `CONTRACT_PASS`, `FIXTURE_PASS`, `LIVE_NODE_PASS`, `IOS_RUNTIME_PASS`, `PARTIAL` and `FAIL`. Successful search, 200 HTTP, returned stream URL, playable segment and physical iPhone playback are **not interchangeable**.
- **Maintain independent Kinetiq identity and user data.** Preserve source-provided module names, IDs, stable source family identity, favorites, watched progress and local queue. Never silently reset user data, relabel a language or switch source/provider because a stream failed.

### Audit inventory (not a live provider-availability claim)

| Reference | Observed snapshot | Engineering application |
| --- | --- | --- |
| [kas021/Synthetiq-Modules](https://github.com/kas021/Synthetiq-Modules) | 38 advertised modules (31 video, 6 image, 1 music); signed production index | Production versions, ZIP package integrity, quality/release rules |
| [kas021/Module-Testing-PL](https://github.com/kas021/Module-Testing-PL) | 45 advertised (38 video, 6 image, 1 music); unsigned test index with mixed per-module signatures | ECDSA verification, release-revision binding, imports, fallback/artwork testing |
| [Synthetiq-HQ/synthetiq-manga-sources](https://github.com/Synthetiq-HQ/synthetiq-manga-sources) | 47 entries: 36 page-image, 4 text, 3 publication, 4 audio | Loose-file importer, reader contracts, `pagev2`, certification |
| [kas021/AROKI-Connectors](https://github.com/kas021/AROKI-Connectors) | 11 video connector index entries | Sandboxed declarative operation descriptors, immutable releases |
| [kas021/Testing-Modules-AR](https://github.com/kas021/Testing-Modules-AR) | 4 experimental connector index entries | AniWorld Home regression, Flux/Anime qualification |
| [kas021/AnyGo-Sources](https://github.com/kas021/AnyGo-Sources) | 1 Synthetiq One source | Small typed API resolver and episode artwork templates |
| [kas021/Testing-Modules-1-2-3-4](https://github.com/kas021/Testing-Modules-1-2-3-4) | 2 unsigned FRAnime test modules | Flat ZIP/bundle build rules, IDs, archive safety and redirect fixtures |
| [Haimiya612/Kinetiq-Modules](https://github.com/Haimiya612/Kinetiq-Modules) | 43 current module folders and 38 backup folders; 38 backup/current matches byte-identical | Exact V3/V4 JavaScript and manifest regression fixtures |

**Archive preservation:** Five current extracted module IDs not present in the production index snapshot are `ev01-v1`, `latanime-v1`, `stcine-v1`, `synthetiq-movies-v1` and `yastream-v1`. Retain them as historical fixtures, *not* as presumed current production offers. Extracted-vs-catalog version examples: Flux 1.0.3-beta.5 vs TEST beta.8; Shahiid 2.1.2 vs production 2.1.3-beta.3; AniPM beta.4 vs TEST beta.5; AniKoto beta.2 vs TEST beta.3. The extracted Flux manifest has conflicting `moduleVersion` beta.5 and `version` beta.4, which needs a validation warning. Do not mutate historical packages merely to make versions match.

## Release train: 05I–05O (Phases 5 and 6 with supporting Phases 2, 4, 11, 12)

**Priority:** P0 = correctness / regressions / device blocking; P1 = security and user-facing integration; P2 = lifecycle and quality. Batches are engineering deliveries, **not** phase-completion certificates. Batch labels refer to this integration train even when existing work is shared between batches.

### Batch 05I -- Physical-device video baseline (P0)

**Status: [ ] Device evidence pending.** AniWorld intermittently working is a valuable test case. Current source playback already handles a number of redirect, cookie and stream alternatives, but results are provider- and device-dependent.

- [ ] Record source ID, installed version, package hash, source type and attempted route (without logging signed URLs, headers, tokens or cookies).
- [ ] On iPhone, test Synthetiq One, Anime, Flux and AniWorld: search → details → episodes → stream resolution → AVPlayer ready → at least 30 seconds playback → seek → audio/subtitle/quality → resume.
- [ ] Test HLS master/variant/media playlist, key and segment request classes, including `Referer`, `Origin`, user agent, cookies and cross-host redirects.
- [ ] Confirm a previously working AniWorld episode still plays before and after the next patch; record one passing and one failing test case if available.
- [ ] Re-test cold start, 403, 429, empty response, timeout, alternate server and repeated retry; never consider returned HTTP 200 sufficient.
- [ ] Preserve the 05I log/result as a sanitized regression baseline, identifying `RESOLVED`, `MEDIA_BYTES_OK`, `AVPLAYER_READY`, `ADVANCING`, `SEEK_OK`, `AUDIO_OK`, `CAPTION_VISIBLE` separately.

**Exit:** Physical-device pass/fail report with exact installed module versions and an explicit header/redirect diagnosis; no unverified claim of full provider certification.

### Batch 05J -- Contract and regression fixture suite (P0)

**Status: [ ] Unmerged delivery candidate / Xcode execution pending.** A separate Kinetiq 0.4.0/05J ZIP was prepared on 8 Nov 2026 with discovery code and six proposed tests. This is not proven merged into `main` or compiled; do not check it off simply because a ZIP exists. The earlier research plan called discovery 05K; that functionality is now included in the combined 05J candidate, with 05K retained for integration hardening.

- [ ] Build sanitized, deterministic input/output fixtures from representative *authorized* extracted V3/V4 modules; preserve original identities and maintain a fixture provenance manifest with SHA, version and relevant handler.
- [ ] Test `searchResults`, `extractDetails`, `extractEpisodes`, `extractStreamUrl` and optional `discoveryHome` / `discoveryFeed` with true provider response shapes.
- [ ] Test source-specific `href`/ID behavior; nested `streams`, `servers`, `qualities`, HLS vs MP4 hints, per-variant headers, subtitles, empty/error objects, duplicates and malformed URLs.
- [ ] Test `fetchv2` methods, `followRedirects: false`, bounded `maxBytesHint`, binary response bytes, 3xx `Location`, case-insensitive headers, timers, 403/429/cold starts and oversized bodies.
- [ ] Test ZIP root layout (`module.json` and `index.js`), SHA-256, identity, version mismatches, incomplete manifests, caps, unsafe paths and unsupported contract revisions.
- [ ] Run test fixtures in GitHub Actions without depending on real provider uptime, then compare live behavior separately with 05I.

**Exit:** Green XCTest suite on a specified commit/Xcode version, with sanitized fixture sources and explicit known gaps. Parsing a Swift file is not an executed test.

### Batch 05K -- Real source Home and discovery hardening (P1)

**Status: [ ] Implementation candidate exists in 0.4.0 ZIP; merge, build and on-device validation pending.** Keep the already-prepared optional Home implementation, then verify the full app route.

- [ ] Call `discoveryHome()` only if exported; decode real `sections`, `id`, `title`, `style`, `items` and `viewAll` descriptors with bounds.
- [ ] Call `discoveryFeed(feedId, page)` from source-advertised links; support `hasMore` and safe pagination without guessed page counts.
- [ ] Support `href`/ID media identity, poster fallbacks, module-supplied FAST/cached flags and source-provided metadata without renaming or inventing rankings.
- [ ] Make discovery errors and absent optional handlers fall back to existing search/favorites/Continue Watching, not an empty or crashing Home.
- [ ] Add per-source stale-response cancellation, refresh, pagination deduplication and separate loading/error/empty states.
- [ ] Confirm AniWorld Home is not confused with a successful search; test Synthetiq One, Anime and Flux separately.

**Exit:** On-device Home → details → episodes → playback for at least one real catalog item per available test source, plus passing fixtures and no regression to local Home.

### Batch 05L -- Publisher identity, signing and provenance (P1, security gate)

**Status: [ ] Planned.** Current Kinetiq package hashing is **not** publisher verification.

- [ ] Create typed repository trust states: trusted verified publisher, community manually trusted, invalid signature, retired, revoked and incompatible.
- [ ] Verify production repository and package descriptors with independent trusted P-256 public-key pins; use CryptoKit SHA-256/ECDSA raw 64-byte (`r || s`) signatures and exact canonical newline-field order **only** for the appropriate schema.
- [ ] Verify signed revision (`publishedAtMs`), repository ID, package path, checksum, module ID/family/number and version; reject malformed Base64, duplicate identities and tampered revisions.
- [ ] Keep TEST public keys separate from production trust; do not promote the public example/test keys to production authority.
- [ ] Permit explicitly confirmed unsigned community sources where policy allows without silently downgrading a previously trusted signed installation.
- [ ] Keep separately signed native subtitle providers and artwork metadata separate from module trust; never infer that one signature authenticates another asset class.
- [ ] Show the publisher, source URL, installed SHA, version, advertised version and trust reason in management UI.

**Exit:** Tamper tests cover signed index, signature bytes, revision, package bytes, mismatched owner and trust downgrade; only verified keys receive a verified badge.

### Batch 05M -- Network isolation and HLS transport (P1, security/reliability gate)

**Status: [ ] Planned; preserve AniWorld's working transport during changes.** The undocumented AVFoundation HTTP header-field option is only best-effort and does not guarantee headers on child HLS requests.

- [ ] Enforce HTTPS and a per-module host allowlist on initial requests and **every redirect**, including refreshed DNS/public-address checks and rejection of local, loopback, link-local, private and credentials-in-URL targets.
- [ ] Restrict forbidden request headers; do not leak source credentials or cookies to unrelated hosts, to UI diagnostics or to persistent cache keys.
- [ ] Keep bounded response bytes, deadlines, concurrency, host cooldown, cancellation and retry handling; distinguish 403, 429, redirects, source-side empty data and binary/media errors.
- [ ] Evaluate a safe native HLS transport solution for header-dependent child requests, without claiming undocumented AVURLAsset options guarantee success.
- [ ] Validate media bytes rather than suffix alone when required; distinguish HLS playlists, TS/fMP4 segments, encryption keys and direct MP4 media.
- [ ] Handle cross-host redirects securely; test signed URL expiry and refresh without persisting URLs or tokens.

**Exit:** Both private-host/redirect attacks and legitimate authorized header-dependent media fixtures are covered; real iPhone playback still works.

### Batch 05N -- Updates, immutable releases and rollback (P2)

**Status: [ ] Planned.** A cached catalogue, archived package or installed copy does not imply a current source.

- [ ] Compare installed version/hash against the current advertised production or testing repository entry and display status: current, update available, experimental, retired, unlisted, incompatible, repository unavailable.
- [ ] Preserve installed modules, saved titles, history, favorites and downloads when a listing disappears or a repository is disconnected.
- [ ] Stage updates atomically; verify signatures/identity/zip bounds before swapping, retain a last-known-good package by hash and roll back if post-install validation fails.
- [ ] Do not silently import a TEST identity over production or downgrade publisher trust; do not overwrite immutable release assets.
- [ ] Add opt-in preview for separately hashed artwork packs and explicit source-ID-based asset matching.
- [ ] Allow fallback mappings only after verified title/season/episode/language/source equivalence and user consent; avoid arbitrary cross-source identity guesses.

**Exit:** Update, downgrade refusal, rollback and repository-disconnection tests preserve user data.

### Batch 05O -- Diagnostics, source quality and certification UX (P2)

**Status: [ ] Planned.** Source responsiveness is not equivalent to content correctness.

- [ ] Separate status for repository validity, fixture behavior, live handler result, decoded media, native AVPlayer startup, seeking, audio language, subtitles and physical device.
- [ ] Derive real HLS/MP4 resolution when observable, keep Auto only when appropriate, and label preferred-quality caps as preferences rather than exact locks.
- [ ] Preserve provider-provided Dub/Sub and captions; never fabricate a track or claim spoken language from a source label alone.
- [ ] Group seasons naturally while respecting source order and keeping specials/films distinguished; do not invent missing seasons.
- [ ] Build source health, safe copyable redacted diagnostics, rate-limit cooldown and user-visible supported/unverified badges.
- [ ] Introduce a compact module certification matrix with `CONTRACT_PASS`, `FIXTURE_PASS`, `LIVE_NODE_PASS`, `IOS_RUNTIME_PASS`, `PARTIAL` and `FAIL` and dated, version-bound evidence.
- [ ] Add a release gate: test at least three representative titles including the reported failing title; validate first/middle/latest episode routes and one full playback/seek path on iPhone.

**Exit:** One source has reproducible, version-specific certification evidence and no sensitive URLs/cookies/tokens appear in results.

## Phase crosswalk and future work -- existing phase numbering preserved

### Phase 4 -- Shared catalogue and metadata

- [ ] Define Kinetiq-owned `MediaItem`, `Episode`, `Chapter`, `StreamChoice`, `SourceReference` and `ArtworkReference` models independent of distribution format.
- [ ] Keep original source identities distinct from optional shared metadata IDs (e.g. MAL/AniList), never collapse two titles solely from display-name similarity.
- [ ] Add exact/season-aware search presentation, explicit movie/OVA/special grouping, and optional artwork-only packs with no media authorization implication.
- [ ] Allow media artwork previews and generation only through appropriate authenticated/cache-scoped flows.

### Phase 5 -- Independent repository adapters and module SDK

- [ ] Implement a strict Player ZIP/repository adapter with V3/V4 capability negotiation, `moduleVersion` vs `version` consistency warnings and per-handler contract tests.
- [ ] Implement a separate Manga Sources loose-file index/manifest/script/icon importer (contract v1) with index → manifest → script/icon SHA integrity and explicit trust.
- [ ] Implement an opt-in AROKI **declarative** connector adapter: signed `index.json`, immutable manifest digest, typed HTTPS methods, selectors/transforms, bounded mirror steps; no implicit execution of downloaded JS.
- [ ] Implement an opt-in AnyGo simple source adapter for declarative catalogue URL, resolver route, header mapping, language flags and artwork templates; avoid transferring embedded demo/API secrets to production.
- [ ] Publish Kinetiq module authoring, manifest/schema/version, exact handler return-shape, trust and testing documentation.
- [ ] Preserve high-quality, sanitized fixtures for historical 43-module archive; maintain a machine-readable inventory and file-by-file/line-by-line audit **before** claiming complete code review.

### Phase 6 -- Streaming Engine (not the manga phase)

- [ ] Complete P0/P1 media transport and header propagation gates before treating remote streams as stable.
- [ ] Preserve actual source label, server, HLS variant, effective non-secret header-name set, subtitle metadata and evidence-based failover.
- [ ] Validate stream availability and media data independently of source search results; isolate per-host and per-request failures.
- [ ] Keep source-resolving modules separate from Kinetiq's local/native player so device fixes do not require source-name changes.

### Phase 7 -- Manga & Image Reader

**07A -- Loose-file source importer:**
- [ ] Parse `index.json`, `modules/<slug>/manifest.json`, `index.js` and icon descriptors; verify SHA and identity/host/capability rules; reject untrusted or unsafe scripts and local-HTTP fallback URLs.
- [ ] Support `pageImages` module handlers: search, details, `extractChapters`, `extractImages`; handle complete pagination, chapter ordering, stable IDs, per-image request headers and bounded image caching.

**07B -- Reader experience:**
- [ ] Build manga Home/details/chapter reader, vertical/horizontal/RTL reading, zoom, image prefetch, chapter/page progress, bookmarks, favorites and offline reading.
- [ ] Support source-image failures honestly: HTML/challenge instead of image, missing page, 403/429, expired URL, mixed HTTP origins and scrambled-image metadata.

**07C -- Restricted interactive web bridge:**
- [ ] Prototype `pagev2` only when explicitly declared by an approved module; use isolated ephemeral WKWebView, per-hop allowed-host policy, strict time/response limits and no app credentials or unrestricted JavaScript capabilities.
- [ ] Do not describe a JSCore `fetchv2` substitute as equivalent to browser-backed page state, or promise protected sources will work without live iOS verification.

**07D -- Text/publications:**
- [ ] Add `extractText`/`extractResources`, HTML/text sanitization, typography/bookmarks, EPUB/PDF file safety and legal/public-license metadata where required by the source; content safety and content rights are separate checks.

### Phase 8 -- Music, Phase 9 -- Servers/TV, Phase 10 -- Downloads/Sync

- [ ] Treat the manga index's `audio` entries and Player `music` modules as **new separate audio contracts**, not video or manga readers with renamed tabs. Add background playback, Now Playing controls and music metadata after a dedicated threat model.
- [ ] Explore Live TV only with a genuine source type, time/EPG semantics, media health and rights/authorization checks; do not infer Live support from merely finding stream URLs.
- [ ] Extend verified media-specific downloads to audio, publications and manga after video offline playback/retry/cleanup tests pass; support cancellation, resume, expiring URLs and storage quotas.

### Phase 12 -- Independent release gates

- [ ] CI: source formatting/lint, Swift syntax, full compile/link, XCTest suites and package-security checks on **the exact commit** proposed for release.
- [ ] Integration: installer/repository → source Home → search → details → episodes → stream → AVPlayer with module-version and source IDs preserved.
- [ ] Device: iPhone startup, play/seek/resume, audio/subtitle language, quality, PiP/AirPlay if relevant, long playback and memory; keep simulator, Node and device evidence distinct.
- [ ] Security: publisher-signature pinning, redirect/public-address/host policy, ZIP paths/hashes, raw credentials in logs, fail-closed boundaries and private data retention.
- [ ] Release: documented changed files, test commands/results, failed tests, known source-side limitations, reversible update and user-visible release notes; do not claim fully certified from static analysis alone.

## Sequencing and release acceptance

| Gate | Dependencies | Completion evidence |
| --- | --- | --- |
| Playback safety, 05I | Existing v0.3 source + actual installed modules | Physical-device regression record |
| Compatibility, 05J | 05I sample shapes + extracted 43-module archive | Exact fixture/XCTest reports |
| Discovery, 05K | 05J decode and real optional handlers | Home/feed tests + iPhone details/play path |
| Publisher trust, 05L | Verified production key ownership | CryptoKit tamper suite + explicit trust state UI |
| Network and HLS, 05M | 05I failures and 05L trust policy | Per-redirect host tests + iPhone media checks |
| Lifecycle/certification, 05N–05O | Verified install/update transport and diagnostics | Rollback tests + honest evidence badge |
| Manga, 07A–07C | Separate indexed format and web-bridge permissions | Fixture, reader and iOS WKWebView tests |
| Later audio/connector expansion | Ownership/licensing review, typed contract architecture | Format-specific tests and native playback/reading |

**Release milestone target:** The next *candidate* is called **Kinetiq 0.4.0 -- Module Discovery and Compatibility**. The prepared 05J ZIP is not an installed binary and not automatically a shipped version. Version/date/title are provisional until source merge, CI and device checks pass. Keep incomplete existing Phase 1–12 items unchecked even when their code appears present.

**No scope deletion:** This programme augments the original roadmap. Earlier Phase 2 PiP/subtitle/quality requirements, Phase 3 library tasks, Phase 9 personal servers/tvOS, Phase 10 downloads/sync and Phase 11 personalization remain intact and are not replaced by the module-engine train.

<!-- KINETIQ_8_REPO_ROADMAP_2026_11_08_END -->

# Reference Research

The following public sources inform Kinetiq's product and architecture
planning.

## Synthetiq Player

- Synthetiq Player -- App Store:
  https://apps.apple.com/us/app/synthetiq-player/id6757483803

- Synthetiq Player -- Google Play:
  https://play.google.com/store/apps/details?id=k.Synthetiq.Player

- Synthetiq Player -- Apple TV listing:
  https://apps.apple.com/vg/app/synthetiq-player/id6757483803?platform=tv

- Synthetiq Player -- Public GitHub repository:
  https://github.com/Synthetiq-HQ/synthetiq-player

- Synthetiq -- Products:
  https://synthetiq.uk/products

- Synthetiq -- Module documentation:
  https://synthetiq.uk/modules/

<!-- KINETIQ_8_REPO_REFERENCES_BEGIN -->

## Eight-repository evidence snapshot (8 November 2026)

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

<!-- KINETIQ_8_REPO_REFERENCES_END -->

## Kinetiq

- Kinetiq -- Repository:
  https://github.com/Haimiya612/Kinetiq-iOS

- Kinetiq -- iOS build and signing guide:
  docs/IOS_BUILD_AND_SIGNING.md

---

*Kinetiq -- One platform. Every kind of media.*


<!-- KINETIQ_BATCH_06I_STREAMING_HQ_ADDENDUM_BEGIN -->
## Batch 06I -- Streaming HQ Experiences and Local Manga Reader (candidate)

Status: [ ] SOURCE CANDIDATE — not yet Xcode-compiled or accepted on a physical iPhone.
Preserve the original twelve roadmap phases, 05I–05O, 07A–07D,
and the eight-source repository research without deleting prior scope.

### Phase 1 / 3 / 4 / 11: Original design system and media discovery
- [ ] Preserve Home, Favorites, Downloads, Settings as the four top-level destinations.
- [ ] Add eight original persisted visual presets: Studio, Prism, Atelier, Signal, Ember,
  Vault, Zen and Nebula, alongside Signature, Cinema, Anime Pulse, Aurora and Nocturne.
- [ ] Theme changes apply to app surfaces and native player chrome, not to source identities.
- [ ] Theme picker remains in the main app Settings (never inside the player).
- [ ] Make source-aware search the destination of Discover, not a generic marketing screen.
- [ ] Show real local saved artwork on Home hero when an actual continue-watching item exists;
  the primary hero button resumes that genuine media item.
- [ ] Never invent provider data, rankings, posters, downloads or unsupported capability badges.
- [ ] Verify dynamic type, Reduce Motion, VoiceOver, Dynamic Island and app safe-area insets.

### Phase 7: Local-image reader foundation (not remote adapter completion)
- [ ] Import user-selected image files via Files security-scoped URLs, into app-owned library.
- [ ] Show actual local albums, ordered pages, private-copy deletion and bounded image decoding.
- [ ] Provide vertical and horizontal reading, RTL reversal and persisted page position.
- [ ] Run real iPhone image-format, long-album, seek/back, relaunch and delete tests.
- [ ] Keep remote source parser/permission/host policy (07A/07C) unimplemented until tested;
  do not mark manga module compatibility, text reader or offline-source downloads complete.

### Phase 2 / 5 / 6 / 12: Release, streaming and security gates
- [ ] Source package must match base 70ac7c6afac3cc73aa929d17fef6ae3a54b4be6b, no pbxproj changes.
- [ ] XCTest and Xcode CI must pass on final commit with exact SHA recorded.
- [ ] Validate real source search → details → episodes → server → native AVPlayer and local playback.
- [ ] Verify manual/automatic/repeated PiP and return; embedded captions and known external
  subtitle overlays in system PiP are separate acceptance cases (known failing).
- [ ] Preserve load screen and landscape start semantics during first-frame gating.
- [ ] Complete 05J fixture, 05L publisher trust, 05M URL/SSRF/redirect policy, 05N rollback,
  05O diagnostics and certification before claiming security/source compatibility complete.
- [ ] Record device model, iOS version, CI run URL, IPA SHA-256 and any failures.
<!-- KINETIQ_BATCH_06I_STREAMING_HQ_ADDENDUM_END -->