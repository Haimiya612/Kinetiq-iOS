# Kinetiq — The All-in-One "Jackpot" Experience

**Deep research and product specification — 16 November 2026**

**Status:** Research and architectural proposal, **NOT implemented software**. The six locked priorities below are the **next major integration**. This document does not certify an Xcode build, ship an IPA, or imply any code is already complete.

## 0. Executive direction

Kinetiq should be the place where a user's anime/video life comes together, not simply a larger player. The moat is **interoperability + personal control + graceful failure**:

- A title has one persistent identity across official metadata, trusted modules and user-selected local files.
- The user can switch editions/sources while preserving the correct season, episode, approximate scene, preferred language and watched state.
- The same timeline feeds a genuine, privacy-aware assistant, quality automation, downloads, notifications, playback notes and watch parties.
- Every advanced operation is reversible, diagnosable and opt-in. Never hide a failing source, alter original source names, silently delete local video, run an untrusted module, or silently upload watch history/filenames.
- Preserve exactly **four main tabs: Home, Favorites, Downloads, Settings**. New experiences live in sheets, destinations, the existing Player and Settings.
- Preserve working unofficial Discord Presence implementation, its storage and formatting exactly as-is. It is experimental, so no other feature may ingest, share or log that credential.
- Music is not a required priority. Anime, film, series, local video and eventually manga/novels are the priority.
- Do not inflate IPA size for its own sake; optional downloaded language/model packs can make the installed app larger when there is a useful capability.

**Current-source guardrail:** docs/ALL_IN_ONE_EXPERIENCE_2026_11_16.md describes an existing 06P1/06O handoff: deterministic Kinetiq Compass discovery, user-confirmed Source Passport links, local unwatched inventory and Travel Vault, episode/season download scaffolding. Do not falsely label those as a conversational model, automatic universal matching, reliable offline acceptance, compression, cloud sync or watch rooms. Device validation is still outstanding.

## 1. The six immovable NEXT priorities

| ID | Priority | User-visible contract | Hard requirement | Dependency |
| --- | --- | --- | --- | --- |
| N1 | **Kinetiq Brain: conversational AI** | Multi-turn chat understands permitted metadata, imported folders, your saved shows, download inventory, playback progress, source results and controls. "Which unwatched romance under 13 episodes can I watch offline?" returns grounded choices and actions. | Zero invented stream links; show provenance and confidence; never read files outside selected grants; never send local filenames/history to online model without explicit opt-in. | Canonical identity N2; permissioned index; optional local model or explicitly configured hosted model. |
| N2 | **Universal continuity** | Switch source/edition mid-episode and return to the matching point, same language and correct subtitle track where possible; progress follows title identity, not only module ID. | "Same title" alone is insufficient: protect against different cuts, numbering, films, specials, dub editions and duration mismatch; confirmation for uncertain matches; reversible mapping. | Identity Graph and manual Source Passport confirmation. |
| N3 | **Kinetiq Quality Forge** | For owned/authorized offline media, preview estimated file size, compare sample frames and re-encode to supported efficient codec/bitrate; preserve playable copy, subtitles, audio and progress. | No claims of dramatic lossless video compression: conventional ZIP won't shrink already encoded video much. Never delete original until full verification. Thermal/battery limits and rights checks. | Offline store; asset compatibility; AVFoundation/VideoToolbox; integrity ledger. |
| N4 | **Cross-device sync** | An opt-in account or secure pairing carries favorites, watch state, source mappings, settings, bookmarks, queue and download *manifests* across Kinetiq devices. | End-to-end protection, conflict resolution, export/delete controls; never assume sync of media payloads or sharing of module credentials; no false "cloud sync" without backend. | N2 IDs; event log; encrypted storage; transport. |
| N5 | **Kinetiq Watch Rooms** | Persistent rooms with invite code/QR, ready check, host controls, synchronized pause/seek, late join, individual captions, chat/reactions and spoiler protection. | Sync *playback state* and permitted metadata only; participants obtain their own authorized content access. No redistribution or DRM bypass. | Time alignment from N2; backend or approved SharePlay entitlement; network recovery. |
| N6 | **Streaming-experience consolidation** | Bring all researched controls, personalization, discovery, accessibility and resilience together in one feature-complete native player and four-tab shell. | Existing 06P1 functions remain intact, no feature theater/placeholder buttons, no broken Discord change, and no duplicate UI owner for settings. | Player componentization; continuous acceptance matrix. |

### Acceptance tests for the six priorities

1. **N1**: Ask for *unwatched imported romance under 13 episodes*, then refine *only English subs and downloaded*; results must expose data source; refusing access must leave private data private. No generic AI text disguised as verified catalog results.
2. **N2**: Open S1E4 at 10:27 in provider A. Switch to provider B with verified same episode/duration; present sensible mapped resume time. Repeat with OVA/S2E4, incompatible cut and failed server: prevent wrong jump; preserve original A history.
3. **N3**: Choose permitted local MP4. Preview 30–60 seconds, request HEVC conversion, force low storage/thermal state and cancel. Verify original remains playable. Completed result keeps correct duration, subtitle/audio options, checksum and progress; report measured, not promised, savings.
4. **N4**: Offline watch on A then offline favorite edit on B; reconnect, resolve conflicts per-item and show a traceable result. Export and restore onto a clean installation. Settings sync must not upload Discord user token.
5. **N5**: Two clients use different permitted sources of the same matched episode, host seeks 10:05, late join at 13:00, one buffers 8 seconds, one changes captions. Both remain within an appropriate tested drift budget; neither switches the other's captions.
6. **N6**: All player buttons are accessible and have real capability state; unsupported options explain *why*; local and module player show equivalent control categories and correct fallbacks; 06P1/06O, PiP, external captions, AirPlay and Discord regression suite remains green.

## 2. What competitors ALREADY have (do not claim inventions)

