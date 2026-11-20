# Kinetiq M03 — iPhone PASS / FAIL / NOT TESTED

Fill this after a **successful GitHub Actions XCTest + IPA build**. All rows begin NOT TESTED; source checks do not prove device behavior.

| ID | Test | Result | Notes |
|---|---|---|---|
| CI01 | GitHub Actions simulator build & XCTest pass; unsigned IPA artifact produced | NOT TESTED | |
| U01 | From Home/All Sources, type `Roshidere`, tap the keyboard's **Search** key; keyboard disappears | NOT TESTED | |
| U02 | Same behavior in one-source Search, module catalogue Search, Compass, Brain | NOT TESTED | |
| U03 | Search across all modules: duplicate IDs and duplicate titles remain visible as distinct source rows | NOT TESTED | |
| U04 | Select Roshidere. If module returns an obviously different title, Kinetiq prevents episode loading and explains mismatch | NOT TESTED | |
| U05 | Legitimate alternate title can be explicitly approved; other titles never change without confirmation | NOT TESTED | |
| U06 | If a stream itself plays the wrong series despite matching metadata, use More → Wrong anime or episode playing?; playback pauses and source is marked less reliable | NOT TESTED | This is manual, not visual AI verification |
| U07 | Module `Install All`: exactly one repository-completion banner; look for accidental duplicate after failed module | NOT TESTED | |
| U08 | Notification history increments duplicates under same repository within 15 s; no stacked identical banners | NOT TESTED | |
| P01 | While module player is playing, More → Lock touch controls; accidental seek/episode taps have no effect | NOT TESTED | |
| P02 | Unlock Player remains accessible and restores controls | NOT TESTED | |
| P03 | Double-tap interval 5/10/15/30/60 changes exact jump; left/back and right/forward work | NOT TESTED | |
| P04 | Long hold enables temporary 2× and releases to previous speed, including 1.25×; disabled toggle works | NOT TESTED | |
| P05 | Remaining clock reflects current duration; toggle returns to total duration | NOT TESTED | |
| P06 | Episodes/Queue search filters number/title and Sub/Dub without losing episodes or reordering | NOT TESTED | |
| P07 | Mark Opening Start and End, skip, then Undo Seek; separate Episode 2 retains no Episode 1 markers | NOT TESTED | |
| P08 | Quit/relaunch: manual markers persist, but do not appear on a different source/series/episode | NOT TESTED | |
| R01 | PiP manual, automatic and return; embedded & external subtitle restoration | NOT TESTED | |
| R02 | AirPlay, server selection, fallback, quality, audio/subtitle menus remain operational | NOT TESTED | |
| R03 | Favorites, download queue and offline MP4/HLS playback retain existing history | NOT TESTED | |
| R04 | Discord poster, watching type, time/episode status, reconnect and PiP behavior unchanged | NOT TESTED | |
| R05 | All four tabs and all 13 visual themes still load | NOT TESTED | |

**Important limits:** Module source script errors, wrong CDN video bytes, DRM, unavailable metadata or unavailable local iOS APIs cannot be fixed merely by declaring a title match. Kinetiq detects source-level title disagreements and supports manual wrong-video reporting; provider-specific diagnosis may still be needed.
