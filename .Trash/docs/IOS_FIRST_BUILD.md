# iOS Foundation — First Import

## What this package adds

```text
Kinetiq.xcodeproj/
  project.pbxproj
  xcshareddata/xcschemes/Kinetiq.xcscheme
Kinetiq/
  App/
  Core/
  Features/
  Resources/Assets.xcassets/
KinetiqTests/
.github/workflows/ios-ci.yml
```

The app currently has a native SwiftUI shell with Home, Library, and Settings tabs. Theme preference is stored locally. The launch tagline is selected at startup and the last selection is stored so the next launch can avoid repeating it.

The Library tab is intentionally an empty-state placeholder. Playback, module discovery, network sources, and library persistence are not implemented yet.

## Import using Working Copy

1. Download and unzip `Kinetiq-iOS-Foundation.zip` on your iPhone.
2. In Working Copy, open the `Haimiya612/Kinetiq-iOS` repository.
3. Import/merge the **contents** of the ZIP into the repository root. Do not create a nested `Kinetiq-iOS-Foundation` directory.
4. Confirm that `Kinetiq.xcodeproj`, `Kinetiq`, `KinetiqTests`, and `.github` appear at the repository root.
5. Review the changed files, then commit and push to `main`.
6. Open the Actions tab on GitHub and inspect the `iOS CI` run.

## Expected CI outputs

- Simulator unit tests.
- Unsigned Release device build.
- `Kinetiq-unsigned.ipa`, packaged for a later signing handoff.
- Test result bundle and build logs for troubleshooting.

The IPA is intentionally unsigned. KSign is the separate signing step. A successful workflow does not count as an on-device verification until the signed app installs and launches on the iPhone.

## First-run checklist

- [ ] Working Copy shows all files at the repository root.
- [ ] The `iOS CI` workflow starts after the push.
- [ ] Simulator tests pass.
- [ ] The Release device build passes.
- [ ] The unsigned IPA artifact is uploaded.
- [ ] KSign signs the IPA successfully.
- [ ] The signed app installs and launches on the iPhone.