| Provider/player | Verified experience | Stronger Kinetiq adaptation |
| --- | --- | --- |
| Netflix | Downloads for You, auto next-episode download, Moments clip bookmarks | A private **travel readiness rehearsal** with local module recordings, subtitles, battery/storage budget and source-based recovery; clips only where capture/export is lawful. |
| Crunchyroll | SharePlay, offline episode/season downloads, release calendar, new accessibility/speed/caption controls | Synchronized **cross-source** watch rooms, anime-specific identity/editions, language-specific release radar with proper distinctions. |
| Prime Video | X-Ray cast/trivia, AI text/video recaps, scene search/jump | Spoiler-aware **source-independent** context and personal timeline notes, linked to local media and all available permitted providers. |
| Apple TV | InSight contextual actors/characters/music and Enhance Dialogue | Contextual anime characters, voice actors, staff, canon order, glossary, per-source audio filters where physically supported. |
| YouTube | Ask YouTube conversational AI on supported content | Kinetiq Brain crosses a user's granted local media + anime metadata + personal queue, rather than being only a video chatbot. |
| Plex | Discover/universal watchlist; community discussion of Watch Together reinstatement | Real local/remote progress **identity transfer**, reliable persistent room across episodes, not only a provider launch link. |
| Infuse | Advanced codec support, local/server files, metadata, sync and upscaling | Subtitle reliability, provider/source repair, selective local conversion with a real quality preview and anime identity context. |
| mpv | A–B loop, fine subtitle/audio offset, seek-to-subtitle, screenshot, filters | Put professional-level controls into an ergonomic iOS interface; this control *inventory* is not itself new. |
| Jellyfin | Chapter thumbnails and structured intro/outro media segments | Universal scene map and intelligent chapter marks spanning imported files and trusted modules. |
| Viki | Former Learn Mode (officially sunset 31 July 2023) | Modern **Japanese Study Deck** with dual captions, line loop, furigana/dictionary, study history and safe local-only storage. |
| Trakt / Simkl / AniList | Tracker APIs, import/export, scrobbling, graph relations and schedule data | Identity-based optional interoperable sync with explicit user connections and API-compliant permissions. |

**Research correction:** Some previously suggested "unique" features (SharePlay, AI recap, caption personalization, season downloads, clip sharing, voice scene jump, smart downloads) already exist elsewhere. Unique value comes from combinations and executing them reliably in a modular/local environment.

## 3. Actual customer pain points — design evidence

These are specific self-selected anecdotes, **not representative surveys**:

| 2025–26 user feedback | Design consequence |
| --- | --- |
| Crunchyroll: accidentally starting a show pollutes Continue Watching; hiding it should not erase history. | Minimum meaningful-play threshold; Hide from Row, Unwatch, Clear Progress and Delete History as four distinct operations. |
| Crunchyroll: favorite shows with new seasons disappear under dubbed re-releases; watchlist sorting misorders. | Distinguish NEW EPISODE, NEW SEASON, DUB RELEASE, SUBTITLE AVAILABILITY and CATALOG UPDATE; notification and sort filters. |
| Infuse: "please show captions for ten seconds after I rewind." | Single **What did they say?** control: rewind 10 s, enable temporary captions, restore prior setting. |
| Infuse: subtitle server sends 503 + Retry-After and player silently deselects track. | Subtitle Recovery retries bounded by retry policy, shows loading badge, retains user preference, can pick alternate track. |
| Infuse: forced-only non-English dialogue subtitles are hard to distinguish; bookmarks/watch progress lost after metadata sync changes. | Detect and display forced/default/SDH flags, preview tracks, keep backup snapshots and avoid destructive rematches. |
| Plex: Watch Together removal broke long-distance shared viewing; Nov 2026 users discuss its return. | Rooms persist across episodes and devices; readiness barrier; buffer-aware synchronization and episode advance. |
| Plex: users complain about misplaced/removed playback-speed/subtitle-delay controls and unwieldy on-screen controls. | Permanent location of controls, hideable pro panel, searchable actions, predictable tap zones. |
| Anime viewers juggling multiple subscriptions want a single place to track episodes. | Personal "What is new across my saved shows?" with source availability and canon order; no fabricated access to licensed catalogs. |

## 4. The real differentiation — ten jackpot systems

**J1. Anime Identity Graph** (foundational): local stable KinetiqMediaID; optional AniList/MAL/TMDB references; provider-specific IDs kept intact; editions, language, episode S/E plus absolute count, OVAs, specials, recaps, films; aliases in Japanese/romanized/English/German; confidence and user corrections; bidirectional links with audit trail. AniList's official Media GraphQL exposes sequel/prequel relations, schedule and other relations. Never hide duplicate source search results.

**J2. Scene Passport:** export/import a personal playback anchor containing verified media identity, episode, progress seconds, duration, subtitle cue index and optional scene note. Resume on another source with confidence tiers: exact file+episode match; same episode with normalized timestamp; subtitle-text landmark; optional media fingerprint from *accessible* files. Manual adjustment when source cut differs. Display "approximate match" honestly.

**J3. Source Flight Control:** opt-in probes measure playable protocol, current stalls, startup latency, declared language, quality, privacy, host responsiveness. Rank with a visible rationale and preserve names; no aggressive scraping. On failure, pause and offer ranked proven candidates matching episode/edition; never randomly move to a different episode. User can pin a source and disable fallback.

**J4. SubStudio + Japanese Learning:** SRT/VTT/embedded plus ASS/SSA where legal/compatible; dual-language tracks, vertical position, line-specific offsets, retry, forced captions, per-show presets, repeat subtitle, study flashcards, pronunciation shadowing, simple furigana, vocabulary export, PiP fallback. A real ASS engine can require additional native library size and rendering integration.

**J5. Private Media Intelligence:** with a user-chosen directory permission, index filename, duration, video codec, language, hash and watch state; surface Unwatched, Partially Watched, Possible Duplicates, Space Hogs, Missing Next Episode, Incomplete Season. No automatic deletion. iOS grants selected-folder access via document picker/security-scoped URLs—not arbitrary access to all apps' storage.

