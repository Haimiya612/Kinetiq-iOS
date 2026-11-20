# iPhone-only ZIP → GitHub automatic commit

**Problem:** GitSync is unavailable. **Solution:** Use GitHub's website once to
install an import workflow. Thereafter, upload one complete Kinetiq source ZIP
through Safari; GitHub Actions validates, replaces and commits the files.

## One-time setup (no PC, no paid Git app)

1. Sign in to `https://github.com/Haimiya612/Kinetiq-iOS` in Safari.
2. Open **Add file → Create new file**. Enter this exact filename:
   `.github/workflows/import-kinetiq-zip.yml`.
3. Paste the **complete contents** of the matching `.yml` in this package.
   Commit to the default `main` branch. This is the only step that must be
   done by pasting text once; uploading the ZIP does not install its workflow.
4. In **Settings → Actions → General**, check that Actions is enabled and the
   workflow token can create repository commits (Contents write permission).
   Branch protection/rulesets can still block a bot push.

## Every new cumulative batch

1. Save the provided **full source ZIP**, not a changes-only/patch ZIP, to
   iPhone Files. Do not rename the internal `Kinetiq-iOS-main/` folder.
2. On GitHub.com, open the repository's main page and select
   **Add file → Upload files**.
3. Upload the source ZIP at the repo root, named **exactly**
   `Kinetiq-update.zip`, then commit to `main`.
4. Open **Actions → Import Kinetiq Source ZIP**. The run starts after the
   upload commit. If it doesn't, use **Run workflow** manually.
5. Confirm a green `Validate ZIP, replace project, commit` job and a newer
   `Import Kinetiq cumulative source ZIP` commit in repository history.
6. Run the normal **iOS CI** workflow *manually* to verify compilation/tests.
   GitHub deliberately does not fire other push workflows when the import
   workflow pushes via its built-in token.

## Safety and scope

- ZIP must be <= 25 MiB for GitHub browser upload and contain the **complete**
  project with Swift sources, project.pbxproj, tests and docs.
- Validation rejects path traversal, symlinks, duplicate-case entries, archive
  explosions and incomplete source trees before any project file is replaced.
- The importer **replaces** `Kinetiq/`, `KinetiqTests/`,
  `Kinetiq.xcodeproj/`, `docs/` and, if supplied, `scripts/` and `tests/`.
  New files inside those folders that you have not included in the ZIP will
  disappear from the new commit. They remain recoverable in Git history.
- It **preserves `.github/`**, other unrelated top-level files and repository
  settings. It removes the uploaded `Kinetiq-update.zip` from the
  newest commit after processing, though its blob remains in the upload commit.
- A GitHub repository branch protection rule can prevent direct bot commits;
  if that happens, the workflow visibly fails at `git push` and requires a
  user-chosen branch/PR workflow instead.

**Do not upload a patch-only ZIP to this importer:** missing source files will
be interpreted as absent and deleted from the allowlisted folders.
