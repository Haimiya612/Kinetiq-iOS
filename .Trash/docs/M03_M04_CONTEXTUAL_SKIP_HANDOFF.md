# M03/M04 — Contextual Skip and Next Episode (app version 0.3.0)

**Source:** user-supplied `Kinetiq-M03-Cumulative-0.3.0(1).zip`.
**Delivery:** cumulative Xcode source repository; not a compiled IPA.
**Status:** Swift source parses on the available toolchain; 20 Python repository tests pass. **Xcode/iPhone verification remains required.**

## New functionality

1. Contextual **Skip Intro**, **Skip Recap** and **Skip Credits** buttons appear while playback falls within a completed, manually confirmed range for the **same provider, title, episode, server identity and approximately matching video duration**.
2. Server identity is stored as a one-way SHA-256 fingerprint of the normalized server hostname, display name and stream type—not as a URL or token. Markers created by M03 are retained, but require explicit re-verification on their server before becoming eligible for floating skip controls. Tap the button to seek to the saved end. Existing **Undo Seek** in More → Power Deck can reverse the seek. The small dismiss X hides that prompt until the current marked segment is left.
3. A floating **Next Episode** button appears when the exact source/episode has a verified credits range currently playing, or in the last 20 seconds of the episode. The next episode must be in the current series and have a supported Sub/Dub option; no alternative source or season is guessed.
4. Once AVPlayer reports actual end of the current item, existing autoplay/Binge Guard rules decide whether an **on-screen, cancellable 10-second countdown** should start. It displays the provider's next episode number and offers **Play Now** or **Cancel**. Cancel affects that finish only, not the global autoplay setting.
5. Turning autoplay off cancels an active countdown. The prompt is shown only when the app is active; background playback/PiP follows normal autoplay without an invisible countdown.
6. Existing `KinetiqManualChapterStore` persists ranges using original source+anime+episode identity; existing Keychain/token-bearing Discord functionality is unchanged.
7. Settings in **Player → Playback**: toggle contextual Skip buttons, toggle 10-second countdown, and the existing autoplay/Binge Guard controls. The feature does not add another main tab.

## How to set verified timestamps

In the **module player**, open **More → Power Deck**. Find **Manual Opening / Recap / Credits**.

- Scrub to the actual start of the opening, press **Mark Start**.
- Scrub to the end of the opening, press **Mark End**.
- Repeat for Recap or Ending / Credits as desired. No timings are guessed. Each marker is scoped to the *current server* and measured runtime, so re-mark if you switch to a substantially different cut or CDN.
- Revisit the marked interval in that same episode and server: **Skip Intro/Recap/Credits** appears automatically. Changing episode, provider, server or to a different runtime will not carry the floating prompt over.
- To undo a skip, open **More → Power Deck → Undo seek**.

## Exclusions / follow-up engineering

- No automated scene analysis, crowd-sourced marker database or title-based unverified timestamp sharing. These could be added in later stages only after verification and privacy design.
- The contextual overlay is for the **native module AVPlayer**. Web embeds, local-library player and system PiP need their own capability-specific integration; they are **not** represented as implemented here.
- For the post-episode countdown, this release deliberately waits until AVPlayer reaches the actual end. It does not forcibly interrupt the episode at the start of credits.
- Playback may be interrupted by module failures; the next episode attempt uses existing module resolver/error handling.
- Compile using GitHub Actions, then run the acceptance tests. Linux Swift parsing is not a replacement for the Apple SDK compiler.

## Files changed

- `Kinetiq/Features/Modules/ModulePlayerView.swift`: overlay policy, contextual buttons, autoplay countdown/cancel, player toggles.
- `KinetiqTests/KinetiqPlayerPersonalizationTests.swift`: source/episode isolation, boundary/invalid-range conditions, label and next-episode gating, storage persistence.
- `docs/M03_M04_CONTEXTUAL_SKIP_HANDOFF.md`, `docs/M03_M04_SKIP_ACCEPTANCE.md`, `docs/M03_M04_SKIP_MANIFEST.json`: reproducible delivery metadata and test instructions.

No edits to `Kinetiq.xcodeproj/project.pbxproj`, app version, Discord source, four-tab root, or module provider identifiers.
