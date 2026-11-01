# Kinetiq

**Fluid streaming, limitless extensions.**

Kinetiq is a modular media platform built around a polished player, an extensible source engine, and a personal media library.

## Current direction

**iOS is the active development target.** The native app is built with Swift and SwiftUI, with AVFoundation planned for playback. The earlier Quest/Android prototype is preserved in its separate repository and is not modified by this project.

## iOS foundation status

The first native foundation package includes:

- A native SwiftUI app target and shared Xcode scheme.
- A three-tab navigation shell: Home, Library, and Settings.
- An initial responsive Kinetiq home screen and app icon.
- System, light, and dark appearance selection persisted with `AppStorage`.
- Random launch tagline selection, avoiding the previous launch's tagline.
- Unit tests for tagline selection.
- A macOS GitHub Actions workflow that runs simulator tests, builds an unsigned device app, and packages an unsigned IPA for the KSign handoff.

**Important:** this is the first source foundation, not a finished media player. The CI build and on-device KSign install still need to be verified after importing the files.

## Development workflow

1. Import the ZIP contents into the root of this repository using Working Copy.
2. Commit and push the files to `main`.
3. GitHub Actions runs on a macOS runner and performs tests/build/package steps.
4. Download the `Kinetiq-iOS-Unsigned-IPA` artifact.
5. Sign the IPA with KSign using your own compatible signing setup, then install and test on your iPhone.

The project does not require a local Mac. App Store and TestFlight distribution are not part of the current plan.

## Build locally (on macOS)

Open `Kinetiq.xcodeproj` in Xcode and select the `Kinetiq` scheme. The command-line equivalent is:

```sh
xcodebuild test -project Kinetiq.xcodeproj -scheme Kinetiq \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The GitHub Actions workflow pins Xcode 26.3 on the `macos-15` runner image. The app deployment target is iOS 17.0.

## Product identity

- **Kinetiq** — the platform and ecosystem.
- **Kinetiq Player** — the application. *Motion. Media. Modular.*
- **Kinetiq Engine** — the source, discovery, metadata, and extension framework. *Your streams, your modules, your rules.*

Approved launch taglines:

1. “Motion. Media. Modular.”
2. “Your Streams, Your Modules, Your Rules.”
3. “Fluid streaming, limitless extensions.”

See [docs/ROADMAP.md](docs/ROADMAP.md) for the master plan and [docs/IOS_BUILD_AND_SIGNING.md](docs/IOS_BUILD_AND_SIGNING.md) for the signing handoff.
