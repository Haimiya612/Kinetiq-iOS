# iPhone test — Batch 06L5

After replacing the files in Working Copy, build the unsigned IPA with
GitHub Actions. Test with an anime that actually plays on Kinetiq, and observe
the Discord activity from a different account. Never share tokens or headers.

| Test | Expected | Result |
| --- | --- | --- |
| Discord heading | Watching **Kinetiq** (not Watching + anime title) | NOT TESTED |
| Appearance styles | Choosing “on Kinetiq” requests Watching **on Kinetiq** | NOT TESTED |
| Activity type codes | 0–5 selectable; Streaming requires real Twitch/YouTube URL | NOT TESTED |
| Anime and episode | Anime title in details; episode number and real name in state | NOT TESTED |
| Poster | Try automatic cover, then a registered test asset if automatic is absent | NOT TESTED |
| +10-second skips | Tap forward repeatedly; **no** false Paused state | NOT TESTED |
| Actual pause/resume | Pause appears only when deliberately stopped; resume restores timer | NOT TESTED |
| PiP/background | PiP video continues; note if iOS suspends the Discord connection | NOT TESTED |
| Episode download | Try Anikage/Jujutsu Kaisen episode 1, Sub, with Wi-Fi | NOT TESTED |
| Download quality | Test original/available variants; no fictitious downloads | NOT TESTED |
| Offline playback | Finished video plays with network disabled | NOT TESTED |
| Regression | Tabs, subtitles, player, modules, server selection remain functional | NOT TESTED |

If the download button still says “background download service is unavailable”,
record the iOS version, source, Wi-Fi-only setting and whether Retry source
check changes the result. Do not include streaming links, tokens or headers.

**Important:** Picture in Picture permits video continuation; iOS does not
guarantee that an unrelated persistent WebSocket stays active in the background.
