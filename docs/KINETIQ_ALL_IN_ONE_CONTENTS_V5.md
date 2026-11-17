# Kinetiq all-in-one source archive — V5

This source-tree package starts from the exact user-provided
`Kinetiq-iOS-main.zip` (all **124 original regular files** confirmed present)
and retains the original `.github`, Xcode project, assets, tests, documentation
and recoverable `.Trash` contents. The archive's only top-level directory is
`Kinetiq-iOS-main/`; it is not an IPA and does not contain a compiled binary.

## Actual source additions and integrations

| Product system | Concrete file(s) | Status |
| --- | --- | --- |
| Confirmed cross-source Scene Passports, private notes and bookmarks | `Kinetiq/Core/Media/KinetiqContinuity.swift` | Implemented; physical-device playback test pending |
| Local-first Brain + public AniList results | `Kinetiq/Features/Discovery/KinetiqBrain.swift` | Implemented; requires network for public search |
| Opt-in on-device **generative multi-turn** Brain using Apple Foundation Models | `Kinetiq/Features/Discovery/KinetiqNativeBrain.swift` | Implemented behind iOS 26/device/model readiness gate; unsupported devices retain grounded tools |
| Personal viewing insights | `Kinetiq/Features/Discovery/KinetiqViewingInsights.swift` | Implemented locally |
| Read-only Library Doctor, imported storage insights and exact duplicate detection | `Kinetiq/Features/Library/KinetiqLibraryDoctor.swift` | Implemented with on-demand SHA-256 verification and finite scan budget; never deletes files |
| Offline local-video HEVC Quality Forge | `Kinetiq/Features/Downloads/KinetiqQualityForge.swift` | Implemented, original preserved; export and quality need on-device evaluation |
| Portable Travel Vault offline manifest | `Kinetiq/Features/Downloads/KinetiqTravelVault.swift` | Implemented JSON export of saved-episode preflight results, quality, language, subtitles and bytes; user can hide title/source names |
| Manual Sync Vault file exchange and merge | `Kinetiq/Core/Media/KinetiqSyncVault.swift` | Implemented; deliberately not automatic cloud sync |
| Watch plans with QR and shareable timecode invitation | `Kinetiq/Features/Social/KinetiqWatchPlans.swift` | Implemented; deliberately not a synchronized room |
| Player Power Deck: ± seek step, undo, exact jump, profiles, A/B loop, caption replay, bookmark notes/jumps, confirmed-source resume, Brain shortcut | `Kinetiq/Features/Modules/ModulePlayerView.swift` | Implemented; hardware/stream regression pending |
| Home Brain shortcut | `Kinetiq/Features/Home/HomeView.swift` | Implemented without adding a tab |
| Navigation and safe progress import | `Kinetiq/Features/Settings/SettingsView.swift`, `Kinetiq/App/MainTabView.swift` | Implemented; four tabs unchanged |
| Contracts | `KinetiqTests/KinetiqPowerCenterContractTests.swift` | Swift tests registered; pending macOS CI run |

## Explicitly preserved

- All four tabs: Home, Favorites, Downloads, Settings.
- Current Discord RPC transport and Discord presence settings **byte-for-byte
  unchanged** from the source ZIP.
- Original stream handling, module names, subtitles, PiP, AirPlay and existing
  queue/download mechanisms. No alterations to `.github` workflows.
- Both research documents are available under `docs/research/`.

## Not silently claimed as shipped

- Live synchronized watch parties, chat/moderation and multi-device presence.
- Automatic end-to-end encrypted cloud/peer synchronization or account pairing.
- Frame-accurate cross-edition video alignment without human confirmation.
- Extreme or lossless recompression of already-compressed streams.
- On-device generative AI on devices without Apple Intelligence support.
- Every speculative feature/control in the large research PDFs. Those are
  included *as product requirements and designs*, not hidden dead buttons.

## Build/test decision

The user has elected to perform one combined GitSync/iPhone regression later.
Do not label this ZIP build-passing until the existing Xcode test and unsigned
IPA workflows are run. The Python roadmap tests pass locally; Swift cannot be
compiled or simulated on this Linux host.
