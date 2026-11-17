# Kinetiq all-in-one foundation expansion — same app version

This is an incremental build on the previously supplied full source tree, not
an app-version upgrade and not a claim of finished 200+ research controls.
`MARKETING_VERSION` remains the user's `0.3.0`. The supplied project's existing
Discord RPC transport and settings files are unchanged.

## New, connected features

| Area | How to open | Behavior | Limitations |
| --- | --- | --- | --- |
| Player Action Finder | Module Player → More → Find a player action | Search 35 real commands, only when available; shortcuts call the existing AVPlayer, controller, sleep timer, A/B loop, scene memory and Brain | No unsupported codec/screenshot actions shown as working |
| Binge Guard | Module Player → More → Binge Guard | Turn autoplay off or pause after 1/2/3 successfully completed episodes | Limit is session-scoped; preferences apply to module player only |
| Recovery Center | Module Player → More; Settings → Playback | Bounded 200-record categorized history of module-resolution/AVPlayer failures, retry/fallback actions, HTTP status, safe next steps; share redacted report or clear | No secret-bearing raw error text; no automatic server manipulation from Settings |
| Japanese Study Deck | Module Player → More; Settings → Playback | Manually create cards with current scene identity, episode/time/language; review Again/Hard/Good/Easy offline; export CSV | Does not claim OCR, transcript extraction, automatic translation or audio capture |

## Privacy and safety contracts

- Recovery persistence takes only enumerated event type/outcome, normalized
  uppercase category code, numeric HTTP status and sanitized source/episode
  labels. URL-looking, key-value or newline labels are hidden completely.
- Study cards contain user-entered text and optional `KinetiqSceneAnchor` only;
  they contain no streaming URL or downloaded media. CSV escapes cells and
  prefix-protects spreadsheet formulas.
- Study scene jump is available only if the current media ID, episode ID and
  language still agree with the card's scene anchor; no fuzzy cross-cut jump.
- Binge limits count *completed episode notifications*, never stream retries.
  The current episode is recorded as complete before Binge Guard pauses.
- Existing four tabs, Local Library boundaries, PiP, subtitles, queue, source
  labels, Discord RPC and GitHub Actions workflow files remain unchanged.

## Tests and pending evidence

Added `KinetiqRecoveryStudyContractsTests.swift`: event sanitization,
coalescing, UserDefaults persistence, HTTP code bounds, scheduling math,
duplicate cards, CSV safety, Binge Guard decisions and searchable command
inventory. Registered in the original `KinetiqTests` Xcode target.

The Linux environment ran all eleven Python checks (six roadmap tests plus
five new integration-wiring tests) and can verify archive integrity, but
cannot compile a native iOS target. **The GitHub
Actions Run / physical-device regression is intentionally deferred** at the
user's request. In particular, multi-sheet transitions, the 35 Action Finder
commands, completion counting, captions and Discord must be checked on iPhone.

## Archive import choices

1. **Full-source ZIP (recommended):** one `Kinetiq-iOS-main/` folder with all
   files, assets, the Xcode project and both blueprints. Merge/replace from the
   repository root in GitSync; avoid creating a second nested project folder.
2. **Changes-only ZIP:** just the original paths added/modified by this
   foundation expansion, including an unchanged-source verification manifest.
   Apply only onto the exact previously supplied base; no binary patch tool.

There are no nested ZIPs inside the source tree, no generated HTML and no
artificial large media files. Archive size is not an app feature.
