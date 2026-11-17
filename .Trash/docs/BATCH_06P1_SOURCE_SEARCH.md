# Batch 06P1 — Faster cross-source search and Favorites source choice

**Status:** Swift implementation candidate, not yet compiled by Xcode or
verified on an iPhone. Prepared on 16 November 2026 from `b5e832c`, with
the previous uncommitted 06O season-download changes retained.

## What the user can do

1. Open **Favorites**. Every saved title in list, poster grid and themed
   spotlight has a change-source icon.
2. Choose **Find on All Sources**, or select one installed/trusted video
   module under **Search One Source**.
3. Kinetiq fills the search query with the saved title, searches immediately,
   and shows results with their original module name attached.
4. Tap the desired result to open its source-specific title details and watch
   with that module. Nothing is automatically treated as the same episode.
5. From a normal anime details page, use **Watch with another source / Search
   all modules**. If the original saved module is unavailable, the Favorites
   fallback also offers **Find Another Source**.

## Search performance and result policy

- Previous implementation: groups of three sources but **one query at a time**
  inside each group, with additional work sometimes deferred until scrolling.
- New implementation: a rolling pool of **four simultaneous module workers**.
  Each completed worker immediately frees its slot for the next source, so a
  slow or failing module doesn't block the other three. Results appear as
  sources finish; a source counter and failure count remain visible.
- Search cancellation uses a per-request token and cancels outstanding tasks.
  Results arriving for an old query are ignored.
- **No title-based deduplication, result-ID merging or 48-item UI limit.**
  Every decoded valid result from the bounded module response is displayed;
  even identical titles/IDs can appear more than once and carry their own
  source association. Local saved-title search no longer stops at ten cards.
- Search operates only against locally installed, trusted video modules.
  Untrusted or missing modules do not execute JavaScript; the user can manage
  modules in Settings. Modules themselves may return partial search results,
  enforce their own pagination or fail on live sites. Kinetiq cannot display
  media a provider never returns, but it won't silently hide results by title.
- No automatic cross-module watch-position transfer, favorite migration or
  fuzzy title-to-episode equivalence is performed. That belongs to the later
  Verified Unified Media Identity design, with confidence checks and consent.

## Manual acceptance on iPhone

- [ ] Search a title returned by multiple modules and confirm every returned
  version appears separately with the correct module label.
- [ ] Search one module only; confirm no other source returns a result.
- [ ] Use a title with identical names from different modules and verify both
  entries are tappable and resolve independently.
- [ ] A slow/failing source doesn't prevent other results from appearing.
- [ ] Change the search text while workers are running; no stale results leak
  into the new query. Leave search and return; previous workers are stopped.
- [ ] In Favorites list, poster grid and spotlight, tap the source icon. Open
  all-source and one-source search, then watch a selected matching result.
- [ ] Reopen the original favorite and verify its original source, progress,
  watched markers and saved downloads remain untouched.
- [ ] Disconnect/uninstall a saved title's original module; verify the error
  path offers an alternate-source lookup without automatic content mixing.
- [ ] Test many search results: scrolling remains responsive and no module
  results vanish because of name/ID duplication.

**Build note:** No new Swift source file was added; the original `.pbxproj`
needs no edits. The changes are in `HomeView.swift`, `MainTabView.swift`,
`ModuleRuntime.swift` and `ModuleDiscoveryContractTests.swift`.
