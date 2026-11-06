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

**Current focus:** Module subtitle tracks and playback-memory verification across Phases 2, 4, and 6.

**Working baseline:** `0aa310df2341927841facad5f82b22a8992a1a08` on `main`,
inspected on 6 November 2026. The implementation has advanced beyond the older
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

These observations describe source code, not a fresh build or device acceptance
result. Manga reading, downloads, cloud synchronization, metadata providers, and
all other unchecked requirements retain their places in the roadmap.

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

---

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

## Kinetiq

- Kinetiq -- Repository:
  https://github.com/Haimiya612/Kinetiq-iOS

- Kinetiq -- iOS build and signing guide:
  docs/IOS_BUILD_AND_SIGNING.md

---

*Kinetiq -- One platform. Every kind of media.*
