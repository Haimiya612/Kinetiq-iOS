# Batch 05J — Native discovery integration and eight-repository engineering audit

Base: `Haimiya612/Kinetiq-iOS@4a74bbe73ac59d0e85b6bdaadd3e0faadb32be6b` (Nov 8, 2026).

## Findings from inspected code

- `Kinetiq/Features/Modules/ModuleRuntime.swift` already has an async JavaScriptCore module invocation bridge, five-argument `fetchv2`, manual redirect control, source response caps, timeout management, stream response shape decoding and player diagnostics. Do **not** replace this infrastructure merely to add Home feeds.
- Its `exploreContent` currently uses only user-owned continue/favorite shelves and search suggestions. The extracted Synthetiq One, Synthetiq Anime, Synthetiq Flux and AniWorld modules export `discoveryHome` and `discoveryFeed`, so the gap is specifically **invoking and rendering** those handlers.
- Synthetiq One's `index.js` maps `sections` with `id/title/style/items` and optional `viewAll.mode=feed/feedId`. `discoveryFeed(feedId,page)` yields `items`, `page`, `hasMore`.
- AniWorld's `index.js` exports the same two handlers and sends source-specific shelf names such as `Neue Animes`. Source names and content IDs must remain unchanged. The user reports AniWorld sometimes now plays; this upgrade does not modify playback or hoster resolution.
- The production `kas021/Synthetiq-Modules` `repository.json` advertises SHA-256 package digests and detached signatures. Kinetiq's existing installer verifies SHA-256 but does **not** establish signature authenticity; this batch does not falsely claim trusted signed repository support.
- Synthetiq Manga Sources is a **different** contract: loose-file `index.json` plus `manifest.json`, `index.js`, page-image/text/publication/audio handlers, and optional WebKit-only `pagev2`. It cannot be made compatible simply by renaming the index or accepting a content-type string. A separate sandboxed runtime, image reader and authenticating repository adapter remain future work.
- AROKI connector indexes are signed **declarative** manifests, not executable Player ZIPs. AnyGo uses a tiny source manifest. They likewise need explicit import adapters and validation, not generic module ZIP import.
- Testing-Modules-1-2-3-4 contains reproducible ZIP/bundle build and signature test patterns; Module-Testing-PL documents publisher/identity fallbacks, signature failure repair and test fixtures. Those patterns motivate the bounded V3/V4 importer gate and contract tests.

## New code

| File | Change |
|---|---|
| `Kinetiq/Features/Modules/ModuleDiscoverySupport.swift` | Pure deterministic decoder for source-owned shelves, cards and feed pages |
| `Kinetiq/Features/Modules/ModuleDiscoveryViews.swift` | Native source Home shelves, branded cards, feed sheet and load-more flow |
| `Kinetiq/Features/Modules/ModuleRuntime.swift` | Small insertion into existing Explore, preserving current player/runtime |
| `Kinetiq/Features/Modules/ModulePackageManager.swift` | Explicit V3/V4 acceptance ceiling |
| `KinetiqTests/ModuleDiscoveryContractTests.swift` | Six fixture tests, independent of provider uptime |
| `Kinetiq.xcodeproj/project.pbxproj` | Register two new app files and test file in target sources |
| `release-notes.json` and project build settings | 0.4.0 candidate What's New metadata and build 4 |
| `scripts/audit_8_repos.py` | Source/config file iteration with per-line non-secret evidence |
| `.github/workflows/kinetiq-eight-repo-audit.yml` | Opt-in eight-source clone, scan, artifact upload |
| `.github/workflows/kinetiq-05j-integration.yml` | Opt-in safe patch and draft PR branch creation |

## Acceptance criteria before merge

1. GitHub Actions compiles the new files and six deterministic fixture tests pass.
2. With **Synthetiq One** installed and trusted, Explore displays actual module-provided shelves; cached titles show FAST only if the source reports the flag. Tap a title and confirm its existing details/episode UI still loads.
3. A shelf with `viewAll.feedId` opens the feed. "Load more" calls subsequent page numbers, deduplicates repeated IDs and stops when the source says `hasMore=false`.
4. With **AniWorld** installed, confirm source-owned German sections load when provider returns them. Then play the same working AniWorld episode, ensuring no regression in media startup, Sub/Dub, captions or seeking.
5. With an older module that lacks discovery handlers, Explore still provides its existing Search, Continue Watching and favorites. There should be no synthetic Trending list.
6. Reinstall/updating tested V3/V4 modules still works; a fictional V5 manifest is rejected clearly before execution.
7. Existing modules, playback history, favorites, source identities, SHA checks and local files remain untouched.
8. Manual iPhone playback and GitHub CI are required for certification. No provider HTTP 200, JS parse success or Node smoke test may be relabeled `IOS_RUNTIME_PASS`.

## Deferred — do not silently add to this patch

- Robust HLS child-playlist/segment header forwarding. The current `AVURLAssetHTTPHeaderFieldsKey` compatibility route is undocumented; altering it while AniWorld is working is a higher-risk transport change. Design a separately reviewed, origin-bound loader and test on iPhone.
- Verified ECDSA P-256 repository authentication with pinned publisher keys. `signature` fields currently are metadata, not authenticity proof.
- Direct installation of extracted `modules/` without a repository index (requires strict manifest, source identity, explicit user approval, integrity, isolation and rollback).
- Manga `pageImages`, text, EPUB/PDF, WebKit `pagev2`, AROKI declarative connectors and AnyGo source-import adapters.
- iOS UI for author/publisher provenance, version mismatches, module installation rollback and automated source health certification.

## Audit evidence boundaries

The static audit tool is designed to walk every matching file line from the eight cloned repositories. Patterns such as `eval`, `new Function`, loopback host declarations or `fetchv2` are **review leads**, not automatically vulnerabilities. The tool records repository-relative file paths, rule IDs and exact source line numbers without leaking matching code, tokens, request headers or stream URLs. Binary ZIP contents are not automatically decompressed by this scanner. This batch's implementation was verified against selected live GitHub source files; an exhaustive line-by-line audit across every file has **not** yet been executed in this session and should only be claimed once the provided Actions audit job completes.

## References

- [Synthetiq One extracted implementation](https://github.com/Haimiya612/Kinetiq-Modules/tree/main/modules/synthetiq-one-v1)
- [AniWorld extracted implementation](https://github.com/Haimiya612/Kinetiq-Modules/tree/main/modules/aniworld-v1)
- [Player production repository](https://github.com/kas021/Synthetiq-Modules)
- [Manga format](https://github.com/Synthetiq-HQ/synthetiq-manga-sources/blob/main/docs/FORMAT.md)
- [AROKI connector contract](https://github.com/kas021/AROKI-Connectors)
- [TEST source and signature repair](https://github.com/kas021/Module-Testing-PL/blob/main/docs/BETA_IMPORT_SIGNATURE_REPAIR_20261016.md)
- [FRAnime test and packaging workflow](https://github.com/kas021/Testing-Modules-1-2-3-4)
- [AROKI discovery restoration report](https://github.com/kas021/Testing-Modules-AR/blob/main/docs/discovery-and-restoration-2026-09-13.md)
- [AnyGo source declaration](https://github.com/kas021/AnyGo-Sources/blob/main/sources/synthetiq-one.json)
