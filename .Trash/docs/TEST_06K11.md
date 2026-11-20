# Kinetiq 06K.11A + 06K.11B — iPhone Test Checklist

Mark each item **PASS** or **FAIL** after testing. Untested items start as
**NOT TESTED**. Record any explanations only under Notes at the end.

## Build and data integrity

- [NOT TESTED] GitHub Actions iOS build succeeds.
- [NOT TESTED] New metadata contract XCTest tests pass.
- [NOT TESTED] Existing favorites, watched, resume and source identities survive upgrade.
- [NOT TESTED] Same Sub/Dub episode still plays through the existing player, including PiP.
- [NOT TESTED] Episode download and offline playback still use the original player.
- [NOT TESTED] Local Library remains independent of online module history.

## Episode information

- [NOT TESTED] Source-provided episode title appears instead of generic Episode N.
- [NOT TESTED] Source-provided 16:9 episode thumbnail appears instead of play icon.
- [NOT TESTED] A missing title/image retains a clean Episode N placeholder.
- [NOT TESTED] Season 2 does not use Season 1 episode titles or stills (Blue Box).
- [NOT TESTED] Episode title, description and duration display without clipping.
- [NOT TESTED] Episode play controls, progress, menu and download action still work.

## AniList and TMDB

- [NOT TESTED] AniList setting is available and defaults to enabled.
- [NOT TESTED] Matching anime shows a real banner when AniList supplies one.
- [NOT TESTED] AniList missing/ambiguous match leaves the module metadata intact.
- [NOT TESTED] Optional TMDB token saves, remains hidden, and can be deleted.
- [NOT TESTED] With TMDB enabled and correctly matched, episode titles/stills appear.
- [NOT TESTED] With TMDB disabled or not configured, module playback is unchanged.

## Cover redesign and accessibility

- [NOT TESTED] Portrait-only artwork fits completely, with a blurred backdrop.
- [NOT TESTED] Landscape banner fills the wide hero without distortion.
- [NOT TESTED] Episode information and title are readable across all 13 themes.
- [NOT TESTED] Episode buttons have accessible 44-point touch targets.
- [NOT TESTED] VoiceOver labels, Dynamic Type and Reduce Motion remain usable.
- [NOT TESTED] Opening many details does not cause excessive network requests or hangs.

## Notes

(Add all observations, screenshots, module names, and any technical diagnostics here.)
