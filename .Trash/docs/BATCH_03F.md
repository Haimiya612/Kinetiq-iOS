# Batch 03F — HLS Quality Preferences

Owning phases: **2 — Playback & Player Experience** and **6 — Streaming Engine**.
Prepared from GitHub `main` commit `ecb805cc997c7b5c9989619446ecc5f46608a566`.

Status: implementation prepared; syntax/source checks performed. Swift type
checking, Xcode compilation, XCTest execution, real-source playback and iPhone
acceptance have not been performed here. Full GitHub Actions debugging remains
deferred as requested. No roadmap feature or phase is certified complete.

## Delivered behavior

The existing Playback panel gains a Video Quality section. For an AVURLAsset
with multiple advertised video resolutions it shows Auto and “Up to …” choices,
dimensions, and known peak bitrates. It observes the current item's presentation
size and displays it separately from the selected preference. The More panel
prefers that current presentation size over its earlier track-size fallback.

Selection updates `preferredMaximumResolution` and, when metadata permits, a
`preferredPeakBitRate` on the existing AVPlayerItem. It does not replace the item,
seek, start/pause playback, or alter selected audio/subtitles. Auto clears both
preferences. A new episode, server, or retried player item starts in Auto.

These are **preferred limits, not exact rendition locks**. AVPlayer can adapt
below the requested resolution; buffered media can delay a visible change. Apple
also documents that bitrate consumption may exceed a requested value when the
system cannot meet it. The interface does not promise a strict download limit or
claim the selected resolution is currently being displayed.

Discovery uses `AVURLAsset.load(.variants)` on the existing asset. No parallel
playlist fetcher, variant-URL switch, HLS rewrite or new credential-forwarding
path is introduced. Existing module headers/cookies and media-selection groups
remain managed by the existing asset/player path.

Empty, single-resolution or unusable metadata produces no manual options.
Audio-only metadata is omitted. Fixed-quality MP4 and unsupported assets therefore
do not gain invented resolution choices. Metadata failure has a separate retry
state and does not invoke playback/server recovery.

## Bounds and lifecycle

- Inspect at most 256 native variant descriptors; expose up to 32 distinct valid
  resolutions, sorted by pixel area. Do not retain variant URLs in quality models.
- Reject non-finite, zero, negative or out-of-bound dimensions before integer
  conversion. Fractional presentation dimensions round up. Keep portrait sizes
  in their original orientation; the short edge supplies the compact “p” label.
- Merge codecs/frame rates sharing a resolution. Keep the highest known peak,
  but leave the group peak unknown if any member has missing/invalid peak data.
- Calculate a bitrate preference from all known groups fitting the selected
  resolution bounds, including lower-resolution/high-bitrate encodings. If any
  eligible peak is unknown, use only the resolution preference.
- Allow 12 seconds for discovery UI state before offering retry. Cancel the
  wrapper task and invalidate its request token; never call `asset.cancelLoading()`
  on the asset shared with playback. This is not a hard network-resource timeout
  for AVFoundation's underlying loading operations.
- Ignore late discovery success/failure after item changes, timeout or stop.
  Remove presentation-size observation and clear preferences on teardown.
- Keep all preference state in the current player session. Nothing new is written
  to Favorites, history, module storage or app settings.

## Files

| Path | Action |
| --- | --- |
| `Kinetiq/Features/Modules/ModulePlayerView.swift` | Replace completely; quality UI, metadata model and controller use its existing target membership |
| `KinetiqTests/TaglineSelectorTests.swift` | Replace completely; retain baseline tests, restore 18 missing 03E cases, add 20 quality cases |
| `docs/ROADMAP.md` | Replace; retain all previous tasks, add phase progression and explicit quality follow-ups |
| `docs/CHANGELOG.md` | Replace; add the unreleased 03F entry |
| `docs/BATCH_03F.md` | Add this record |

The latest GitHub baseline did not include `ModuleRemoteSubtitleTests`. This batch's
complete test replacement includes the earlier 03E tests, so no separate 03E test
copy is needed. App subtitle implementation files already match the delivered 03E
versions and are not replaced again.

`project.pbxproj`, all source/module names, runtime contracts, existing player
controls, local playback, module subtitles and Batch 03D progress logic remain
unchanged. No new source-file membership or identifier is required.

## Verification and remaining scope

All 20 Swift files pass tree-sitter syntax parsing. Source checks compare the
baseline against GitHub blob hashes, retain all 420 existing roadmap checkbox
lines, validate the 82 existing project identifiers/references, verify file target
membership and check whitespace. The ZIP contains a detailed `VERIFICATION.json`.
Syntax parsing is not a Swift compiler or SDK compatibility check.

Twenty new XCTest cases cover catalogue normalization/bounds, missing peaks,
lower-resolution bitrates, portrait/fractional dimensions, preference reset,
unsupported assets, retry, timeout, teardown and stale results. Eighteen 03E cases
are restored. **Neither set was executed here.** Mock loaders do not establish
real AVFoundation discovery or network behavior.

The variant list can include encodings that a device cannot play. This batch does
not offer codec/HDR/frame-rate locks or claim that every advertised variant is
playable. Exact rendition locking, bitrate-only ladders, persistent quality
defaults and external PiP/AirPlay subtitle rendering remain separate work. The
local-file player does not gain a quality menu in this batch.

The roadmap now lists gates for all 12 phases. Near-term player work is followed
by a stabilization checkpoint and an audit of remaining Phase 3–6 requirements
before committing to a manga batch. Later music, servers/TV, downloads and optional
sync features remain planned. Existing unchecked items stay unchecked until their
required evidence is available.

## Device/build acceptance still required

1. Compile/link using the project's Xcode configuration and run the existing test
   target, including `ModuleRemoteSubtitleTests` and `ModuleVideoQualityTests`.
2. Open a real HLS multivariant source. Confirm only advertised resolutions appear
   under Playback, with Auto selected initially and current presentation reported
   independently. Include an extensionless HLS URL and missing bitrate metadata.
3. Select lower/higher preferences during playback and while paused. Check playback
   time, pause/rate state, audio and subtitle selection are retained. Allow buffered
   media to drain; do not expect an immediate exact-resolution switch.
4. Return to Auto and confirm both preferences clear. Test low bandwidth, codec
   alternatives, portrait video and live HLS; record actual device behavior.
5. Open a direct MP4, a media playlist without a useful variant ladder, and a
   single-resolution master playlist. Confirm no fake manual options appear.
6. Change server/episode during discovery, trigger retry/failover and close the
   player. Confirm new items start in Auto and late results cannot restore old
   options. Test timeout/retry without disturbing playing video.
7. Recheck existing server labels, source resolution, embedded/external subtitles,
   Continue Watching, watched state, player menus, PiP and AirPlay for regressions.

## Official references inspected

- [Async variant discovery](https://developer.apple.com/documentation/avfoundation/avpartialasyncproperty/variants)
- [Variant attributes](https://developer.apple.com/documentation/avfoundation/avassetvariant)
- [Video attributes](https://developer.apple.com/documentation/avfoundation/avassetvariant/videoattributes-swift.class)
- [Peak bitrate metadata](https://developer.apple.com/documentation/avfoundation/avassetvariant/peakbitrate-9hzpi)
- [Preferred maximum resolution](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution)
- [Preferred peak bitrate](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate)
- [Current presentation size](https://developer.apple.com/documentation/avfoundation/avplayeritem/presentationsize)

The async variant APIs are documented from iOS 15; this project targets iOS 17+.
Reference inspection does not replace compiling against the project's Apple SDK.
