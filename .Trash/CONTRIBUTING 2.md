# Contributing to Kinetiq

## Platform direction

- Treat iOS as the active application target.
- Use Swift and SwiftUI for the native interface, and AVFoundation for native media capabilities where appropriate.
- Keep the existing Quest/Android prototype intact unless a change explicitly targets that legacy project.
- Do not describe Android/Kotlin files as the iOS implementation.

## Engineering standards

- Keep changes aligned with `docs/ROADMAP.md`.
- Do not mark a feature complete without implementation, automated tests where applicable, and real-device verification where required.
- Keep platform-specific implementation behind clear interfaces so future platform support does not leak into shared product contracts.
- Treat module packages, metadata, subtitles, and network responses as untrusted input.
- Preserve the adapter boundary: external module formats must not define Kinetiq's internal API.
- Provide meaningful loading, empty, offline, and error states.
- Consider accessibility, privacy, performance, memory, and battery use in every phase.

## Build and signing safety

- Use GitHub Actions macOS runners for remote iOS builds; do not assume contributors have a local Mac.
- Keep signing certificates, private keys, provisioning profiles, passwords, and account credentials out of Git.
- Use GitHub Actions secrets only when a workflow genuinely requires them; never print secret values in logs.
- KSign is the planned final IPA signing/sideload tool. Do not claim an IPA is installable until its signing and installation have been verified on a device.
- App Store and TestFlight workflows are outside the current distribution scope.

## Module and network safety

- Validate module manifests and package contents before installation or execution.
- Apply execution limits and capability checks to extensions.
- Do not log credentials, cookies, private media paths, or signed media URLs.
