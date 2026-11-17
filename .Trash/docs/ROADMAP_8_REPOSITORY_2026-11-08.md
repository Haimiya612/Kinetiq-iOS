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
