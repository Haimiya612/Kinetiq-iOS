# Kinetiq

**Fluid streaming, limitless extensions.**

Kinetiq is a modular media platform built around a polished player, an extensible source engine, and a personal media library.

## Product family

- **Kinetiq** — the platform and ecosystem.
- **Kinetiq Player** — the application. *Motion. Media. Modular.*
- **Kinetiq Engine** — the source, discovery, metadata, and extension framework. *Your streams, your modules, your rules.*

## Current platform direction

**The active development target is iOS.** The initial iOS application will be built with Swift and SwiftUI, with AVFoundation used for native media playback where appropriate.

The existing Quest/Android application is a working early prototype and is retained as historical project work. This documentation update does not convert its Kotlin/Gradle source into an iOS application. iOS implementation will be developed as a separate native app target/project so the existing prototype remains intact.

## Development workflow

The project is designed around an iPhone-first source-control workflow:

1. Edit and manage repository files in Working Copy on iPhone.
2. Commit and push changes to GitHub.
3. Use GitHub Actions with a macOS runner for Xcode/Swift builds and automated checks.
4. Download the resulting build artifact from the workflow run.
5. Sign the IPA with KSign using the user's own compatible signing setup, then install and test on the iPhone.

A local Mac or local Xcode installation is not assumed. GitHub Actions is the remote build environment. Signing assets, certificates, provisioning profiles, and passwords must never be committed to the repository or pasted into chat.

## Distribution

Kinetiq's current distribution plan is direct sideloading. The intended deliverable is an iOS IPA that can be signed with KSign. App Store and TestFlight distribution are not required for this development plan.

The exact signing method and certificate/profile requirements depend on the signing setup used with KSign. A successful CI compilation alone does not prove that an IPA is installable; signing and on-device installation must be verified separately.

## Planned iOS foundation

- Native Swift application structure.
- SwiftUI interface and adaptive light/dark appearance.
- Reusable motion system, polished transitions, loading/empty/error states, and responsive micro-interactions.
- Random launch tagline selection from the three approved taglines, avoiding the same tagline twice consecutively.
- AVFoundation playback foundation.
- Persistent settings and structured diagnostics.
- GitHub Actions macOS build and test workflow.
- IPA packaging and KSign sideload verification.

Playback integrations, source discovery, module execution, and personal-library features are not considered complete until implemented and tested.

## Approved launch taglines

1. “Motion. Media. Modular.”
2. “Your Streams, Your Modules, Your Rules.”
3. “Fluid streaming, limitless extensions.”

## Roadmap and project status

See [docs/ROADMAP.md](docs/ROADMAP.md) for the master plan and [docs/IOS_BUILD_AND_SIGNING.md](docs/IOS_BUILD_AND_SIGNING.md) for the iOS build and sideload workflow.

A checked planning item means the decision or documentation exists; it does not mean a feature has shipped. Implementation status requires code, automated tests where applicable, and verification on a real device.
