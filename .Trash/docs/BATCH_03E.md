# Batch 03E — Module Subtitle Tracks

Prepared on 6 November 2026 from GitHub `main` commit
`0aa310df2341927841facad5f82b22a8992a1a08` (Batch 03D).

Status: implementation prepared; Swift syntax parsing and source-consistency checks
passed. No Swift compiler, Apple SDK, simulator, or physical device was available
for this batch. The new XCTest cases have not been run. Full GitHub Actions build
debugging remains deferred to stabilization.

## Change and scope

The baseline module player lists embedded AVPlayer subtitles but discards external
subtitle descriptors in stream results. This batch retains optional SRT/WebVTT
tracks, lists them under **From source** in the existing Subtitles panel, and
renders the selected track as text over the in-app video surface.

**Off** disables external and embedded tracks. Selecting an embedded track clears
the external selection. The panel includes loading, a safe error message, and
Retry Subtitles. Old requests are cancelled and their results invalidated when a
new track or stream is selected, Off is chosen, or the player closes.

The external language preference stays in memory for the current player session.
A new episode/server attempts to match the track identity, then language or label.
If no match is available, the panel asks for another track or Off; it does not
silently pick an unrelated language. This preference is not an app-wide setting.
An explicit Off selection remains Off across stream changes.

The existing fullscreen controls, four tabs, source names, JavaScript bridge,
module trust/install flow, local subtitle implementation, Favorites, and Batch 03D
progress handling are retained. No project identifiers, memberships, workflow,
release version, or `project.pbxproj` are changed.

## Complete replacement files

| Repository path | Change |
| --- | --- |
| `Kinetiq/Features/Modules/ModuleRuntime.swift` | Optional subtitle descriptors, per-stream metadata, and cookies scoped to the subtitle URL |
| `Kinetiq/Features/Modules/ModulePlayerView.swift` | Existing-panel integration, cue overlay, playback timing and stream cleanup |
| `Kinetiq/Features/Library/ExternalSubtitleSupport.swift` | Remote loader, request policy, timeline and selection controller; local implementation retained |
| `KinetiqTests/TaglineSelectorTests.swift` | 18 new regression cases; all previous cases retained |
| `docs/ROADMAP.md` | Current focus and pending Batch 03E verification; all prior checkboxes retained |
| `docs/CHANGELOG.md` | Unreleased Batch 03E entry |
| `docs/BATCH_03E.md` | This new implementation/acceptance record |

New Swift types live in files that are already members of the app/test targets.
Replace the files at these exact paths; do not create duplicate Swift files.

## Optional metadata schema

This is a **Kinetiq extension**, not a claim that Synthetiq officially standardizes
these fields. The retrieved public Synthetiq guide documents direct URLs and
stream results but does not specify external subtitle descriptors. Existing
sources may return no such tracks. This batch does not modify modules or invent
subtitle URLs; real-source compatibility still requires testing actual output.

An illustrative `extractStreamUrl` result is:

```json
{
  "streams": ["Main", "https://cdn.example.invalid/episode.m3u8"],
  "subtitles": [
    {
      "url": "https://captions.example.invalid/episode-en.vtt",
      "label": "English",
      "language": "en",
      "format": "vtt",
      "headers": {"Referer": "https://source.example.invalid/"}
    }
  ]
}
```

The example domains are placeholders, not working playback fixtures.

Supported descriptors can be supplied at the result root or inside an individual
stream dictionary. Server-specific tracks precede global tracks; identical URL,
language and effective-header combinations are deduplicated. Existing direct URL,
flat label/URL pairs and alternative-server inputs still work without subtitles.

| Field | Accepted forms |
| --- | --- |
| Track container | `subtitles`, `tracks`, or `captions`: array, single descriptor/string, or label-to-descriptor/string map |
| URL | `url`, `file`, `src`, or `href`; a string track is also accepted |
| Label | `label`, `name`, or `title`; otherwise language or “Source subtitles” |
| Language | `language`, `lang`, or `srclang`; normalized lowercase with hyphens |
| Format | `format`, `mimeType`, or `type`: SRT/SubRip or VTT/WebVTT aliases |
| Kind | Absent or `captions`, `subtitles`, `subtitle`; other kinds are ignored |
| Headers | Optional string-to-string `headers` on the subtitle descriptor |

Relative URLs resolve against the installed module's base URL, not the video URL.
Unknown filename extensions may be checked by response MIME type/content. Explicit
unsupported formats, thumbnail tracks, and invalid URLs are ignored without
invalidating a usable video stream. Only the first 24 valid tracks per stream are
retained; inspection is bounded to 48 candidates per container key.