**J6. Recovery Ledger:** every interrupted playback/download/encode/source update records recoverable step and error reason; a one-tap Recovery Center offers Retry, Switch Source, Restore Original, Copy Diagnostics, Explain Error, File Health Test, and module quarantine recommendation. No full-screen block for routine update failures.

**J7. Spoiler Firewall:** timeline-aware community posts and AI context; hide screenshots, titles, comments, descriptions, trailers, final-season recommendations past the verified latest watched episode. Granular safe-depth controls; remove as appropriate after marking watched.

**J8. Personal Release Radar:** connect favorite series to season relations and release feed, distinguish time zone, sub/dub language, postponement, official availability versus source-module availability; open all-source search from a calendar entry; offer silent daily digest.

**J9. Universal Smart Queue:** drag and drop episodes across local + trusted module sources; play-next contract, manual "Watch in chronological/franchise order", opt-in quality fallback, binge timer, pause after X episodes, alarm-based "Stop at hh:mm"; persistent handoff to downloads and watch room.

**J10. Private Scene Memory:** with permission, capture legal screenshots or just text/timestamps, personal notes/bookmarks, memorable scenes, quote/character context and spoiler-free review. Export sharable links/reference to content availability where possible; no unauthorized redistribution of protected video.

## 5. Kinetiq Brain — a concrete AI agent, not a chatbot label

### Tool permissions

| Tool | Example question | Read/write policy |
| --- | --- | --- |
| Public anime metadata | "Find an anime about a quiet loner and a teasing girl, finished, under 13 episodes" | Public AniList metadata and public search; display exact match rationale; no invented titles. |
| Unwatched inventory | "Which downloaded series haven't I finished?" | Read only media imported into Kinetiq or explicit user-picked scoped directories. |
| Source catalog | "Where is Blue Box available among my installed trusted modules?" | Search permitted module metadata with existing all-source path; report timeouts and absent results separately. |
| Playback state | "What was the last scene of episode 4 I reached?" | Read user's own tracked position and notes; do not invent story knowledge. |
| Quality planning | "Can I save 3 GB for the train?" | Analyze locally measurable bytes/codec, suggest reversible options, ask before transcoding/removing. |
| Calendar/taste | "Notify me for new romance seasons but not new English dubs" | Draft setting and show affected titles; confirm before writing. |
| Diagnostics | "Why did this stream fail?" | Explain captured error code, server retry options; redact protected URLs/tokens. |
| Library actions | "Mark this as watched", "queue this season" | Explicit confirmation for destructive/bulk actions, undo history, clear provenance. |

Architecture: start with **deterministic search and grounding** reused from 06P1 Compass; add an optional on-device model when Apple's Foundation Models is available and performs acceptably; provide a clear alternative for unsupported devices; cloud model requires user opt-in and a real securely configured service. Never ship API secrets in the IPA. A device model is not guaranteed available on every iOS 17+ device. Include model/version state, hallucination tests and bounded function calls. Account for animation/accessibility.

## 6. Player navigation: maximize power, minimize obstruction

Current unified module player already has a transport row, scrubber, AirPlay/PiP/aspect actions and seven bottom panels: **Episodes / Servers / Audio / Playback / Subtitles / Queue / More**. Existing content includes speed, aspect, multiple subtitle routes, quality, sleep, diagnostics, Discord Presence and retry. Build on this rather than putting 100 overlapping icons on the video.

Proposed navigation:

- **Always visible while chrome active:** close, title, AirPlay, PiP (if supported), seek +/-10, play/pause, prev/next episode, slider, elapsed/remaining, current source badge, subtitle quick switch and *More*.
- **One-tap Quick Deck:** Speed, Quality, Subs, Audio, Server, Queue, Sleep, Report Problem — user-customizable and rearrangeable.
- **Power Deck:** Playback, Timeline, Video, Audio, Captions, Sources, Anime Info, Study, Social, Downloads, Diagnostics, Accessibility. Scrollable sections; action search and favorites.
- **Long-press video:** context menu of 5–8 pinned actions. **Double-tap:** programmable seek. **Two-finger gesture:** optional, documented, off by default; accessible button equivalent always exists.
- **Capability matrix:** unsupported options disabled with explanation, never dead buttons. Allow compact/standard/advanced density with VoiceOver/large-text-friendly layout.
- **Settings-owned app theme:** all global RGB/theme controls remain in Settings; player may inherit accents but never host the primary app customization UI.

### Accessibility invariants

Every action exposes an accessible label/hint and at least usable target area, VoiceOver rotor and switch-control order. Dynamic Type in sheets, reduced motion, no controls behind sensor notch or Home indicator, landscape safe-area support. Do not use color alone to distinguish untrusted, failed or selected sources. Timing adjustments must work with keyboard/assistive actions.

## 7. The module player: comprehensive control catalogue

These are **action candidates**, not an assertion that every one is implemented or that they need 150+ simultaneous visible buttons. Some already exist in Kinetiq; the acceptance pass must mark each as EXISTING / NEW / CONDITIONAL / INAPPLICABLE and link its implementation. A control may display only when the content/device supports it.

### A. Essential transport and timeline

1. Play / pause.
2. Previous episode / next episode.
3. Seek backward/forward in separately configurable 5, 10, 15, 30 and 60 second steps.
4. Press-and-hold temporary 1.5x/2x playback, releasing to original speed.
5. Double-tap edge seek with optional haptic feedback.
6. **Undo Last Seek** (save the previous timestamp; restore after accidental swipe).
7. Jump to exact timestamp (hh:mm:ss).
8. Timeline scrub preview thumbnails, if available.
9. Fine scrub (drag farther from timeline = finer adjustment).
10. Jump to chapter, scene marker or bookmarked moment.
11. Next/previous subtitle line navigation.
12. Frame-step for locally accessible decodable media (not generic network HLS).
13. A/B loop with optional repeated count.
14. Repeat entire episode / repeat playlist item / repeat season.
15. Previous scene, next scene and back-to-last-paused position.
16. Always-visible elapsed/remaining time toggle.
17. **What did they say?**: rewind 10 s with temporary captions.
18. Skip opening / skip recap / skip ending / skip preview / reverse mistaken skip, **when verified chapter data exists**.
19. Autoplay-next on/off plus a countdown with Cancel and Play Now.
20. "Pause after this episode", "stop after N episodes", "stop at time" and "sleep after inactivity".

