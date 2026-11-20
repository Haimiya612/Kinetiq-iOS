# Kinetiq M01 — Source Flight Control + Continuity Safety

**Source delivery:** 17 November 2026, from the owner's `Kinetiq-iOS-main 2.zip`.
**Application version:** unchanged at `0.3.0`.
**Delivery form:** complete project source tree; no remote changes or release claim.

## Why the previous Actions Run failed

Read-only inspection of GitHub Actions run `44109144432` (commit `c0f0548f`)
showed a successful compilation followed by **two XCTest assertion failures**.
The unsigned IPA artifact step was skipped because the test step failed.

1. `DiscordPresenceContractTests.testAnimePlusKinetiqUsesEachOriginalHeadingStyleAndKeepsRichCard` expected the empty suffix style to omit `Kinetiq`. The actual, intentional RPC fallback includes `Kinetiq`. **Only the test expectation was corrected. The existing Discord RPC implementation was not edited.**
2. `KinetiqCompassContractTests.testSmartSearchExtractsGenreAndLengthWithoutLosingTitle` showed `Find Roshidere` being sent as the literal title. The Compass direct-search parser now removes leading request verbs while preserving genuine title words such as `on` in `Attack on Titan`.

These are **source-level fixes, not a verified new CI run**. Import and commit this
complete source tree, then run GitHub Actions to confirm the two assertions and
the remaining tests pass before trusting any IPA.

## M01 changes

- **Source Flight Control evidence:** Previously recorded host-level success/failure is now expressed as human-readable age and observed startup duration. Unknown hosts are explicitly unverified; an observation never proves the current episode works. Existing alternative servers remain visible.
- **Per-title, per-language server pins:** In the module player, open `More > Servers`, then tap the pin on a stream. Explicitly chosen hosts take priority only while the module still offers that candidate. Pins are bounded and stored as SHA-256 identifiers, not stream URLs, headers, signed query parameters or cookies. Unpinning is reversible.
- **Per-title automatic-fallback switch:** The same Servers panel can disable automatic *server switching* for the current source, title and audio language. Automatic initial retry is retained. When the current stream ultimately fails, the player reports the disabled fallback and leaves manual server selection available. Default behavior for everyone remains unchanged (automatic fallback on).
- **Cross-source Scene Passport safety:** Source-to-source seek suggestions now compare parsed season/episode/OVA/special/recap identities. `S1E4` is equivalent to `Season 1 Episode 4`, but **not** to `S2E4`, bare `4`, `OVA 4`, or an uncertain fractional episode. Both source IDs must already be confirmed as connected, and language and cut duration still must agree. Suggestions without a season identifier explicitly ask the user to verify the edition.
- **Confidence disclosure:** The Scene Passport option shows the matching confidence as a percentage along with a plain-English rationale. It remains a suggestion; no automatic seek across uncertain cuts.
- **Regression tests:** Compass title parsing, season/edition rejection, host observation ranking, server-pin persistence/scoping, privacy-safe storage, fallback opt-out and the existing Discord heading contract.

## Preserved invariants

- Home, Favorites, Downloads, Settings are the only four root tabs.
- Existing module IDs, display/source names, media import separation, playback,
  subtitles, PiP, offline downloads and user storage keys are retained.
- No GitHub files, commits, branches, Actions settings or remote services were modified.
- `Kinetiq/Features/Integrations/KinetiqDiscordPresence.swift` is **unchanged**.
- `docs/ROADMAP.md`, both research blueprints, older delivery documentation and
  the complete future feature inventory remain present.

## Scope and known limits

M01 is **the first incremental part** of the wider identity, continuity and
Source Flight Control program. Do not mark its larger roadmap references or
the 180+/395-item research inventory complete based on this ZIP.

Still pending: true stable cross-provider edition graph with user-corrected
links and historical audit, scene subtitle landmarks and file fingerprints,
consented diagnostic probes with quality-language measurement, automatic
encrypted multi-device synchronization, live rooms/social backend, and every
remaining feature in the preserved blueprints.

No local Xcode or Apple SDK is available in this Linux execution environment.
The Python repository checks passed; Swift compilation, XCTest and actual iPhone
playback must be verified by a fresh Actions Run and an on-device test.

## Safe import and acceptance checklist

1. Save a backup of the existing GitSync checkout or confirm it can be recovered
   from its current commit.
2. Unzip the delivery. Inside is exactly one `Kinetiq-iOS-main/` project root.
   Use that entire project as your replacement working tree, preserving the
   `.github/` workflows and `Kinetiq.xcodeproj/` bundle. Do **not** nest a
   second `Kinetiq-iOS-main` inside the Git working tree.
3. Confirm `MARKETING_VERSION` remains `0.3.0`, inspect local changes, commit,
   then allow Actions to run. This import/commit is **not** performed here.
4. Confirm previous two XCTest failures are gone and the unsigned IPA step runs.
5. On iPhone, test a source with two servers: rank evidence, pin B, reopen the
   title, ensure B is preferred, unpin, and ensure other servers remain.
6. Turn automatic fallback off for that title; simulate a failure only on a
   disposable stream. Confirm it stops after a bounded retry and offers manual
   selection. Confirm another title/language retains its normal fallback.
7. Confirm playback, PiP, subtitles, offline playback, four tabs and Discord
   status all behave as in the previously installed build.
8. Verify a Scene Passport never equates S1E4 to S2E4 or to an OVA.

**Status:** M01 source prepared; *Actions and iPhone acceptance pending*.