## Download and timing behavior

- Fetch only the selected track, with an ephemeral session and no shared cookie,
  credential or response cache. Subtitle URLs, bodies and selection preferences
  are not written to app persistence.
- Require HTTPS without embedded credentials or fragments. Inherit video headers
  only when the subtitle has the same origin. Descriptor-specific headers remain
  available for subtitle hosts; runtime cookies are captured for each actual URL.
- Build fresh redirect requests. Cross-origin redirects drop source headers and
  cookies; same-origin cookie forwarding still respects domain and path. An HTTP
  downgrade is rejected. A subtitle CDN needing headers after a cross-origin
  redirect may therefore require a direct track URL from its module.
- Limit the response body incrementally to 2 MiB, with a 20-second request timeout
  and a 30-second resource timeout. Limit accepted parsed output to 20,000 cues.
- Reuse the existing SRT/WebVTT parser on a utility task. Display plain text;
  authored positioning, regions, font styling, and WebVTT styling are not rendered.
- Drive the overlay from the current AVPlayer time on a 0.2-second observer and
  update after completed seeks. Recompute active cues for backwards seeks and
  overlaps. Display is bounded to eight simultaneous cues/eight visible lines.
- Clear the old stream's cue state when loading the replacement player item, and
  suppress captions while restoring its saved position. During source resolution,
  the currently loaded video retains its own subtitle state until handoff.

External subtitles in this batch are an in-app overlay. They are hidden while
system PiP is active and are not part of the remote AirPlay video. Existing native
embedded subtitles keep their AVPlayer selection path. Native external-subtitle
PiP/AirPlay rendering, timing-offset controls, persistent language preferences,
appearance customization, ASS/SSA/TTML, and HLS subtitle playlists remain future
work. No related roadmap feature has been removed or marked complete.

## Verification performed

- Parsed all 20 Swift files with tree-sitter 0.26.0 / tree-sitter-swift 0.7.4:
  no syntax error nodes. This is not Swift type checking or an iOS build.
- Passed 59 static checks covering syntax, retained source sections, unique added
  declarations, existing target membership, project references, roadmap retention,
  test presence and patch whitespace.
- Confirmed all 82 project identifiers resolve and are unique, with
  `project.pbxproj` byte-for-byte unchanged.
- Retained all 416 pre-existing roadmap checkbox lines unchanged.
- Retained the baseline local subtitle implementation and all existing tests.
- Added 18 XCTest cases for legacy stream decoding, optional metadata, header and
  cookie scope, redirect policy, cue boundaries/overlaps, malformed bodies,
  cancellation, stale results, stream changes, Off and error sanitization.

The XCTest cases are **added, not executed**. Download behavior, Swift/SDK type
compatibility, iOS layout, source compatibility and actual playback are unverified.
The downloadable batch also contains `VERIFICATION.json` and `SHA256SUMS` as
optional delivery records; neither is an app input or a file to add to an Xcode
target.

## Acceptance still required

1. Compile and link the app and run the existing test target, including
   `ModuleRemoteSubtitleTests`, in the project's Xcode configuration.
2. Use a trusted module that actually returns a reachable SRT or WebVTT descriptor.
   Confirm the source track appears, loads, displays and can be disabled. A source
   returning no descriptors should retain its normal embedded/empty-track behavior.
3. Exercise pause/resume, rate changes, forwards/backwards seeks, overlapping cues,
   control visibility, rotation and accessibility on iPhone. Confirm no old cue
   appears during saved-position restoration.
4. With a slow subtitle endpoint, switch tracks, choose Off, select another
   episode/server and close the player. Confirm late responses never restore old
   captions and a new stream selects only a matching language/label.
5. Test authenticated tracks, same/cross-origin redirects, rejected HTTP redirects,
   404/HTML responses, oversized bodies, retry and connection loss with controlled
   endpoints. Policy unit tests alone do not validate URLSession integration.
6. Check embedded subtitles, existing local imports/selection, player menus,
   server recovery and Batch 03D progress/Continue Watching for regressions.
7. Check the advertised PiP/AirPlay limitation: external overlays are not expected
   in the system/remote video. Do not mark external PiP subtitle support complete.

## References inspected

- Public module guide: <https://synthetiq.uk/modules/>. Its linked full contract
  repository path returned 404 during this work; it was not treated as verified.
- Apple URLSession incremental response API:
  <https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:)>
- Apple redirect delegate API:
  <https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)>

These references informed the implementation; they do not verify a particular
installed module's subtitle output or replace the acceptance steps above.
