# Kinetiq Changelog

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
