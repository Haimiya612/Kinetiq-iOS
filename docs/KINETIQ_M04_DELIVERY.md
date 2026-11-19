# Kinetiq M04 — SubStudio and Player Comfort (18 November 2026)

This **cumulative full-source** package starts from the user's uploaded
`Kinetiq-iOS-main 5.zip`, retaining its M01–M03 work and contextual
M03/M04 skip-marker additions. It does not modify GitHub. App version remains
**0.3.0**, minimum iOS **17.0**, Swift language mode **5**.

## Delivered in this iteration

1. **SubStudio multi-caption tracks:** second and third independently loaded
   source-provided SRT/WebVTT subtitle timelines above the existing primary
   embedded or external subtitle. Each choice is cancellable and resets on
   server/episode changes to prevent wrong-edition captions.
2. **Japanese reading assistant:** optional romanized line for a provided
   Japanese subtitle, using Apple's language-aware token transcription.
   Proper nouns/kanji readings may be approximate. No fabricated transcript,
   machine translation, or unsupported ruby/furigana rendering is claimed.
3. **Transcript tools:** copy source-backed transcripts, search phrases,
   seek to a matching line, navigate previous/next cue and inspect a simple
   character-speed readability estimate. The estimate does not certify
   translation accuracy or timing synchronization.
4. **Independent sync:** ±10 seconds in 0.05-second steps for additional
   subtitle timelines, retained as an on-device preference. The existing
   primary subtitle timing setting remains intact.
5. **Foreground notifications:** one existing deduplicated notice banner
   now lives in a transparent, pass-through foreground UIWindow so fullscreen
   players and app modals do not bury it. History sheet remains reachable.
6. **Smart player controls:** Lock is one tap in the player header;
   More defaults to pinned Quick Deck, relevant actions, Action Finder, and
   SubStudio. All original advanced tools stay accessible after expanding
   *Show Advanced Tools*. No player action is deleted.
7. **Contextual Skip and Up Next polish:** original Kinetiq-designed glass
   prompts, more readable labels, artwork where provided, a countdown meter,
   and accessible close/Cancel/Play controls. Verified source-specific marker
   validation and Binge Guard logic remain unchanged.
8. **Transport safety:** only the Previous/Next controls beside Play/Pause
   ask for confirmation. Contextual Netflix-style Next Episode and autoplay
   still work directly, as requested.
9. **In-player episode handoff:** the full launch scene appears only until
   the *first* video frame. Later episode changes retain the same player
   surface with a compact loading card; session, PiP, subtitles and progress
   logic are left in place.

## Permanent M04 reference ledger — never remove

Each reference remains a requirement even where it is not yet delivered.
The 52 source references are retained here and in the original blueprints.

| State | Source reference IDs | Qualification |
|---|---|---|
| Present or enhanced | R067 R069 R071 R075 R083 R085 R086 R092 | Source-backed captions; styling, offsets, navigation, transcript, PiP disclosure |
| Partial / source-dependent | R068 R072 R073 R074 R078 R080 R087 R088 R089 | ASS/SSA, alignment, track details, translation, romanization and ruby need capability checks |
| Pending | R070 R076 R077 R079 R081 R082 R084 R090 R091 | Series priorities, retry, forced tracks, preview, scene modes, per-show profiles, sidecar repair |
| Present or enhanced | B069 B070 B071 B073 B074 B077 B079 B081 B083 B087 B089 B090 B093 B094 | Existing first track features plus second/third, phrase search and heuristic |
| Partial / source-dependent | B072 B078 B080 B084 B092 | Requires providers, configurable stroke, native CC metadata or Japanese reading support |
| Pending | B075 B076 B082 B085 B086 B088 B091 | Auto-sync, font family, repositioning, SDH/forced filters, mute captions, word dictionary |

## Limitations and compatibility

- Supplemental subtitles are visible only in Kinetiq's own player. Native
  iOS PiP cannot render arbitrary SwiftUI overlay tracks. Existing embedded
  subtitle and native-HLS bridge PiP behavior is preserved.
- Two or three languages require those subtitle tracks to exist and to
  match the current edition. No subtitle search service or AI translation
  is silently contacted. Existing caption export does not include stream
  URLs, cookies or authorization headers.
- This work is **not** a claim that every R/B feature is complete.
- No native Xcode compile, GitHub Actions run, or device playback test can be
  performed on this Linux workspace. iOS type checks remain required.

## iPhone acceptance checklist

1. Start a module install while a fullscreen player is open; notice appears
   above the player without blocking controls outside the banner.
2. Use Lock in the header; the player shows Unlock and ignores seek gestures.
3. Open More: quick actions are available immediately; advanced tools are
   collapsed but accessible on demand.
4. Tap the *central* Previous/Next arrows; confirm and cancel both. Tap the
   contextual Next Episode button; no confirmation should appear.
5. Change episodes; the player must remain mounted with a compact loading
   state instead of the original portrait launch scene.
6. Verify Skip Intro/Recap/Credits only appear after saved, exact-edition
   markers. Inspect the redesigned overlays and countdown.
7. With a source that exposes at least two valid SRT/VTT tracks, select second
   (and optionally third) SubStudio tracks; seek, rewind, and switch servers.
   The tracks must never drift onto a different edition unnoticed.
8. On Japanese subtitle tracks, turn Romaji on; compare readings with the
   spoken dialogue. If no supported reading is available, no fake line appears.
9. Search a phrase, jump to a cue, copy transcript, and adjust ± timing.
10. Test manual/automatic PiP, return captions, Local Library separation,
    source identity, Discord RPC, Home/Favorites/Downloads/Settings and offline
    playback. Report PASS/FAIL with the first failure's diagnostics.
