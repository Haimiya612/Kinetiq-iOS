# iPhone test checklist — Batch 06L: Discord Presence Lab

Build/run the latest unsigned IPA as usual. The feature is **experimental**:
the test must use a separate Discord account to **observe** whether the
activity is really visible. Do not share a session token in results.

Mark each test `PASS`, `FAIL`, `BLOCKED`, or `NOT TESTED` and put notes at the
bottom.

| ID | Test | Result |
| --- | --- | --- |
| 06L-01 | Settings → Integrations → Presence Lab opens; feature is Off by default | NOT TESTED |
| 06L-02 | A fresh credential can be entered in SecureField; saving clears input | NOT TESTED |
| 06L-03 | Settings reports saved Keychain credential without revealing its value | NOT TESTED |
| 06L-04 | Enable feature; status reaches `Gateway connected` or clearly shows a failure | NOT TESTED |
| 06L-05 | Send sample activity; separate Discord observer sees a Watching presence | NOT TESTED |
| 06L-06 | Play Blue Box Season 2; title and episode number display correctly | NOT TESTED |
| 06L-07 | Anime **main poster** displays on Discord, without cropping or a Kinetiq logo | NOT TESTED |
| 06L-08 | Pause/resume updates state without flooding the Gateway | NOT TESTED |
| 06L-09 | Seek, switch episodes, change Sub/Dub; presence remains accurate | NOT TESTED |
| 06L-10 | Start PiP and background Kinetiq: video plays and Presence persists | NOT TESTED |
| 06L-11 | Return from PiP; activity reconnects/updates if socket was suspended | NOT TESTED |
| 06L-12 | Exit playback; presence clears on the external Discord observer | NOT TESTED |
| 06L-13 | Disconnect and Forget remove credential; no automatic connection while Off | NOT TESTED |
| 06L-14 | Invalid or revoked credential shows recovery status without crash | NOT TESTED |
| 06L-15 | Kinetiq playback/PiP/server switches/source names remain unchanged | NOT TESTED |

## Notes

- Device / iOS:
- Current build / Action run:
- Connection status:
- External presence visible (different account):
- Artwork visible / missing:
- PiP result (screen locked / app background):
- Any error text (never include a token):
- Other observations:

**Do not call the feature operational until the externally observed tests pass.**