### B. Episode, edition and canon navigation

21. Episode list with watched/unwatched/partial/progress badges.
22. Search within episode list and switch numbered/absolute numbering.
23. Change season, movie, special, OVA and recap edition.
24. Canonical watch order vs broadcast/release order vs user custom order.
25. Preview episode title without plot spoiler after watched boundary.
26. Filter by subtitle/dub language, release status and source availability.
27. Mark episode watched/unwatched (manual override with Undo).
28. Reset episode progress without erasing viewing history.
29. Toggle auto-add next episode to queue.
30. Open the series metadata card and franchise relation navigator.
31. Inspect episode duration, year, director, subtitle availability and source response.
32. Copy canonical episode ID or share spoiler-safe metadata link.

### C. Server, stream and resilience

33. Choose server/source, with original source name preserved.
34. Prefer pinned server / last good server / highest confidence.
35. Pre-flight diagnostics and playability indicator.
36. Source latency, recent failures, estimated throughput and stream format.
37. One-tap fallback to verified same episode.
38. Compare alternatives side by side without hiding "duplicate" results.
39. Retry with exponential backoff and explicit cancellation.
40. Re-select subtitles/audio when changing source.
41. Display exact file cut/resolution/audio/sub version when known.
42. **Portable Resume** with position/confidence preview and 10-second adjustment.
43. Switch to local/downloaded copy when equivalent and available.
44. Restrict to Wi-Fi or avoid mobile data above a user budget.
45. Temporary "do not auto-switch this source" lock.
46. Copy safe playback diagnostics without headers/tokens/stream keys.
47. Preview server health history with data provenance.
48. Report wrong episode/incorrect season/corrupted source to local correction list.
49. Optional background pre-resolve of next episode from trusted sources with bounded resource use.
50. Simulator/test mode for error 401/403/404/429, HLS playback fail and subtitles 503.

### D. Video and display

51. Quality Auto / original offered quality / manual rendition.
52. Quality info: actual 360/480/720/1080/4K if known, bitrate, fps, codec and HDR.
53. Fit / Fill / Stretch / original pixels, with aspect reset.
54. Safe zoom/pan for letterboxing or subtitles (do not hide text).
55. Rotate portrait/landscape; respect requested player landscape.
56. Brightness slider/gesture where supported by OS.
57. Adjustable contrast, saturation, gamma and warmth for locally rendered content, not unsupported protected streams.
58. Live color/HDR capability and HDR-to-SDR tone mapping when pipeline supports.
59. Black-frame detector / static frame watchdog with opt-in recovery.
60. Match original frame rate or display refresh when supported.
61. Screenshot/scene bookmark where permitted; show capture restriction otherwise.
62. Hide/show controls, never auto-hide while paused if accessibility setting enabled.
63. Compact mini-player, fullscreen and PiP (subject to hardware/API restrictions).
64. AirPlay route picker and remote playback status.
65. Scaled preview thumbnails size and memory cap.
66. Pin orientation independently of main-app theme.

### E. Captions and subtitle studio

67. Off / From source / Embedded / External subtitle library.
68. SRT/VTT loading and capability-checked ASS/SSA styling.
69. Primary and secondary subtitle tracks (dual-language when both available).
70. Language order and fallback priorities per series.
71. Size, font, weight, stroke, shadow, background and opacity.
72. Vertical offset (avoid face/scene) and safe-area anchoring.
73. Horizontal alignment and line width/wrapping.
74. Color settings and optional auto-contrast from video region.
75. **Subtitle delay fine tuning** +/-0.05 or +/-0.1s; reset.
76. Caption duration/speed adjustment when timing data permits.
77. **Automatic subtitle retry** on transient fetch error, honoring Retry-After.
78. Show track properties: language, SDH, forced-only, default, commentary, group.
79. "Foreign dialogue only" forced-track preference.
80. Smart language-priority auto-selection without losing manual override.
81. Subtitle search in all local imported files; never spoof unlicensed availability.
82. Preview 3–5 lines before choosing a candidate track.
83. Auto-enable captions only for rewind replay then restore.
84. Show/hide captions for the current scene only.
85. Next/previous subtitle and repeat one subtitle interval.
86. Caption scrolling transcript with tap-to-seek (if local/permitted).
87. Select text to translate, define, copy and add to flashcards.
88. Show ruby/furigana in Japanese Study Mode when language tools support it.
89. Dual/subtitle overlap avoidance and per-track vertical offsets.
90. Per-show subtitle style and delay profiles.
91. Repair malformed timings for an imported sidecar with an undoable copy.
92. PiP caption support matrix and fallback, with truthful status.

### F. Audio

93. Select original/dub audio tracks; show exact language and codec.
94. Volume and mute, respecting system/media route.
95. **Audio delay** fine tuning +/-0.1s and reset where custom pipeline permits.
96. Voice clarity/dialogue boost (only where signal path supports processing).
97. Night mode/dynamic range reduction and equalizer on supported audio output.
98. Audio channel downmix/stereo/mono options when possible.
99. Stereo balance and channel diagnostics.
100. Audio-only background listening where system capability and rights allow.
101. Keep pitch constant while slowing playback.
102. Custom playback speed (e.g. 0.75x to 2.0x as engine permits).
103. Per-series preferred dub and track.
104. Spatial audio route and available output formats (informational where AVPlayer controls externally).
105. Bluetooth/AirPlay output diagnostic and device latency notice.
106. Audio description track preference where provided by media.
107. "Replay dialogue" preset with audio boost if available and temporary captions otherwise.

