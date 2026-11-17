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
- Bounded season download sheet reached from an anime's Episodes section.
  Explicit season identifiers download that season; a flat module episode
  list offers **All Listed Episodes** instead of inventing season numbers.
  For each episode the app checks the requested Sub/Dub availability, skips
  existing nonfailed entries, resolves a separate native MP4/HLS stream, then
  enqueues it using the ordinary download store. The batch is bounded to
  60 entries and may be stopped without cancelling already queued transfers.
  All failures are reported by episode; this operation **prepares a queue**,
  not a promise that every download has finished successfully.
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
- Season queue-preparation code is now present but needs CI and iPhone tests,
  especially background/resume, source rate limits and bulk storage pressure.
  Queued requests are persisted individually; an unfinished **season resolver**
  does not automatically restart after the process is killed.
- HEVC/AV1 transcoding and a Kinetiq offline container remain separate future
  work. Repacking MP4/HLS media as ZIP generally provides negligible savings.
  A storage-saving preset should use an available lower-bitrate rendition or a
  separately validated, on-device transcode with explicit quality/size tradeoffs.
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
