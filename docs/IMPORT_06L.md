# Importing the Batch 06L checkpoint (iPhone / Working Copy)

This archive contains the **current working checkpoint**, including earlier
uncommitted 06K/metadata/download work that was already present when 06L was
started. It is deliberately not a minimal 06L-only patch: the updated Xcode
project and Settings screen reference those existing files.

1. In the iOS Files app, extract the archive to a new folder.
2. Open your **Kinetiq-iOS** checkout in Working Copy.
3. Copy the extracted `Kinetiq/`, `KinetiqTests/`, `docs/` and
   `Kinetiq.xcodeproj/` contents into the corresponding checkout folders.
   Keep the same nested paths. Replace same-name files when prompted.
4. Review Working Copy's change list. There should be **no deletion** of
   unrelated repository files.
5. Commit and push to the branch you use for GitHub Actions.
6. Build the IPA, and complete `docs/TEST_06L.md` on your iPhone.

Do not extract or commit any personal Discord token. This archive contains
only source code, project wiring, tests, and documentation. Use the new secure
entry field **on-device only** after invalidating any previously exposed token.

If your checkout has advanced beyond the checkpoint, review differences
before replacing files. No live Discord login or iOS build was performed by
this checkpoint's author.