### G. Learning and personal intelligence

108. Ask Kinetiq Brain about this anime/show at the current watched depth.
109. Query "who is this character?" only with grounded metadata; spoiler-safe.
110. Define/translate current subtitle line.
111. Save vocabulary, pronunciation and sentence.
112. Slow + repeat line; A/B learn loop.
113. Hide translation until tapped for self-testing.
114. Generate study card from authorized subtitle cue; export CSV/Anki-compatible cards.
115. Add personal note at timestamp; voice note only with explicit microphone permission.
116. Search timestamped notes, subtitles and chapter headings.
117. Build "Previously on" summary only from available licensed/authorized text and watched range, with source and confidence.
118. Record original title, alternative spelling, Japanese reading, season/canon location.
119. Spoiler Shield strength slider while browsing contextual details.
120. "Find similar shows in my trusted catalog" using AniList traits, displaying failed modules.
121. Show next episode release time and related special/OVA.
122. Export episode progress state and source identity diagnostics.

### H. Offline, queue and storage

123. Download episode / season / selected episodes (source/download availability permitting).
124. Choose quality/audio/subtitle package and storage target.
125. Estimate size before downloading; show unknown if no reliable estimate.
126. Wi-Fi only / mobile data cap / charging preference.
127. Pause/resume/retry/remove queued download.
128. Verify downloaded MP4/HLS and sidecar subtitle presence.
129. Travel Vault: *airplane-mode rehearsal* with actual short decode test on device.
130. Offline quality/compression preview and estimated battery/temperature.
131. Compare original and transcoded clip before accepting conversion.
132. Pin original / roll back transcoded edition.
133. Auto-remove played episodes **only when user opts in**, with recoverable policy.
134. Smart queue reorder, group-by-season, episode language and priority.
135. Add to Favorites/Watch Later/Study Later.
136. Mark Don't Auto Download This Show.
137. Export safe offline manifest and import compatibility report.
138. Duplicate local copy detection with non-destructive review.

### I. Rooms, profile and social

139. Create Watch Room / Join by code or QR / Copy invite.
140. Ready / Not Ready, host request-to-start.
141. Share current progress anchor, not video content.
142. Party drift indicator; "resync with host".
143. Host pause / group pause / individual buffering policy.
144. Late join with source/edition alignment and title mismatch warning.
145. Individual caption, audio, quality and playback preset.
146. Reaction emoji, chat and optional timestamped comments.
147. Spoiler depth enforcement on messages and previews.
148. Rejoin after app restart/network loss without duplicate room.
149. Co-watch queue and vote next episode.
150. Private friend groups and report/block/mute/moderation settings.
151. "Watch later together" invite with time zone and no account leak.
152. Optional share to system Share Sheet, respecting content rights.
153. Existing Discord Presence status **unchanged**, never shared automatically to rooms.

### J. Accessibility, diagnostics and automation

154. Closed-caption quick toggle, VoiceOver output status, Reduced Motion, High Contrast.
155. Larger subtitle and interface font independent of video zoom.
156. Single-handed player controls and left-/right-hand mode.
157. Haptic intensity, disable gesture conflicts, keyboard control shortcuts.
158. Safe-area diagnostics for PiP and landscape.
159. Plain-language error explainer (HTTP, decoding, entitlement, subtitle).
160. Advanced stream information and copyable redacted debug bundle.
161. Buffer graph (last 60 seconds), stall count, dropped frames if API exposes.
162. Data usage per episode and source; user-controlled history retention.
163. Battery/thermal warning before expensive encode or live processing.
164. Source test matrix: probe video, audio, captions and PiP independently.
165. Quick Settings presets: Study, Cinema, Battery Saver, Travel, Low Data, Accessible.
166. Restore factory presets for one episode vs entire application.
167. Configurable shortcuts and Action Search by typing a verb ("sync", "caption delay").
168. Crash-safe playback session restore and optional manual "Report this".
169. Show all enabled capabilities and "why unavailable" explanations.
170. Test every action across Local MP4, HLS, trusted module, AirPlay and PiP, with explicit N/A rather than hiding failure.

**Important:** This is a candidate catalogue of 170 numbered *actions/capabilities*, not 170 independently shippable features. Some are currently present (e.g. normal seeking, PiP, AirPlay, basic download, speed, subtitles, diagnostics, Discord status). Some are conditional on available media/OS/rights (e.g. screenshots, HDR filters, audio EQ, full ASS support). Make the baseline audit before deciding what is truly new.

## 8. Where the rest of the product fits (four tabs unchanged)

| Surface | New destination/feature |
| --- | --- |
| **Home** | Kinetiq Brain search entry; franchise timeline/canon order; Just Released for My Favorites; Time-to-finish picker; hidden-spoiler recommendations; Source Health status; "Watch a random unwatched episode" with filters. |
| **Favorites** | Universal title groups by canonical identity; per-source editions visible; Missing Episodes, Upcoming Season, Unwatched, Rewatch, Dub Arrived; smart collections; Source Passport matching confidence; optional list import/export and tracker sync. |
| **Downloads** | Travel Vault; Quality Forge; Airplane Mode rehearsal; smart per-season queues; storage optimization and undo; file doctor; per-episode language inventory and playback verification. |
| **Settings** | Theme and RGB owner; accessibility and player button layout; Brain privacy/model provider; sync/account/device pair; watch-party safety; player presets; release notification rules; module trust; Discord Presence unchanged. |
| **Inside detail sheet** | Related seasons/specials/OVAs, legal availability, anime calendar, alt titles, voice cast, soundtrack metadata if legally sourced, episode ratings, cast/canon spoilers, watched-depth gated discussion. |
| **Inside module player** | The 170-candidate Power Deck above, contextual one-click actions, explanation of unsupported controls, and player-specific presets. |

