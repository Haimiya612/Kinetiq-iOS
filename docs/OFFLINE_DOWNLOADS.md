# Kinetiq offline video contract — 06K.10B.2 direct media downloads

The Downloads tab contains a shared native MP4 and HLS VOD download queue,
distinct from the user's imported Local Library. Its index never saves a
remote stream URL, provider credentials, or cookies.

## Download eligibility

There is **no publisher-specific offline flag**, offline host allowlist,
authorization URL, or per-module download grant. Any installed
streaming module may offer episode downloads when it resolves a directly
playable HTTPS MP4/MOV/M4V or HLS stream, including MIME-typed URLs without
file extensions. Resolved streaming CDN hosts may
differ from the module's base host. Cross-host HTTPS redirects drop source
credentials rather than forwarding them to unrelated destinations.

No extra download permission setting or per-source consent switch is
introduced by this feature. Web-only embeds without a direct video
URL, live feeds, and formats unsupported by the native offline APIs cannot
be saved through this implementation.
HLS streams with custom headers/cookies are **attempted** using the same
best-effort AVURLAsset options as streaming; AVFoundation may not propagate
them to all segments. No success is claimed until an actual download plays
offline on-device. Users remain responsible for saving only media they may
lawfully keep.

## Functional scope

- Per-episode download sheet with sub/dub and real available HLS qualities.
- Background URLSession transfers for direct MP4 and AVAssetDownloadURLSession
  for HLS VOD; task identifiers are opaque and contain no stream secrets.
- Progress, queue, pause/resume, cancel, in-session retry, deletion,
  storage limits and Wi-Fi/cellular preferences.
- Offline episodes reopen **the same `KinetiqModulePlayerView` and
  `ModuleEpisodePlaybackSession`**, with its established controls, PiP,
  caption preferences and module watch-history/resume identity. Nothing is
  inserted into personally imported Local Library data.
- **Every source-advertised external SRT/WebVTT track** must be fetched,
  parsed and saved as a local sidecar before the episode is queued. An
  invalid URL or failed track makes the entire request fail clearly;
  no available subtitle is silently skipped.
- For HLS VOD, the native asset configuration requests every reported
  `allMediaSelections` audio/caption combination (bounded to 100). Whether
  AVFoundation preserves every rendition requires an iPhone verification.
- Offline sidecars feed the same custom subtitle controller; native embedded
  subtitles are controlled through the same AVPlayer menu. Offline sidecar
  display **in system PiP remains unverified** and may require an additional
  native handoff path.

## Limits that still need device tests

- Test a range of installed modules that return direct MP4/HLS videos;
  a missing `config.offline` object must not block the download sheet.
- Season batch queues and HEVC transcoding/compression belong to later work.
  Quality presets choose actual HLS variants, not an invented transcoded resolution.
- All available subtitle tracks are requested, but real multi-language HLS
  retention, external caption rendering and captions in offline PiP still
  require iPhone verification against permitted sample media.
- External caption downloads are bounded to 24 tracks and 2 MiB per track,
  and follow HTTPS redirects with source credentials stripped on cross-host
  handoffs.
- Expiring signed links may require reopening the episode after an app relaunch.

Apple primary references:
- https://developer.apple.com/documentation/avfoundation/using-avfoundation-to-play-and-persist-http-live-streams
- https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession
- https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- https://developer.apple.com/app-store/review/guidelines/
