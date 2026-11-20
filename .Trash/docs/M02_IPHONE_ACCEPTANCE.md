# M02 iPhone Acceptance — PASS / FAIL / NOT TESTED

Fill each result after installing a GitHub Actions-generated IPA. A ZIP passing syntax checks does not certify actual device behavior.

| ID | Test | Result | Notes |
|---|---|---|---|
| U01 | Compass: type romance, press Search; keyboard dismisses | NOT TESTED | |
| U02 | Compass: keyboard Search submits and dismisses | NOT TESTED | |
| U03 | Anime detail: favorite title shows exactly one check mark | NOT TESTED | |
| U04 | Discord profile: `Episode 1: S1E1: Episode 1: Title` becomes a single clean title; poster and elapsed time remain | NOT TESTED | |
| U05 | Unofficial RPC connection, authentication and reconnection remain unchanged | NOT TESTED | |
| D01 | Episode MP4 resolves, downloads, plays offline in Airplane Mode | NOT TESTED | |
| D02 | HLS VOD resolves, downloads, plays offline in Airplane Mode | NOT TESTED | |
| D03 | Individual episode subtitles remain available offline and in PiP where supported | NOT TESTED | |
| D04 | Downloaded MP4/HLS resume after app restart | NOT TESTED | |
| D05 | Full season queue no more than 60 items; no duplicate ready or queued episodes | NOT TESTED | |
| D06 | Next 3 missing episodes queues only missing items for selected Sub/Dub | NOT TESTED | |
| D07 | Season progress remains 0/N → N/N as individual episodes are queued | NOT TESTED | |
| D08 | Waiting queue up/down changes priority; order survives restart | NOT TESTED | |
| D09 | Active tasks remain unaffected by priority reorder | NOT TESTED | |
| D10 | Charging-only gate holds newly queued transfers until charging (app active) | NOT TESTED | |
| D11 | Night-only gate explains it cannot force iOS background wake-ups | NOT TESTED | |
| D12 | Per-series budget blocks new transfers once saved bytes exceed limit | NOT TESTED | |
| D13 | Source A budget does not affect source B / another anime | NOT TESTED | |
| D14 | HLS size displays estimate only with real duration and peak bitrate; otherwise unknown | NOT TESTED | |
| T01 | Travel Vault file audit differentiates ready and failed | NOT TESTED | |
| T02 | MP4 playback probe decodes a frame from an actual saved file | NOT TESTED | |
| T03 | HLS probe reports local asset compatibility but not falsely “fully playable” | NOT TESTED | |
| T04 | Travel Vault can stop/restart playback probes without losing downloads | NOT TESTED | |
| Q01 | HEVC 30-second sample encodes and can be previewed | NOT TESTED | |
| Q02 | Original remains unchanged if sample/full conversion fails or is canceled | NOT TESTED | |
| Q03 | Sample size is not presented as full output size | NOT TESTED | |
| R01 | Four tabs, modules, Favorites, themes, RGB, PiP and subtitle options unchanged | NOT TESTED | |
| R02 | Successful Actions XCTest and unsigned IPA artifact | NOT TESTED | |

### Report format

Copy the table and replace `NOT TESTED` with `PASS` or `FAIL`. Attach the error code or a screenshot where useful. Do not publish Discord credentials or authenticated stream URLs.