## 9. Architectural contract — how to avoid a 4,000-line player

### Shared models

- **KinetiqMediaID**: stable internal UUID; optional canonical external IDs; aliases and edition ID.
- **ProviderMediaRef**: module ID, provider item ID, resource location and trust state. Never rewrite existing provider identifiers.
- **EpisodeIdentity**: season ID, episode number, absolute number, kind (episode/OVA/special/film/recap), release year/edition and language.
- **PlaybackAnchor**: content/episode identity, seconds, duration, last subtitle cue, track preferences, cut offset and confidence. Manual corrector with Undo.
- **ProgressEvent**: per-device timestamp and user intent (started/progress/completed/reset/rewatched) for conflict-free sync; reset and rewatch must not be overwritten by naive max-progress merge.
- **SourceCapability**: declared/observed player protocol, captions/audio, seek/PiP, rights and recent probe outcome; no speculative quality labels.
- **WatchRoomState**: matched episode, logical timeline, host state, participant readiness, drift samples; no video payload.
- **QualityForgeJob**: source authorized file, encoded rendition, presets, progress, thermal state, integrity and original rollback path.
- **PermissionLedger**: which local directory, user data and model service may be read or transmitted, and revocation timestamps.

### Swift ownership

The present project is **Swift 5 mode, iOS 17+**, with no explicitly configured strict concurrency/default actor isolation in the inspected project settings. Plan careful boundaries:

- Data models and diffable immutable snapshots are Sendable where appropriate.
- Shared source probing, subtitle retry queues, sync event storage and encoding jobs belong to focused actors; cancellation is explicit.
- UI-owned state lives on MainActor and narrow view dependencies; off-main work must not block playback or scrolling.
- User-facing features share an independent PlayerAction abstraction; each action declares label, icon, capability, availability reason, handler and diagnostic ID. No hard-coded dead buttons.
- Keep AVPlayer/module runtime adapters stable; add a unified playback capability layer rather than duplicating module versus local player UI.
- Componentize views by panel and feature. Avoid extending existing large ModulePlayerView.swift without extracting reusable model/controller/view slices; this protects compile performance and regression testing.
- VoiceOver, iOS 17 fallback and future iOS 26 APIs need explicit availability guards.

Proposed feature folders (not yet created):

    Kinetiq/Core/Identity/
    Kinetiq/Core/PlaybackContinuity/
    Kinetiq/Core/PlaybackCapabilities/
    Kinetiq/Core/Privacy/
    Kinetiq/Features/Brain/
    Kinetiq/Features/Player/PowerDeck/
    Kinetiq/Features/Player/SubtitleStudio/
    Kinetiq/Features/Downloads/QualityForge/
    Kinetiq/Features/Sync/
    Kinetiq/Features/WatchRooms/
    Kinetiq/Features/ReleaseRadar/
    KinetiqTests/PlayerCapabilityContractTests.swift
    KinetiqTests/IdentityAlignmentTests.swift
    KinetiqTests/QualityForgeRecoveryTests.swift
    KinetiqTests/SyncConflictTests.swift

### Resilience invariants

- N2 matching refuses cross-episode auto-seek on uncertain identity; a user confirmation is the recovery.
- N3 never modifies an original until replacement has been fully decoded/verified and written atomically with rollback.
- N4 syncs history/settings/manifests; actual offline video and protected sources do **not** cross-device automatically.
- N5 room telemetry is consented and ephemeral; server cannot access local media content.
- New AI tools cannot mutate watch state or enqueue 60 downloads without user confirmation.
- All-source search remains exhaustive among *installed trusted* modules; failures are surfaced, not treated as zero results.
- Show owner and model/feature versions in exported diagnostics; redact credentials and stream keys.

## 10. The honest 7 MB → 50 / 100 MB / larger decision

Increasing IPA size is not, by itself, a development milestone. Evaluate features by user value, RAM, app start, battery, heat, download size, licensing, maintenance and whether Apple already supplies the engine.

| Payload | Approximate footprint approach | Recommendation |
| --- | --- | --- |
| Universal identity graph, typed event sync, player deck, accessibility and quality telemetry | Mostly Swift code/data; do not assume fixed MB from LOC | **Ship in base app**. These are the important capabilities regardless of binary size. |
| Transcoding video via AVFoundation/VideoToolbox | Native Apple APIs included in OS; custom support code often far smaller than a full codec toolkit | **Ship native backend first**. Benchmark actual compatible export and audio/subtitle passthrough before introducing new libraries. |
| ASS/SSA anime subtitle renderer and fonts | Additional renderer/dependencies and font assets may add a nontrivial amount | **Optional if quality is proven**. Audit licensing and PiP/AVPlayer constraints. |
| Local voice transcription or subtitle generation | Downloadable ML model weights can run from tens to hundreds of MB or more, depending on model/quantization; Core ML also creates compiled caches | **Optional model pack**, downloaded with Wi-Fi/storage consent; never claim a specific size without measuring the selected artifact. |
| Local embedding or anime personalization model | Also model/runtime-dependent; compact model may fit more easily than general conversational LLM | **Consider only after offline evaluation** against deterministic Compass search. |
| Full conversational local language model | Typically substantially more runtime/model memory than a small metadata engine | Prefer Apple Foundation Models on supported devices, otherwise optional hosted provider or clearly disclosed deterministic fallback. Never silently promise "offline AI" on all iOS 17 devices. |
| Complete offline anime video files | Gigabytes of user data; not an IPA feature | Keep in managed user storage and explicit offline manifest. |

Apple's app-thinning documentation distinguishes compressed app size from the installed/thinned size. Keep an actual post-build size report in CI. A 7 MB IPA can expose powerful built-in OS frameworks; a 100 MB IPA can still be a poor product if it bundles dead libraries. Aim for usefulness, not a number.

### Compression example (not a guarantee)

