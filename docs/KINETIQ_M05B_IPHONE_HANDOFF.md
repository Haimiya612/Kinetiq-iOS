# Kinetiq M05B — Player, Brain and Presence Overhaul

Prepared 21 November 2026 from the complete M05A user-uploaded source.
M05A's 13 iPhone tests were reported PASS by the owner. M05B is **source
prepared / Xcode and iPhone tests pending**. App bundle identifiers, four
main tabs, all existing installed module identities, and `project.pbxproj`
remain unchanged.

## Import on iPhone

1. Download the **complete** `Kinetiq-update.zip` from this delivery.
2. Upload it at the **root** of `Haimiya612/Kinetiq-iOS` as exactly
   `Kinetiq-update.zip` and commit the upload to `main`.
3. Wait for **Actions → Import Kinetiq Source ZIP** to finish green. The
   importer replaces source, tests and docs, then commits the changes.
4. Manually start the normal **iOS CI** workflow. GitHub's built-in Actions
   token does not automatically trigger subsequent `push` workflows.
5. Only install and test the new IPA if the simulator build succeeds.

Do not use a patch-only archive with this importer: its source directory
replacement requires a complete tree.

## M05B iPhone checklist — PASS / FAIL / NOT TESTED

1. SubStudio: change the distance between stacked caption tracks from 0 to
   26 pt and confirm the visual distance changes.
2. SubStudio: set first, second, third and Romaji caption colors; leave the
   player and reopen it. All choices should persist.
3. SubStudio: Restore subtitle layout defaults returns track gap to 7,
   secondary Yellow, tertiary Cyan, Romaji Mint and Soft Colors on.
4. SubStudio regression: primary/secondary/tertiary track pickers, timing,
   subtitles in regular playback and existing external-to-PiP bridge.
5. Player Signature: compare with M05A. The familiar default remains intact.
6. Player Cinema: theatre console at bottom; transport, timeline, buttons,
   panel shortcuts, PiP, AirPlay and Close work.
7. Player Focus: central large play/pause button; skip/seek and panel controls
   remain reachable, including in portrait.
8. Player Studio: visibly different monitor HUD and transport arrangements.
9. Player Minimal and Classic: visual differences, tap targets and seek work.
10. Change player appearance in Settings and inside the player; relaunch,
    confirm it persists and local/module playback use the shared chrome.
11. Find Similar: enter several different genres/titles, scroll beyond the
    first page and check new results appear (without duplicate AniList IDs).
12. Find Similar: tapping a recommendation searches installed sources; no
    suggestion is claimed playable until an actual module returns a result.
13. Brain: enable Save chats, ask a question, start a new chat, switch back;
    messages and themed titles should persist after app relaunch.
14. Brain: rename and delete one conversation without losing the others;
    then test Delete All and the legacy single-chat migration if available.
15. Brain: with local saving disabled, new chat text must not be persisted
    after restart. On-device AI must not ingest prior transcripts on switch.
16. Brain: enter `anilist Frieren` or `rating Frieren`; check public rating,
    poster cards and original-source links when the API responds.
17. Brain: enter `web search Frieren`; verify Wikipedia sourced articles,
    image cards (if available), HTTPS links and clear empty-result handling.
18. Brain: configure a personal TMDB API Read Access Token, then enter
    `tmdb Frieren`; verify exact-title info and ratings if TMDB matches it.
19. Discord: with playback activity enabled, start an episode, pause, resume,
    seek repeatedly; check intent change and 30-second rapid-seek cooldown.
20. Discord: opt in to Browsing Presence. On Home, Favorites, Downloads,
    Settings, Brain, source catalogue and anime details, observe activity
    transitions from a second Discord account if the client accepts them.
21. Discord: playback overrides browsing; closing playback returns to the
    current browsing activity, and disabling browsing clears idle activity.
22. Regression: the four root tabs, search ranking/source isolation,
    favorites, offline episodes, module packages, PiP and subtitles remain usable.

## Known bounds

- **No native Xcode compiler in this delivery environment.** 36 existing
  Python contract tests pass, but this does not establish Swift compilation.
- Public research currently supports explicit **Wikipedia article lookup**,
  **AniList** and **TMDB** only. It is not unrestricted internet browsing.
  TMDB needs the owner's existing token stored in Keychain.
- Saved Brain transcripts are local and opt-in. Opening older chats does not
  silently feed them back into the on-device model.
- Discord's user-account Gateway presence is experimental, subject to
  Discord behavior and rate limits. Activity submission is not proof that
  other users can see it. Browsing is independently disabled by default.
- 06O season download queues, codec-dependent compression, true live video
  ambilight, in-app mini-player and automatic speaker diarization remain
  outside this M05B delivery.
