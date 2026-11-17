# Kinetiq All-in-One V2 — implementation and acceptance handoff

Date: 17 November 2026. App marketing version: **0.3.0 (unchanged)**.

## Import status and source-of-truth

The earlier **V1 full-source ZIP was delivered but, according to the owner,
not yet imported into GitSync, committed or tested on iPhone.** V2 continues
from the complete V1 code tree. The V2 **full-source** archive contains all V1
additions as well as the features listed below; it can therefore replace the
old unmodified source *without importing V1 first*. Do not install both full
source archives one after the other or create a nested `Kinetiq-iOS-main/`
directory. The optional **V2-only patch ZIP requires V1 as its base**, whereas
the **cumulative patch ZIP is relative to the original uploaded source**.

The source ZIP contains the original `Kinetiq.xcodeproj/project.pbxproj`,
resources, original actions configuration, tests, and the two unmodified
research blueprints. Its four main tabs are still Home, Favorites, Downloads,
Settings. Source labels, module runtime, native player/PiP/subtitle bridge,
local media separation and current Discord RPC files are unchanged.

## V2 working scope — added above V1

| Capability | UI entry | Concrete behavior | Limits |
|---|---|---|---|
| Expanded Action Finder | Module Player → More → Find a player action | 48 command choices, each routed to existing player APIs and capability-disabled when unavailable. New fine seeking, fractional speeds, fit/fill, volume steps, subtitle retry, autoplay toggle | Some commands depend on current stream and existing AVPlayer capabilities; no unsupported codec claims |
| Customizable Quick Deck | Module Player → More → Your Quick Deck → Customize; Settings → Playback | Persistent eight-slot maximum, actual player command buttons; add/remove/reorder, default six shortcuts | Per-device settings only; module player only; changes do not alter Discord settings |
| Spoiler Shield | Streaming title details → Episodes → eye icon; Settings → Anime Discovery | Off/Unwatched/Strict. Unwatched hides stills, episode names and summaries for episodes not marked watched. Strict hides all episode metadata, synopsis and sensitive detail sections. Per-episode reveals last only for that visit | Relies on local module watched state; does not filter remote sites, notification previews or third-party Discord activity. Off by default to retain previous UI |
| Study/Cinema presets | Module Player → Playback | Study sets 0.75× and 5-second Quick Deck seek. Cinema sets 1×, aspect fit and 10-second Quick Deck seek | Does not modify subtitle selections or force third-party codecs |
| Stop at local clock time | Module Player → More → Sleep Timer | Picks next matching local clock time (even tomorrow), schedules existing session-scoped pause timer | Round-up to next minute; active player session only; not a system background alarm |

## Privacy, control and compatibility contracts

- Quick Deck saves only `KinetiqPlayerAction` identifiers, never a player,
  stream URL, server credentials, diagnostic payload or token. Unknown IDs
  are discarded; duplicate IDs and more than eight pins are rejected.
- Every Quick Deck action uses the same capability checks as Action Finder.
- Spoiler Shield never suppresses Play, Sub/Dub, download, progress management
  or source selection; it masks only candidate spoiler media/metadata.
- Off is the initial spoiler setting; no old user's title is suddenly hidden.
- Nothing is sent to a service to evaluate spoiler depth. Sensitive snippets
  are revealed only after an explicit tap, and temporary reveals reset when
  the detail view closes or the protection level changes.
- No changes to the experimental Discord RPC transport or settings.
- No GitHub remote modifications, access changes or version upgrade.

## Test coverage and known verification gaps

- Swift XCTest: `KinetiqPlayerPersonalizationTests.swift` covers pin limits,
  order, persistence, action count/uniqueness, spoiler-depth decisions and
  explicit reveal bypass. These tests are registered in the Xcode test target.
- Python integration checks in `tests/test_foundation_wiring.py` cover the two
  new source references, UI wiring, version lock and basic privacy invariants.
- Linux can verify tests that do not require SwiftUI, SHA-256 and archive
  integrity. It does **not** verify iOS compiler diagnostics, playback,
  animation, VoiceOver, cold-launch settings or the Discord regression.
- The owner elected to postpone the existing Actions Run repair; V2 is a
  development package, not a CI-pass/IPA certification.

## iPhone acceptance sequence (once imported)

1. Launch and traverse all four tabs without crashes. Check local-library
   separation, source picker, module playback, PiP and external subtitles.
2. Compare Discord Rich Presence before/after with the prior build.
3. Module Player → More → Action Finder. Confirm 48 choices; each enabled
   action should affect current playback, and unavailable ones should be
   disabled. Test subtitles retry with/without external track selected.
4. Pin eight Quick Deck actions, reorder two, close/reopen player and app;
   confirm persistence. Try pinning a ninth; it should be disabled.
5. From a streaming detail page, enable Unwatched protection. Check that
   an unplayed episode's poster/title/synopsis disappears but Play/Download
   remain functional. Reveal one card; no other card should reveal.
6. Mark that episode watched; in Unwatched mode its metadata becomes visible.
   In Strict mode it hides again, and series synopsis/trailer/related sections
   require user reveal. Turn Off and confirm original presentation.
7. Select Study then Cinema presets and check AVPlayer speed/aspect/seek step;
   set stop-at 2 minutes ahead, confirm playback pauses; cancel it.
8. Run Swift XCTest and existing unsigned IPA workflow when ready for the
   requested Actions Run repair. No new Xcode build success is claimed here.

## Open core blueprint milestones — still pending

The blueprints remain the **backlog**, not an implementation certificate.
Automatic encrypted account-based cross-device sync, live synchronized watch
rooms with presence/chat/reactions, universal frame-accurate source matching,
offline audio/subtitle normalization, complete ASS rendering, advanced voice
assistant control and the rest of the proposed hundreds of controls all
need engineering, test devices, service contracts or explicit media rights.
The previously added manually exported Sync Vault, shareable Watch Plans,
native HEVC Quality Forge, grounded AI/Apple Intelligence features, Scene
Passport and Recovery Center remain intact in this V2 tree.
