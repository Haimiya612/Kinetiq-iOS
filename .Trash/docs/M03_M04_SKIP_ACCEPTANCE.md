# M03/M04 contextual skip — iPhone acceptance checklist

Run on the signed/installed IPA **after GitHub Actions succeeds**. Mark PASS / FAIL / NOT TESTED; record source and episode and attach safe diagnostics for failures.

| ID | Test | Result |
|---|---|---|
| S01 | Open module player; More → Power Deck shows Mark Start/Mark End for Opening, Recap, Ending / Credits | NOT TESTED |
| S02 | Open an unmarked episode: no fabricated Skip Intro or Skip Credits button | NOT TESTED |
| S03 | Save a 1+ second Opening marker; button appears only while within its actual interval | NOT TESTED |
| S04 | Tap Skip Intro: seeks to exact saved end, not guessed position | NOT TESTED |
| S05 | Undo seek from Power Deck restores previous position | NOT TESTED |
| S06 | Dismiss X hides this specific prompt without pausing or seeking | NOT TESTED |
| S07 | Mark Recap: Skip Recap appears only in Recap interval | NOT TESTED |
| S08 | Mark Ending: Skip Credits appears inside marked range, Next Episode button appears when next is playable | NOT TESTED |
| S09 | Change episode: prior episode's marker never appears | NOT TESTED |
| S10 | Change module/source **or server**: previous marker never appears on a different provider/stream fingerprint | NOT TESTED |
| S10b | Change to a different-duration cut: previous marker never appears; M03 legacy markers remain stored but do not auto-trigger | NOT TESTED |
| S11 | Same source/episode after full app restart: marker remains | NOT TESTED |
| S12 | Episode without a successor: no premature next-episode button | NOT TESTED |
| N01 | With autoplay on and no Binge Guard stop: after actual video ends, 10-second Play Now / Cancel prompt appears | NOT TESTED |
| N02 | Play Now starts next episode through existing source resolver and maintains language preference | NOT TESTED |
| N03 | Cancel leaves the completed episode on-screen and doesn't change global autoplay preference | NOT TESTED |
| N04 | Disable autoplay: no countdown and no automatic next episode | NOT TESTED |
| N05 | Binge Guard pause-after-one: no countdown or auto-next | NOT TESTED |
| N06 | With countdown disabled but autoplay enabled: legacy immediate next playback | NOT TESTED |
| N07 | Changing episode/server cancels old countdown and never starts a stale episode | NOT TESTED |
| N08 | Background/PiP end-of-episode does not create an invisible cancelable prompt | NOT TESTED |
| R01 | PiP, AirPlay, subtitles, player gestures, Quick Deck, recovery and playback progress remain functional | NOT TESTED |
| R02 | Four tabs, source names, saved library and Discord presence remain unchanged | NOT TESTED |
| R03 | VoiceOver can find Skip, Dismiss, Play Now and Cancel; no blocked touch targets | NOT TESTED |