For a 24-minute video at a **5 Mb/s video bitrate**, payload is about 900 MB (before audio, subtitles and container overhead). If an authorized HEVC encode can preserve acceptable subjective quality at **2 Mb/s**, video payload is about 360 MB, a 60% bitrate reduction. For other inputs, the result may be visually worse or even larger. The resolution can remain 1080p, but pixel dimensions do **not** guarantee the original fidelity. Measure on actual anime footage (flat gradients/banding, fast motion, fine line art, subtitles); compare reference and output with independent perceptual metric plus human inspection; never call it lossless. Preserve source, quality profile and cancel/rollback.

For streaming HLS and DRM-protected sources, do not turn Quality Forge into a stream capture/decryption tool. Only process properly obtained local files or downloadable media the source explicitly permits for this use.

## 11. Prioritization: what earns the first engineering hours

The six fixed priorities N1–N6 remain next. The ranking below is a **dependency order inside one eventual integration**, not a promise to split delivery into many user-visible micro-batches.

| Rank | System | User advantage | Risk | Why now |
| --- | --- | --- | --- | --- |
| **P0** | Identity Graph + Source Passport expansion (N2, J1) | One title, every edition, reliable resume | High | Without it AI, rooms, history and sync can report the wrong episode. |
| **P0** | Playback capability registry + Power Deck (N6) | Professional controls without hidden failure | Medium | Gives 170-candidate plan an organized/testable home. |
| **P0** | Caption/rewind recovery + Subtitle Studio (N6, J4) | Directly fixes real complaints | Medium | High differentiation for anime and already adjacent to existing PiP captions. |
| **P0** | Kinetiq Brain grounded tools (N1) | Ask for personal and cross-source actions | High | Build deterministic trusted tools before generative text. |
| **P0** | Safe Quality Forge proof of concept (N3) | Less offline storage with clear tradeoff | High | Can fail safely while preserving original; requires real device measurements. |
| **P1** | Sync event log and encrypted transport (N4) | Keep one library on every device | High | Must define merge and authentication rather than just "enable CloudKit". |
| **P1** | Persistent Watch Rooms (N5) | Social differentiator | High | Requires sync transport, accurate identity and lawful content delivery. |
| **P1** | Source Flight Control + Recovery Ledger (J3/J6) | Avoid repeated E01-style dead ends | Medium | Reuse existing diagnostics and server-switch UI. |
| **P1** | Release Radar + Spoiler Firewall (J7/J8) | New season alerts that mean what they say | Medium | Metadata exists; need per-provider availability honesty. |
| **P1** | Private Library Doctor / user-approved scoped folder scan (J5) | Makes local and remote media feel one | Medium | iOS sandbox grants restrict what can be indexed. |
| **P2** | Japanese Study Deck and transcript search | Distinctive learning use case | Medium/High | Requires subtitles and careful native renderer support. |
| **P2** | Social comments/reactions and moderation | Greater engagement | High | Only after room privacy, abuse handling and data retention are designed. |
| **P3** | Advanced video filters, AI-generated captions, scene semantic index | Specialist power tools | Very high | Hardware/rights/model-size gated; should not delay sound core playback. |

### Single-integration release gates

1. **Freeze existing contract:** no changes to RPC credential path; retain 4 tabs; preserve data IDs, source names, module trust and 06P1/06O functions.
2. **Build shared models and migration:** import existing history/downloads/favorites; no user-data loss; identity match confidence exposed and manual undo.
3. **Make player controls real:** map each proposed action to implementation and capability; inaccessible ones show a reason. Add a contract test for every action's availability and non-noop handler.
4. **Integrate private AI/search:** use public metadata, user-approved local index and source search; stress privacy, latency and error reporting.
5. **Integrate encoding and sync safely:** cancel/reboot/low-storage/thermal/dueling-devices cases; do not overwrite source or discard progress.
6. **Prove room semantics:** late join, offset mismatch, buffering, reconnect, moderation, spoiler levels, separate captions.
7. **Build with Xcode 26 CI and test on device:** simulator tests, physical iPhone landscape/PiP/AirPlay, one HLS and MP4, external PiP subtitle, airplane mode, module error cases, compare data before/after update.
8. **Check app size as evidence:** compressed IPA, installed/thinned size, optional model/cache sizes, frame rate, background CPU, memory and battery. No success claim without results.

### Must-not-break regression matrix

| Scenario | Expected |
| --- | --- |
| Existing Discord RPC token and status | Value/storage/format unchanged; no new log/upload path. |
| Trusted/untrusted module filtering | Only explicitly trusted modules execute; all trusted search results appear; timeout source reported. |
| Favorite's Source Passport current links | Existing confirmed mapping retained; no auto-removal. |
| Local media open + saved progress | Same file opens after migration and restart. |
| MP4 vs HLS streaming | Both retain seek, subtitles, progress and queue where supported. |
| PiP local/module/external subtitles | Existing working flows remain; unsupported pipeline shows truthful status. |
| Offline Downloads/Travel Vault | Current entries remain; file health and on-device offline test still required. |
| Player theme and 4-tab shell | No player-themed controls overlay main-app Settings or erase theme selections. |
| CPU/battery/thermal | Scans, encodes, and AI tasks cancel or suspend without UI freezes. |
| iOS 17 baseline / iOS 26 AI features | Build succeeds on baseline; new APIs gated and unavailable features explained. |

## 12. Research links and provenance

Research was conducted against official provider documentation, open-source project documentation, primary developer APIs and **anecdotal** 2025–2026 viewer discussions. Provider capabilities are time-sensitive and device/region/subscription-specific. This document makes **no statistically representative claims** about review frequency.

### Mainstream services, established features

