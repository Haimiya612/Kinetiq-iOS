# Kinetiq Development Roadmap

This is the master plan. A checked item means the decision/documentation exists, not that a feature has shipped. Implementation status requires code, tests, and device verification. **iOS is the active development target.** The existing Quest/Android app remains a preserved prototype, not the current implementation target.

## Phase 0 — Product and engineering foundation

- [x] Product name and product-family identity.
- [x] Hybrid personality: premium presentation, enthusiast capabilities.
- [x] Adaptive light/dark visual direction.
- [x] Dual module strategy: Synthetiq compatibility + native Kinetiq modules.
- [x] Initial architecture and security principles.
- [x] iPhone-first source-control workflow documented.
- [x] Direct IPA sideloading with KSign selected as the intended distribution route.
- [ ] Confirm minimum supported iOS version and device baseline.
- [ ] Confirm Swift/Xcode toolchain and dependency versions on the selected macOS runner.
- [ ] Inspect and document the published Synthetiq module specification and distinguish verified behavior from unpublished internals.
- [ ] Establish repeatable macOS CI, IPA packaging, signing handoff, and device-install workflow.

**Exit criteria:** implementation-ready iOS specification, verified deployment baseline, and repeatable build/install process.

## Phase 1 — Native iOS application foundation

- [ ] Create the native Swift project and package structure.
- [ ] Build SwiftUI navigation and adaptive design system.
- [ ] Implement light/dark/system appearance.
- [ ] Add settings persistence, structured logging, and error handling.
- [ ] Add unit tests and GitHub Actions macOS build/test checks.
- [ ] Establish reusable animation and motion components.
- [ ] Add polished screen/navigation transitions and responsive micro-interactions.
- [ ] Add loading, empty, error, and interaction animations.
- [ ] Implement random launch tagline selection from the three approved lines; avoid repeating the previous launch's tagline.
- [ ] Produce an IPA build artifact from CI.
- [ ] Sign with KSign and verify installation and launch on the target iPhone.

**Exit criteria:** app launches reliably on-device, navigation and settings work, motion foundation and tagline selection work, and CI produces a verifiable IPA that can be signed and installed.

## Phase 2 — Playback and player experience

- [ ] Integrate AVFoundation for native playback.
- [ ] Implement local-file playback first, subject to iOS file-access rules.
- [ ] Implement playback state, buffering/error UI, retry, seeking, and resume.
- [ ] Add audio/subtitle selection and subtitle styling where supported.
- [ ] Add playback speed, queue, next item, and sleep timer.
- [ ] Design an iPhone-native viewing experience and responsive layouts.
- [ ] Test supported codecs, containers, hardware decoding, and performance on-device.

**Exit criteria:** local media can be selected, played, paused, sought, resumed, and viewed reliably on the target iPhone.

## Phase 3 — Kinetiq Engine and module compatibility

- [ ] Inspect the published Synthetiq documentation, package format, handlers, and runtime assumptions.
- [ ] Define Kinetiq's independent internal module API.
- [ ] Implement a Synthetiq compatibility adapter from verified specifications.
- [ ] Define and implement the native Kinetiq module contract.
- [ ] Decide on a safe iOS-compatible module execution model; do not assume arbitrary Node.js or browser APIs are available.
- [ ] Add repository catalogue validation and package integrity checks.
- [ ] Add install, enable/disable, update, rollback, and uninstall.
- [ ] Add capability declarations, execution limits, diagnostics, and test fixtures.

**Exit criteria:** both module formats integrate through adapters and can be tested without coupling the player to either external format.

## Phase 4 — Discovery and catalogue

- [ ] Search across enabled modules.
- [ ] Normalize titles, aliases, artwork, and metadata.
- [ ] Deduplicate results from multiple sources.
- [ ] Add filters, sorting, categories, and source indicators.
- [ ] Add details and episodic navigation where supported.
- [ ] Handle missing and conflicting metadata gracefully.

## Phase 5 — Personal library and profiles

- [ ] Watch history and continue watching.
- [ ] Watchlists, favourites, and collections.
- [ ] Local profiles and profile-specific settings.
- [ ] Hidden titles and metadata corrections.
- [ ] Export/import and local backups.
- [ ] Optional recommendations and release reminders.

## Phase 6 — Network and personal media

- [ ] SMB and WebDAV, subject to iOS capabilities and platform restrictions.
- [ ] Personal media server integrations.
- [ ] LAN discovery with explicit consent and required local-network permissions.
- [ ] Remote server configuration and diagnostics.
- [ ] Offline downloads only where source terms and rights permit and iOS background/storage constraints allow.
- [ ] Download queue and storage controls.

## Phase 7 — Expanded media

- [ ] Image/gallery viewer.
- [ ] Manga/comic reader with zoom, page fit, and reading direction.
- [ ] Music mode and background playback, subject to iOS audio-session behavior.
- [ ] 180°/360° and stereoscopic video, subject to device and framework support.
- [ ] Optional 3D model viewer where supported.

## Phase 8 — Advanced experience and motion design

- [ ] Premium animated interface with Kinetiq's own identity.
- [ ] Fluid screen transitions, subtle micro-interactions, and responsive feedback.
- [ ] Animated loading and content states.
- [ ] Picture-in-picture and system media controls where appropriate.
- [ ] Accessibility, Dynamic Type, VoiceOver, and reduced-motion support.
- [ ] Battery, thermal, and performance profiles.

## Phase 9 — Module ecosystem

- [ ] Developer SDK, templates, examples, and validator.
- [ ] Repository manager and update channels.
- [ ] Optional community catalogue with moderation/reporting.
- [ ] Publisher provenance and trust indicators.
- [ ] Compatibility matrix and deprecation policy.

## Phase 10 — Release and long-term maintenance

- [ ] Security and privacy review.
- [ ] Accessibility, localisation, performance, and compatibility QA.
- [ ] Repeatable IPA build and KSign signing/sideload checklist.
- [ ] Crash recovery, support process, and changelog.
- [ ] Dependency and licence audits.
- [ ] Stable sideload release and maintenance policy.

## Preserved Quest prototype

The existing Kotlin/Gradle Quest prototype and its historical documentation are retained. It is not part of the active iOS build pipeline. Any future Quest revival or cross-platform strategy should be planned explicitly rather than assumed by the iOS roadmap.

## Cross-cutting requirements

Every phase considers privacy, accessibility, offline/error states, battery and memory use, legal source access, automated tests, and clear user control.
