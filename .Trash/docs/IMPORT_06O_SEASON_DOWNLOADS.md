# Import Batch 06O into Working Copy

Source baseline: `Haimiya612/Kinetiq-iOS` commit
`b5e832ca0d8d1f6720f06f89df07b6108c81f358` (16 November 2026).

The package preserves paths **relative to the root of `Kinetiq-iOS`**.

1. In Working Copy, open your `Kinetiq-iOS` checkout and make sure you have
   committed or backed up any overlapping local changes first.
2. Download the delivery ZIP and extract it with the iPhone Files app.
3. Copy the ZIP's `Kinetiq/` files into the same folders in Working Copy,
   choosing **Replace** for the existing Swift files. Do the same for `README.md`
   and the `docs/` files. **Do not** replace the entire `Kinetiq` folder or
   the whole `docs` folder. Keep every other file unchanged.
4. The `.pbxproj` does **not** need changing: both modified app Swift files and
   the test file were already part of the Xcode project.
5. Review the Working Copy diff; commit and push to `main` only if it matches
   your intended changes. GitHub Actions should then attempt the Swift build.
6. If CI fails, share the first compiler error and the file/line. No Swift
   compiler or iOS Simulator was available in the environment that prepared
   this package, so an unsigned IPA is not guaranteed.

## Test on iPhone

1. Open an installed, permitted anime module. Pick a title with a working
   direct MP4 or HLS server and known episodes (e.g., Roshidere if supported).
2. Open its Episodes tab. Choose a season when the source explicitly labels
   seasons; otherwise tap **Download All Listed Episodes**.
3. Check the title, total count, Sub/Dub availability, quality and Wi-Fi
   preference. Queue a small source first, then check the Downloads tab.
4. Verify the status counts and that failures identify individual episodes.
   Repeat and make sure nonfailed entries are skipped, not duplicated.
5. Stop preparing partway through one batch; confirm that previously queued
   entries continue. Close and reopen the app; completed downloads and
   individual background tasks should persist, but an unfinished resolver
   batch is not automatically restarted.
6. Verify MP4 and HLS playback in Airplane Mode, subtitle choices, actual
   saved quality, storage display and delete cleanup.

Important: The new batch UI only prepares a queue of the existing native
download tasks. It does **not** repair nonfunctional sources such as the
reported Synthetiq Flux source, download DRM-protected video, or introduce
HEVC re-encoding or ZIP-based media compression. These are separate tasks.