1. Netflix, Smart Downloads: https://help.netflix.com/en/node/122916
2. Netflix, Downloads for You: https://help.netflix.com/en/node/119204
3. Netflix, Download Next Episode: https://help.netflix.com/en/node/101262
4. Netflix, saved Moments/clips: https://help.netflix.com/en/node/210664027435620
5. Crunchyroll, SharePlay: https://help.crunchyroll.com/hc/en-us/articles/20365134443668-Crunchyroll-Shareplay
6. Crunchyroll, release calendar: https://help.crunchyroll.com/hc/en-us/articles/22745725145364-Is-there-a-release-calendar-available
7. Crunchyroll, offline season download: https://help.crunchyroll.com/hc/de/articles/19203280609172-Wie-lade-ich-Inhalte-herunter-um-sie-offline-anzusehen
8. Crunchyroll, accessibility: https://help.crunchyroll.com/article/accessibility-features
9. Amazon Prime X-Ray AI recaps: https://www.aboutamazon.com/news/entertainment/amazon-prime-video-x-ray-recaps
10. Amazon AI video recap: https://www.aboutamazon.com/news/entertainment/ai-plot-summary-video-recaps-prime-video
11. Amazon Alexa+ scene jump: https://www.aboutamazon.com/news/devices/fire-tv-alexa-plus-jump-to-the-scene
12. Apple TV InSight and Enhance Dialogue: https://support.apple.com/en-al/guide/iphone/iphaec9fc22f/ios
13. YouTube, conversational Ask YouTube: https://support.google.com/youtube/answer/14110396
14. Plex Universal Watchlist and Discover: https://support.plex.tv/articles/universal-watchlist/
15. Plex Discover: https://www.plex.tv/discover/

### Anime, local-player and API foundations

16. Viki Learn Mode officially retired in 2023: https://support.viki.com/hc/en-us/articles/17924295071251-Sunsetting-of-Learn-Mode-Feature
17. mpv stable manual (A/B, subtitle delay, dual captions, seek): https://mpv.io/manual/stable/
18. mpv input commands: https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst
19. Jellyfin structured media segments: https://jellyfin.org/docs/general/server/metadata/media-segments/
20. Jellyfin chapter thumbnails: https://jellyfin.org/docs/general/server/metadata/chapter-images/
21. Infuse feature overview: https://firecore.com/infuse
22. AniList Media relations and schedules: https://docs.anilist.co/reference/object/media
23. AniList relation types (sequel, prequel, parent): https://docs.anilist.co/reference/enum/mediarelation
24. Trakt official scrobbling and watchlist API: https://developer.trakt.tv/
25. Simkl official API repository with API usage caveats: https://github.com/SIMKL/API
26. libass ASS/SSA renderer: https://github.com/libass/libass
27. Netflix VMAF perceptual comparison: https://github.com/Netflix/vmaf
28. FFmpeg licensing: https://ffmpeg.org/legal.html

### iOS engineering constraints, official sources

29. User-granted directory access/security-scoped URL: https://developer.apple.com/documentation/uikit/providing-access-to-directories
30. Group Activities entitlement: https://developer.apple.com/documentation/xcode/configuring-group-activities
31. Foundation Models availability: https://developer.apple.com/documentation/foundationmodels
32. Foundation Models tasks and supported devices: https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
33. VideoToolbox compression session: https://developer.apple.com/documentation/videotoolbox/vtcompressionsession
34. AVFoundation alternative video export: https://developer.apple.com/documentation/avfoundation/exporting-video-to-alternative-formats
35. AVPlayer stall counts: https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent/numberofstalls
36. Apple size reporting/app thinning: https://developer.apple.com/documentation/xcode/reducing-your-app-s-size
37. OpenAI Whisper official model table: https://github.com/openai/whisper
38. WhisperKit Core ML implementation: https://github.com/argmaxinc/argmax-oss-swift

### Firsthand user feedback, not prevalence estimates

39. Crunchyroll: hide accidental Continue Watching separately from erased history (Aug 2026): https://www.reddit.com/r/Crunchyroll/comments/1vrdd1p/things_i_wish_crunchyroll_would_change/
40. Crunchyroll: missed new seasons because dubs changed sort order (Jul 2026): https://www.reddit.com/r/Crunchyroll/comments/1uvuui1/why_is_there_no_way_to_view_if_there_is_anything/
41. Crunchyroll: misordered saved shows (Nov 2026): https://www.reddit.com/r/Crunchyroll/comments/1xmbjxs/new_episodes_from_my_list_dont_show_at_top_after/
42. Infuse: temporary captions after a 10-second rewind (Nov 2025): https://www.reddit.com/r/infusevideoplayer/comments/1ozzmps
43. Infuse: background subtitle retry after 503 + Retry-After (Oct 2026): https://www.reddit.com/r/infusevideoplayer/comments/1xe3czl/retry_external_subtitles_that_are_not_ready_yet/
44. Infuse: forced captions and progress concerns (Jul 2026): https://www.reddit.com/r/infusevideoplayer/comments/1vbo3vc/occasional_subs_not_displaying_a_couple_of_update/
45. Plex: lost Watch Together on newer clients (Sep 2025): https://www.reddit.com/r/PleX/comments/1nl7c2g/missing_watch_together/
46. Plex: Nov 13 2026 discussion of Watch Together's planned return, including persistent-room user wish: https://www.reddit.com/r/PleX/comments/1xutcme/watch_together_is_finally_coming_back/
47. Plex: subtitle adjustment control complaint (Oct 2026): https://www.reddit.com/r/PleX/comments/1xagh1h/did_they_remove_the_option_to_delay_and_speed_up/

## 13. Final decision

**Greenlight the six locked priorities as the next integrated Kinetiq expansion**, with universal identity and capability checks as the shared foundation. The most defensible unique experience is:

> **"I can search, understand, play, transfer, repair, learn from, save and watch the same anime with friends—across my trusted sources and my own files—without losing my place or my preferences."**

Do not call the implementation finished until CI, device tests, data migration, failure recovery and privacy controls all pass. Keep this specification as the durable checklist; mark future items with implementation paths and test evidence, not just feature names.


