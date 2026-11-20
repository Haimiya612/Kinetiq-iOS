# Kinetiq M05A — iPhone handoff

Source baseline: uploaded GitHub snapshot commit `446b37398ef906cb657095736d1e679930db0226`,
the verified M04 R3 project. This cumulative ZIP retains the full Xcode project,
all existing Swift sources, tests, resources and current `project.pbxproj`.

## 20 November 2026 — CI compiler hotfix

The full-source re-import now includes an explicit `return` from
`KinetiqSubStudioCaptionStack.line(_:color:label:)`. This fixes the
`KinetiqSubStudio.swift:292` opaque-return-type error seen in the first
M05A GitHub Actions test build. Static contract tests pass locally; rerun
the Xcode workflow to validate macOS compilation and iOS simulator tests.

## Test on iPhone (PASS / FAIL / N/T)

1. **Player error escape:** Start a module episode that has no accepted stream.
   Before any landscape rotation, both `Close` (top-left) and `Close Player`
   (error actions) should dismiss the player. Copy Diagnostics still works.
2. **Portrait header:** During initial resolution or failure, the title,
   clock, Wi-Fi and player actions should not occupy each other's hit targets.
3. **SubStudio selection:** Choose the second and third tracks from a module
   exposing several caption files. Scroll the full-height picker and verify
   that one file cannot be selected in both slots or duplicate primary.
4. **Subtitle readability:** Toggle Soft Colors and Color Intensity; display
   three timed caption tracks simultaneously. No visibly colliding lines,
   including after rotating / opening the player Playback menu.
5. **Player appearance:** In Settings → Playback → Player appearance, try
   Signature, Cinema and Focus, confirm the preview changes and the actual
   player responds without restart. Try the same in player Playback settings.
6. **PiP return:** With the new toggle **off**, return to Kinetiq and PiP should
   continue floating. With the toggle **on**, reopening Kinetiq should stop PiP
   and restore the video in the player. Check embedded subtitle restoration.
7. **Search rank:** Search "Blue Box" across all trusted sources. Exact titles
   appear before titles containing those words, even as workers finish.
8. **Source suffix:** Search "Blue Box AniPM" or another installed source name.
   Confirm the query sent to modules is "Blue Box", the preferred provider is
   queued first, and all sources remain represented when available.
9. **Duplicates:** Same anime on two sources should remain two choices. The
   same source reporting an identical `(id, href)` twice should show one card.
10. **Find similar:** Use a result's button, confirm the exact AniList title
    match and genre, then tap a related anime to search installed sources.
    If no exact public match exists, a clear limitation message should appear.
11. **Brain chats:** Turn on "Save chats on this iPhone", ask several questions,
    leave/reopen Kinetiq Brain, verify the transcript persists. Clear it after
    the Yes/No-style confirmation. With the toggle off, new messages should
    not be written to local chat storage.
12. **Discord:** During normal playback, a Pause should show the paused state.
    Tap seek forward 10 seconds at least 4 times quickly; the heading should
    stop rotating and queue one settled presence update. Close the player or
    reproduce a never-started stream and check that stale video activity clears.
13. **Smoke/regression:** Theme selector, module install/update, progress,
    PiP subtitles, episode skip/confirmation, local library independence, and
    all four Home/Favorites/Downloads/Settings tabs still work.

## Scope and limitations

- iOS cannot programmatically send the user to the Home Screen. An app-owned
  mini-player while browsing Kinetiq requires a persistent app-level playback
  host; it is **not** included here.
- iOS system Picture in Picture does not render arbitrary SwiftUI subtitle
  stacks; only compatible native captions / video-embedded text can appear.
- Automatic speaker diarization and per-character coloring are **not** in
  M05A. Accurate speaker assignment needs a reliable transcript/diarization
  model plus a user-visible opt-in and an editable speaker map.
- Cross-source watch-progress transfer is **not** in M05A: matching only a
  title can silently map the wrong season, episode or dub/sub track.
- The ambient-light effect from live video pixels and full Brain permissioned
  action tools are **planned M05B** work, not hidden features in this ZIP.
- Native Xcode compilation and live PiP/RPC verification require macOS and the
  owner's device. No simulator build is claimed here.
