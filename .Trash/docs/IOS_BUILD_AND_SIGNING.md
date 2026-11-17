# iOS build, IPA, and KSign workflow

## Goal

Build Kinetiq remotely and produce an IPA that can be signed with KSign and installed on the user's iPhone. The project does not require App Store or TestFlight distribution.

## Source and build workflow

1. Edit source and documentation in Working Copy on iPhone.
2. Commit and push to the GitHub repository.
3. GitHub Actions runs on a macOS runner with the required Xcode toolchain.
4. The workflow resolves dependencies, runs tests, builds the iOS target, and prepares the IPA/build output.
5. Upload build outputs and diagnostic reports as GitHub Actions artifacts.
6. Download the artifact on iPhone.
7. Use KSign with the user's own compatible certificate/profile/signing method.
8. Install the signed app and verify launch, permissions, playback, and persistence on the physical device.

## Important distinction: build versus signing

A successful Swift compile or CI run does not automatically mean the resulting IPA can be installed. iOS installation depends on a valid signing setup and the applicable provisioning/distribution method. KSign is the planned signing handoff; its exact requirements depend on the certificate and signing workflow selected by the user.

The build pipeline must report these stages separately:

- Compilation and tests passed.
- IPA packaging completed.
- IPA signing completed (if signing is performed in CI; otherwise explicitly marked as a manual KSign step).
- Installation and launch verified on-device.

Never label a build as device-ready based on compilation alone.

## Secrets and signing assets

- Never commit `.p12`, `.mobileprovision`, private keys, passwords, or account credentials.
- Do not paste signing secrets into chat or issue comments.
- If signing is automated later, store required values in protected GitHub Actions secrets and avoid printing them in logs.
- Prefer keeping the initial workflow unsigned and performing the signing handoff with KSign, unless the user deliberately chooses a secure CI-signing design.

## CI design notes

- Use a macOS GitHub Actions runner because Xcode and Apple's iOS build tools require macOS.
- Pin or explicitly select the Xcode version in the workflow and record it in build logs.
- Run Swift tests and any available static checks before packaging.
- Cache dependencies only where cache correctness is maintained.
- Upload the IPA and diagnostic reports with clear artifact names and retention periods.
- Keep the existing Android/Quest workflow separate; do not mix APK and IPA outputs in one ambiguous artifact.

## Device verification checklist

- [ ] IPA is signed with the intended KSign setup.
- [ ] KSign reports successful signing.
- [ ] App installs on the target iPhone.
- [ ] App launches without immediate termination.
- [ ] Navigation and appearance settings work.
- [ ] Local data persists after relaunch.
- [ ] Relevant permissions and file access behave as expected.
- [ ] Logs and crash reports are reviewed for failures.

## Apple reference

Apple documents exporting an iOS app as an IPA and distributing it outside the App Store using an appropriate signing and provisioning method: [Export an iOS app](https://help.apple.com/xcode/mac/current/en.lproj/dev23ea8b877.html) and [Distribute to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
