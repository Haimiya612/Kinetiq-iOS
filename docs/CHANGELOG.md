# Kinetiq Changelog

## Unreleased -- Batch 03E (6 November 2026)

Prepared from commit `0aa310df2341927841facad5f82b22a8992a1a08`; iOS validation pending.

- Add optional module-provided SRT/WebVTT tracks to the existing Subtitles panel.
- Add Off, loading/error/retry states, and an in-app subtitle overlay driven by AVPlayer time.
- Cancel stale requests and reset cues when selecting another track, episode, server, or Off.
- Carry an available external language choice within the player session; retain Off across stream changes.
- Bound subtitle transfers to 2 MiB and 20,000 cues, keep credentials scoped, and avoid persisting subtitle URLs.
- Retain legacy stream shapes, local subtitle behavior, navigation, player controls, and Batch 03D progress.
- Add 18 regression cases to the existing test file. They have not been executed here.

PiP/AirPlay rendering of external subtitles, real-source compatibility, Xcode builds,
and physical-device tests remain unverified or deferred. Details: `docs/BATCH_03E.md`.


## Unreleased -- Batch 03D (6 November 2026)

Implementation prepared from commit `8efde5e117243ab85e5bb1f86f254d4aeef8f1d5`.
This entry describes source changes awaiting Xcode and iPhone validation.

- Retain remote progress separately for each episode and Sub/Dub language.
- Migrate the previous collection format while preserving Favorites and its last saved position.
- Add episode progress indicators, watched filters, episode-number search, and per-language watched controls.
- Select an available resumable episode or the first unwatched episode in source order.
- Exclude completed episodes from Continue Watching and preserve progress when a card is hidden.
- Correct Sub/Dub handoff position reuse; save current progress on pause, seek completion, and app inactivity.
- Add regression tests to the existing test target file and update roadmap status without deleting planned features.

Navigation, player appearance, source identities, module contracts, project identifiers,
and CI workflow files are retained. Full build/device acceptance remains pending.
