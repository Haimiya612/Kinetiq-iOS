# Batch 03D — Episode Progress and Continue Watching

Base: [`8efde5e117243ab85e5bb1f86f254d4aeef8f1d5`](https://github.com/Haimiya612/Kinetiq-iOS/commit/8efde5e117243ab85e5bb1f86f254d4aeef8f1d5), `main`, 6 November 2026.
GitHub was rechecked before packaging and still pointed to this commit.

Status: implemented in replacement source, awaiting Xcode and iPhone validation.

## Scope and implementation

The 03C baseline saved one episode/language position per title. Selecting another
episode could discard that position, and the Continue Watching filter did not
exclude completed episodes. This batch extends the existing collection and
connects episode progress to details and the existing player.

| Area | Change |
| --- | --- |
| Persistence | Keep a progress record for each episode and language inside its existing source-specific title record. |
| Migration | Decode the existing collection key and promote the last valid saved position into episode history. Retain Favorites, metadata, and source names. |
| Completion | Mark watched at 97% or a successful player end event. Late callbacks cannot undo completion. |
| Details | Show watched counts, Sub/Dub progress, episode-number search, watched filters, and per-language watched actions. |
| Main action | Resume the most recent available unfinished episode, or play the first unwatched playable episode in provider order. |
| Continue Watching | Select an unfinished episode per title. Hiding its card preserves Favorites, recents, progress, and artwork. |
| Recent Episodes | Removing an entry hides its recency and Continue Watching card while retaining underlying episode progress. |
| Player | Keep same-language recovery position; use separate saved positions for Sub/Dub. Save on pause, completed seeks, app inactivity, handoff, and close. |

Watched filters count an episode watched if an available Sub or Dub version is
completed. Each language still has its own resume position and watched mark.
“Mark Unwatched (Reset Progress)” clears only that episode/language's position.
Replaying a watched episode retains its watched mark unless explicitly reset.

The details recommendation uses watched state. The player's existing automatic
Next/Previous queue still follows the provider's episode order.

The existing 400-title limit remains. At most 8,000 episode records are retained
across those titles; older records are pruned first. Progress previously overwritten
by older batches cannot be reconstructed. Artwork remains in its separate cache.
Resume persistence requires a finite duration longer than five seconds and at
least three seconds of playback. Live and unknown-duration stream behavior still
requires device validation.

## Complete replacement files

| Repository path | Purpose |
| --- | --- |
| `Kinetiq/App/MainTabView.swift` | Collection model, migration, episode progress, continuation selection, card hiding. |
| `Kinetiq/Features/Modules/ModuleRuntime.swift` | Anime details UI; runtime, decoder, artwork, and browser code preserved. |
| `Kinetiq/Features/Modules/ModulePlayerView.swift` | Progress-saving and Sub/Dub handoff integration. |
| `KinetiqTests/TaglineSelectorTests.swift` | Existing tests plus 18 episode-progress regression cases. |
| `docs/ROADMAP.md` | Refresh current status; retain every original roadmap task. |
| `docs/CHANGELOG.md` | Unreleased entry with verification status. |

Add this document as `docs/BATCH_03D.md`. All four Swift files already belong to
their Xcode targets. No `project.pbxproj` changes or new Swift target memberships
are required.

## Verification performed

- Retrieved 34 text files at the pinned commit and verified their Git blob hashes
  before editing. Binary app artwork was not changed.
- Parsed all 20 Swift source/test files using tree-sitter 0.26.0 and
  tree-sitter-swift 0.7.4: no syntax error or missing-token nodes.
- Passed 45 syntax and structural consistency checks, plus ZIP integrity and
  full-file SHA-256 checks during packaging.
- Confirmed the original 411 roadmap checkboxes remain with their original state.
- Verified all 82 declared Xcode identifiers are unique and references resolve;
  checked existing Sources membership for each changed Swift file.
- Compared the navigation, global Favorites layout, runtime bridge, handlers,
  stream decoder, artwork cache, browser, episode queue, details resolution,
  local player/library, module installation, CI files, and release notes against
  the base. Their implementation is retained (the details file gains a final newline).

Syntax parsing is not Swift type checking. No Swift compiler or Apple SDK was
available in this environment. The 18 XCTest cases were added, not executed.
The full iOS app was not compiled or linked, and no simulator or physical-device
tests were run. Full GitHub Actions debugging remains deferred to stabilization.
No new claim of third-party module playback compatibility is made by this batch.

The accompanying `VERIFICATION.json` lists the checks and their limits.

## iPhone acceptance checklist

Use an existing 03C installation so migration is exercised without resetting its data.

1. Confirm existing Favorites, original source names, recent selections, and the
   last saved position survive the update and another app launch.
2. Play episode 1 Sub to about 90 seconds, episode 2 Sub to about 180 seconds,
   then return to episode 1. Repeat after closing and relaunching the app.
3. Play episode 1 Dub to a different position. Switching Sub/Dub should restore
   each version's own position, including after a server change.
4. Pause, seek backward, and close the player. Reopening should use the latest
   accepted seek position. Repeat after leaving and returning to the app.
5. Reach 97% or the end of an episode. Its watched badge should appear and that
   completed episode should leave Continue Watching. Another unfinished episode
   from the same title may still provide a card.
6. Mark Sub watched manually, then mark it unwatched. Only Sub should reset;
   Dub progress should survive. Do this again after relaunching.
7. Hide a Continue Watching card. Favorites, recents, artwork, and resume in
   details should remain. Actual playback should make the card eligible again.
8. Remove a Recent Episodes entry and reopen the anime through its source or
   Favorites. Its underlying episode resume positions should still be available.
9. Search an episode number and use All/Unwatched/Watched. Check long lists,
   empty results, large text sizes, and VoiceOver labels on iPhone.
10. Check the same-looking anime/episode IDs from two sources remain independent.
11. Exercise server recovery, failed episode resolution, previous/next, audio,
    subtitles, PiP, and AirPlay without changes to the existing player appearance.
12. Confirm Home, Favorites, Downloads, and Settings remain the four tabs; smoke
    test local import, local playback, local Favorites, and the local queue.

Run `ModuleEpisodeProgressTests` with the project's existing XCTest target during
stabilization. Do not mark the corresponding roadmap requirements complete until
their build, integration, and device checks pass.
