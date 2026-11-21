# Kinetiq M05C — Player Experience + Free Brain

Prepared 21 November 2026 on top of the prior M05B-R2 full source delivery.
**Not verified by Xcode or on-device playback.** Source contracts are not a
replacement for the macOS/iPhone tests.

## Important rules

- Signature is the existing Default player. It is intentionally not rewritten.
- Existing module protocols, four primary tabs, source names, PiP bridge,
  player callback interfaces and persisted settings remain in place.
- Web research does **not** require Brave, a card, API credits or a subscription.
  Broad results open a browser in the app; Kinetiq does not automatically read
  and rank arbitrary Google results. AniList/Wikipedia cards are fetched from
  those public sources and labeled as such. No credentials are embedded.
- TMDB metadata remains optional behind the app's existing user-provided
  credential setting; Brain works without TMDB.
- If the device supports Apple's on-device Foundation Models and the user
  explicitly enables Conversational AI, Brain can summarize bounded public
  excerpts. This feature is optional, and such summaries still need checking.

## iPhone testing — reply PASS, FAIL or NOT TESTED

1. Signature/Default visual comparison against M05A: absolutely unchanged.
2. Cinema: video stays visible; no giant central box or excessive dimming.
3. Focus: a single play control, subtle lower timeline and usable tools menu.
4. Studio: playback monitor with compact bottom timeline and editor dock.
5. Minimal: unobstructed video with floating primary action and options.
6. Classic: traditional transport row and distinct lower panel strip.
7. Immersive: soft floating control islands; video remains visible.
8. Modern: distinct low-profile bottom command bar.
9. Portrait: title, close, lock, AirPlay, PiP and aspect controls don't overlap
   status bar; review each style, especially Studio, Cinema and Modern.
10. All appearance choices stay selected after closing/reopening the app.
11. Play, pause, 10-second rewind/forward, previous/next work in all styles.
12. Seek scrubber works in all styles; duration and elapsed time remain legible.
13. Episodes, Servers, Audio, Playback, Subtitles, Queue and More are reachable
    in all styles via toolbar or tools menu.
14. Lock, PiP, AirPlay and aspect-fill controls remain functional where
    available, including returning from PiP.
15. Subtitle preferences and external/embedded subtitles still work.
16. Brain → `web search roshidere`: public AniList links (when available) and
    a wider-web browser card; no unrelated rose species represented as facts.
17. Browser card opens results inside Kinetiq; Close returns to the chat.
18. Brain → `what is blue box anime`: appropriate public source cards,
    not a demand for a Brave key.
19. Brain → `wikipedia moon`: links to public Wikipedia article cards.
20. Chat library: New, reopen, rename and delete remain reliable and private;
    different questions produce distinguishable suggested titles.
21. On a compatible device, opt in to Conversational AI and try public snippet
    synthesis; on unsupported devices the app must degrade gracefully.
22. Discord playback activity after pause, resume, seek and PiP; browsing
    updates must remain disabled.
23. General regression: module search, streaming, favorites, downloads, and
    local library separation.

## Installation

Upload the provided full `Kinetiq-update.zip` to the GitHub repository root
and use the existing **import-kinetiq-zip** workflow to unpack it after the
uploader confirms `Okay`. Confirm the imported commit includes the new player
styles and `docs/KINETIQ_M05C_IPHONE_HANDOFF.md`, then run the normal Xcode
test/unsigned-IPA workflow. Do not mistake a successful archive import for a
successful Swift compile or playback test.

## Follow-up ideas (not in this build)

- Optional per-style auto-hide timing, one-handed placement, and Quick Deck
  position presets for different phone sizes.
- A small on-device player layout playground showing real safe areas, text
  sizes and landscape/portrait screenshots before shipping new styles.
- Search caching with source-specific expiry/limits, better AniList alias
  matching and multilingual encyclopedia routing.
- A user-approved, on-device AI action toolbox for opt-in local library tasks;
  never grant remote websites authority over private data or playback.
