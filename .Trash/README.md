# Kinetiq

**One platform. Every kind of media.**

Kinetiq is an independent native iOS media platform built around a polished
player, a personal media library, and an extensible content engine.

The long-term goal is to bring video, anime, manga, images, music, and
personal media sources into one unified application.

Kinetiq is heavily inspired by Synthetiq Player. Its approach to combining
different media experiences, content discovery, and extensible sources
serves as an important product reference.

Kinetiq is being developed independently, with its own native architecture,
visual identity, playback systems, and security model. The goal is not to
copy another application, but to build an even more capable media platform.

## Current Development

**Active target:** iOS

**Current phase:** Phase 2 -- Playback & Player Experience

Kinetiq is being developed using Swift, SwiftUI, AVFoundation, and AVKit.

The current application includes:

- Native SwiftUI application architecture.
- Five main destinations: Home, Discover, Library, Modules, and Profile.
- Initial Kinetiq design language and app icon.
- Persistent appearance preferences.
- Launch tagline selection.
- First-launch What's New experience for unseen release notes.
- Local video importing through Files.
- Local video importing through Photos.
- Full-screen AVPlayer-based video playback.
- Playback speed controls.
- Aspect-ratio controls.
- Audio track selection.
- Embedded subtitle selection.
- Sleep timer.
- Persistent playback history.
- Automatic playback resume.
- Continue Watching.
- Playback progress tracking.
- Completed-media handling.
- Persistent playback queues.
- Next and Previous navigation.
- Shuffle and Repeat.
- Queue selection, removal, and reordering.
- Play Next.
- Queue persistence and unavailable-file handling.

The Modules and Profile destinations currently provide the navigation
foundation for future functionality. The complete module ecosystem,
account systems, and remote content functionality are still planned.

The advanced player experience is also still being developed. Thumbnail
caching, technical media metadata, Picture-in-Picture, AirPlay,
double-tap seeking, and enhanced retry controls must be implemented
and verified before being described as completed.

## Product Direction

Kinetiq is inspired by the convenience of modern media players, but it is
not intended to be a rebranded copy of another application.

The product is being built around these principles:

- Native-first implementation.
- Local-first media management.
- Privacy and user control.
- Reliable playback.
- Recoverable errors.
- Extensible architecture.
- Consistent design across media categories.
- Independent implementation and visual identity.
- No decorative controls that do nothing.
- Automated testing and physical-device verification.

Synthetiq Player is one of the main product references used during research.
Its public features and module documentation inform Kinetiq's roadmap,
but Kinetiq maintains its own implementation and architecture.

## Product Identity

- **Kinetiq** -- The platform and ecosystem.
- **Kinetiq Player** -- The application. *Motion. Media. Modular.*
- **Kinetiq Engine** -- The planned source, discovery, metadata, and
  extension framework. *Your streams, your modules, your rules.*

Approved launch taglines:

1. "Motion. Media. Modular."
2. "Your Streams, Your Modules, Your Rules."
3. "Fluid streaming, limitless extensions."

## Roadmap

The master development roadmap is available here:

[docs/ROADMAP.md](docs/ROADMAP.md)

The roadmap covers:

1. Foundation & Application Architecture
2. Playback & Player Experience
3. Advanced Media Library
4. Discovery & Content Catalogue
5. Kinetiq Module Engine
6. Streaming Engine
7. Manga & Image Reader
8. Music Experience
9. Personal Media Servers & Living Room Experience
10. Offline, Downloads & Synchronization
11. Personalization & Advanced Settings
12. Release, Testing & Optimization

## Development Workflow

The project is maintained through GitHub and Working Copy.

1. Update the project files in Working Copy.
2. Commit and push changes to `main`.
3. GitHub Actions runs the configured build and test workflow.
4. The workflow selects a compatible macOS runner and Xcode installation.
5. Simulator tests run when an available iPhone simulator is detected.
6. The workflow builds an unsigned iOS application.
7. The workflow packages the application as an unsigned IPA.
8. Download the `Kinetiq-iOS-Unsigned-IPA` artifact.
9. Sign the IPA using KSign and a compatible signing setup.
10. Install and verify the application on a physical device.

The default workflow runner is `macos-26-intel`. Manual workflow
dispatch also allows selecting from the configured macOS runner options.

The workflow prefers Xcode 26.3 when that installation is available
and falls back to another available Xcode installation when necessary.

The project does not require a local Mac for the GitHub Actions build
workflow. The remote workflow handles simulator testing, unsigned builds,
and IPA packaging.

**Important:** A successful CI build does not mean the IPA is signed
or verified on a physical device. Signing and device installation
remain separate steps.

The current distribution workflow uses an unsigned IPA and a manual
KSign signing handoff. App Store and TestFlight distribution are not
part of the current plan.

For the full process, see:

- [iOS Build and Signing Guide](docs/IOS_BUILD_AND_SIGNING.md)
- [First iOS Build Guide](docs/IOS_FIRST_BUILD.md)

## Build Locally

Open `Kinetiq.xcodeproj` in Xcode and select the `Kinetiq` scheme.

The command-line equivalent is:

```sh
xcodebuild test \
  -project Kinetiq.xcodeproj \
  -scheme Kinetiq \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

The project's iOS deployment target is iOS 17.0.

## Project Structure

The native iOS application is organized around:

- `Kinetiq/App` -- Application entry point and main navigation.
- `Kinetiq/Core` -- Shared design, branding, and storage infrastructure.
- `Kinetiq/Features/Home` -- Home screen and Continue Watching.
- `Kinetiq/Features/Library` -- Local media library and playback systems.
- `Kinetiq/Features/Settings` -- Application preferences and What's New.
- `Kinetiq/Resources` -- App icons and visual assets.
- `KinetiqTests` -- Automated tests.
- `docs` -- Development roadmap and build documentation.

The project uses a manually maintained Xcode project file. New Swift
source files must be registered in `Kinetiq.xcodeproj/project.pbxproj`
when required by the project structure.

## Earlier Quest / Android Prototype

The earlier Quest/Android prototype is preserved in its separate repository.
This iOS project is focused on the native Apple application and does not
modify the separate prototype.

## Development Notes

- Preserve existing functionality when introducing new features.
- Prefer complete, tested integrations over decorative placeholders.
- Keep playback and source resolution separated.
- Keep external module execution isolated from unrelated application data.
- Update the roadmap when implementation status changes.
- Do not mark a feature complete until its implementation and relevant
  verification have been completed.

---

*Kinetiq -- One platform. Every kind of media.*
