# Kinetiq combined verification — 06K.10A + 06K.10B

Mark PASS / FAIL / UNAVAILABLE; all items are NOT TESTED initially.

## Deferred 06K.10A

- [ ] GitHub Actions compilation and XCTest.
- [ ] Calendar item opens All Sources anime lookup.
- [ ] iPhone notification tap opens the correct anime while locked/backgrounded/cold-launched.
- [ ] In-app notice opens the same lookup.
- [ ] Actual episode title, number, artwork shown when metadata exists.
- [ ] Full source browsing automatically paginates.
- [ ] Favorites hitboxes, search, genre navigation and module switching regressions.
- [ ] Local Library and online module histories remain independent.
- [ ] Playback, PiP, SRT/WebVTT bridge and resume regressions.

## New 06K.10B

- [ ] Downloads tab is usable in all 13 themes with 44-point touch targets.
- [ ] Installed trusted modules offer downloads without adding config.offline.
- [ ] MP4 Episode 5 downloads and plays in Airplane Mode when the stream is directly available.
- [ ] HLS VOD episode downloads and plays in Airplane Mode when supported.
- [ ] Extensionless direct MP4/HLS URLs recognized using the stream's MIME type.
- [ ] Embedded pages, live-only feeds and unsupported formats explain technical limits.
- [ ] HLS with source headers/cookies is attempted; record actual provider results.
- [ ] HTTPS CDN redirects preserve playback without leaking cross-host credentials.
- [ ] Quality presets display only actual HLS rendition options.
- [ ] Queued, progress, pause, resume, cancel and retry operate correctly.
- [ ] Background, locked phone, app restart and system termination recovery.
- [ ] Explicit Wi-Fi-only/cellular behavior.
- [ ] Storage totals, storage limit, delete item and delete completed.
- [ ] Deleting a download leaves Local Library, Favorites and history unchanged.
- [ ] Source identity, sub/dub and video selection remain correct.
- [ ] Offline playback opens the **same streaming player** (controls, seek,
      speed, aspect ratio, audio, subtitles and PiP), not a system-only player.
- [ ] Module resume history persists through app restart and does not appear
      in Local Library.
- [ ] Offline MP4 with multiple SRT and WebVTT tracks downloads **all** tracks,
      offers each in subtitle menu and displays them without internet.
- [ ] One broken or invalid subtitle URL prevents incomplete downloads.
- [ ] Offline HLS with multiple embedded audio and subtitle languages saves
      and exposes every advertised supported media selection.
- [ ] Native subtitles in offline PiP; external sidecars in offline PiP
      (record supported / unsupported independently).
- [ ] VoiceOver, Dynamic Type, Reduce Motion and low-storage errors.

There is no module-specific offline authorization flag. A direct playable URL
is still required; an embed-only result is not a downloadable video.
Verify real MP4/HLS offline playback using a known working direct media source
before marking the functionality PASS.
