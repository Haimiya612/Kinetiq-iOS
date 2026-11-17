# Kinetiq complete merged project — V1 + V2 source

Prepared: 17 November 2026. **App marketing version is still 0.3.0.**

## What was combined

This one-folder project archive overlays the full Kinetiq V1+V2 development
source onto the owner's `Kinetiq-iOS-main(3).zip` upload. The latter was
verified byte-for-byte identical to the original source ZIP used for V1/V2,
so there were no conflicting personal edits to choose between. Comparing
the resulting project tree with the supplied V2 full-source ZIP yielded no
differences before this import guide was added.

The archive contains the original project content, application assets,
`Kinetiq.xcodeproj/project.pbxproj`, test target, GitHub workflow files,
and all V1/V2 Swift additions. Both master blueprints are retained in
`docs/research/`. It is **source code**, not an IPA and not a verified iOS build.

## Important preservation rules

- All four bottom tabs: Home, Favorites, Downloads, Settings.
- The existing Discord Rich Presence implementation and settings are unchanged.
- The app marketing version remains `0.3.0`; the V1/V2 labels identify source
  delivery stages, not app-version upgrades.
- No files were committed, pushed, or edited on the owner's GitHub repository.
- Local Library data and streaming-module data remain separate.
- The Actions Run repair was intentionally deferred by the owner.

## Import into an existing GitSync checkout on iPhone

1. Back up or commit any **new local edits** in GitSync first. This merged ZIP
   was produced from the uploaded project, not from hypothetical later edits.
2. Extract this ZIP in Files. Open its single top-level folder:
   `Kinetiq-iOS-main/`.
3. Copy its **contents** into the root of the existing Kinetiq-iOS checkout.
   Preserve the folder layout and replace existing matching project files.
   **Do not copy the wrapper folder into another `Kinetiq-iOS-main` folder.**
4. Include `Kinetiq.xcodeproj/project.pbxproj` so Xcode sees all new Swift files.
   Preserve the checkout's own `.git` directory; it is not included here.
5. Check the GitSync changes and commit only after confirming they match the
   intended update. Do not separately apply the older V1 or V2 patch ZIPs.

## Build and user acceptance

No Xcode or iOS SDK is installed on the construction host. The previous V2
source passed fourteen available Python integration checks, but native
XCTest, unsigned IPA production, module playback, PiP, offline downloads,
theme switching, and Discord activity must be tested with Xcode/iPhone.

Start with the four tabs, source selection, module playback/PiP/subtitles,
Discord, individual and season downloads, Quick Deck, Spoiler Shield, Brain,
and Sync Vault. See `KINETIQ_ALL_IN_ONE_V2_HANDOFF.md` for exact checks,
limitations, and remaining blueprint work.

## Honest implementation boundaries

Automatic encrypted cloud sync, live synchronized watch rooms, a complete
manga/music experience, every proposed research feature, and lossless extreme
compression are **not** fully implemented. Quality Forge is a native optional
HEVC re-encode for local video with normal quality/size tradeoffs.
