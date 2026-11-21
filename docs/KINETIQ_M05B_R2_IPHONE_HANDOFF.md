# Kinetiq M05B-R2 — Corrective iPhone handoff

Prepared 21 November 2026 against the owner's M05A source plus M05B changes.
**Corrective source prepared; Xcode and real iPhone verification pending.**
All 41 repository Python contract tests pass. This is not proof of Swift
compilation or live Discord visibility.

## What was corrected from M05B feedback

1. **Player overlays**: Cinema and Studio have compact, translucent footer
   controls rather than large center-spanning black consoles. Focus, Minimal
   and Classic remain distinct while using the same real transport actions.
   A portrait-specific header separates the title from AirPlay, PiP, Lock and
   aspect controls and reserves 62pt for the status bar when insets report 0.
   The unchanged Signature layout is not routed through the redesign.
2. **SubStudio labels**: clearly identify Track 1 (primary), Track 2
   (secondary), Track 3 (tertiary). Romaji's extra color is shown only when
   approximate Japanese Romaji is enabled. It is a generated fourth text
   line, **not** a fourth selectable caption track.
3. **Kinetiq Brain**: `web search ...` no longer misrepresents Wikipedia's
   article prefix search. It now queries the Brave Web Search API with a
   user-owned key stored in iOS Keychain; source cards show actual indexed
   links, titles and snippets. Open Web research settings in Brain to add a
   key. Wikipedia remains opt-in via `wikipedia ...`. AniList and TMDB cards
   are shorter; TMDB attempts official AniList aliases before concluding that
   a title is missing. Exact provider-title and season verification remains
   the user's responsibility. There is no bundled paid provider access or
   general-purpose cloud LLM.
4. **Discord**: removed all browsing scene publications, including for users
   who had previously enabled them, to preserve playback update budget.
   The pause button now follows user intent even when AVPlayer's status is
   transiently paused/buffering. Repeated-seek cooling reduces from 30 to
   12 seconds while respecting the existing rate window.

## Focused test list (PASS / FAIL / N/T)

1. Portrait Cinema: status bar separate from title; all top controls tap.
2. Landscape Cinema: compact controls, video still visible, seek works.
3. Studio landscape: no giant black bar; all controls available.
4. Focus, Minimal, Classic: distinct appearance, no accidental obstruction.
5. Signature: identical to M05A default; no unexpected change.
6. SubStudio: three track labels; Romaji color only when Romaji enabled.
7. Subtitle colors and track spacing persist on app restart.
8. Brain: `web search roshidere` without key explains setup, not roses.
9. With your Brave API key: `web search roshidere anime` gives relevant
   source cards and tappable pages without duplicated giant text blocks.
10. Brain: `wikipedia Frieren`, `anilist Frieren`, `tmdb Frieren`, and
    `tmdb Roshidere` (after setting up TMDB) check aliases/ratings/citations.
11. Discord: pause while buffering and while playing, resume and repeated
    seeks; check actual Discord display separately from local submit status.
12. Discord: Home/Favorites/Settings navigation does not publish activities;
    playing/pausing should get first priority.
13. Core regression: PiP, source switch, subtitles, app tabs, module search.

## How to import

Upload the full cumulative `Kinetiq-update.zip` to the root of the main
GitHub repository under that exact name, commit, run **Import Kinetiq Source
ZIP**, then manually run **iOS CI**. The import workflow replaces all
allowlisted source directories; do not use a patch-only ZIP.

## Intentional limits

- Brave Search requires the owner's own plan/key and network connectivity.
  The key is kept in Keychain; only the typed public search query goes to
  Brave. Provider terms, quotas and pricing are outside Kinetiq's control.
- Real web search currently supplies indexed snippets and links, not
  arbitrary page fetching or ChatGPT-style reasoning over full websites.
- Discord account-automation activity is unofficial and may be rate-limited,
  rejected or unavailable externally. No status packet is guaranteed.
- No iOS simulator or actual device test can run on this Linux environment.
