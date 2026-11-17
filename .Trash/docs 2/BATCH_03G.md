# Batch 03G — Subtitle Preferences

This batch covers Phase 2 playback and Phase 11 personalization. All five 03F
repository files matched GitHub `main` at commit `d065edd9f23347f9f37bbdbb6e9d185909a2ab5c`.

## Player behavior

Open **Settings → Playback → Subtitles** to choose a default, subtitle size, text
colour and background. The preview uses the same caption view as module playback.
The app stores these four preferences in UserDefaults, so they can be read the next
time a player opens. Reset appearance leaves the language choice intact.

| Choice | Behavior |
| --- | --- |
| Automatic | Uses AVPlayer's automatic embedded selection. Source tracks can be selected from the player. |
| Off | Clears optional captions. A stream that requires an embedded track keeps that track. |
| Language | Matches the saved language against embedded tracks in local media and embedded/source tracks in module playback. Missing matches leave optional captions off. |
| Manual choice in the player | Takes precedence for this session. On item changes, embedded choices match by track metadata and manually selected source tracks use the existing session preference. |
| Use saved subtitle default | Clears the session override and evaluates the current item's tracks again. |

Common languages appear in the picker. **Other language** accepts a tag such as
`en-GB`. Matching normalizes case, underscores and common language aliases.
An exact tag takes priority over a primary-language fallback, and equal matches
prefer an embedded track. Conflicting explicit scripts such as `zh-Hans` and
`zh-Hant` do not match. Unknown tracks can still be selected manually.

Selecting a language in Settings can fetch a matching source caption file once
the module player's media selection metadata loads. A settings-based source
choice is evaluated again on the next item. An explicit manual source choice can
carry across items according to the existing 03E matching policy. The existing
subtitle transfer limits and cancellation handling apply to both routes.

The source overlay uses the selected appearance for SRT and WebVTT text. Local
and module AVPlayerItems receive native style rules for WebVTT. Default fields
leave that part of native styling to the system. Other embedded formats follow
their native presentation. The selected module Sub/Dub stream controls audio and
episode resolution independently of caption language.

## Verification

All 20 Swift files were syntax parsed and the project file and target memberships
were checked against the pinned commit. Seven XCTest cases cover persistence,
invalid values, language and script matching, manual priority and the distinction
between a saved default and a manual source choice. Swift type checking, XCTest
execution, Xcode compilation and physical-device verification are pending. Full
Actions debugging remains deferred.

For acceptance on iPhone:

1. Save a language and appearance, close the app and reopen Settings. Confirm
   the saved values and preview, then reset appearance and confirm the language.
2. Play a local file with embedded tracks, then a module stream with native and
   source tracks. Try an exact match, a regional fallback, missing tags and a
   missing language. Check that optional captions stay off on a miss.
3. Select another track or Off while captions are loading. Change episode/server
   or local queue item, then choose **Use saved subtitle default**. Check the
   selected row and visible text after each handoff, including a required native group.
4. Compare the source SRT/WebVTT overlay, embedded WebVTT, and another embedded
   format. Exercise native accessibility overrides on the device and verify that
   the selected Sub/Dub stream, HLS quality and playback position are preserved.

Local SRT/WebVTT import, storage and parser helpers exist in the baseline. The
local player currently exposes its embedded tracks. The roadmap tracks the
missing connection to the file importer. External captions in system PiP or
remote AirPlay video still require a separate rendering implementation.

Apple documents the native style scope and supported attribute values. [WebVTT style rules](https://developer.apple.com/documentation/avfoundation/avplayeritem/textstylerules) · [Size](https://developer.apple.com/documentation/coremedia/kcmtextmarkupattribute_basefontsizepercentagerelativetovideoheight) · [Foreground colour](https://developer.apple.com/documentation/coremedia/kcmtextmarkupattribute_foregroundcolorargb) · [Background](https://developer.apple.com/documentation/coremedia/kcmtextmarkupattribute_backgroundcolorargb)

Apple also documents returning a group to automatic selection and observing item changes. [Automatic selection](https://developer.apple.com/documentation/avfoundation/avplayeritem/selectmediaoptionautomatically(in:)) · [Language tags](https://developer.apple.com/documentation/avfoundation/avmediaselectionoption/extendedlanguagetag) · [Selection changes](https://developer.apple.com/documentation/avfoundation/avplayeritem/mediaselectiondidchangenotification)
