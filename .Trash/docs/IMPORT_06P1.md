# Import combined 06O + 06P1 into Working Copy

Base GitHub commit: `b5e832ca0d8d1f6720f06f89df07b6108c81f358`.
This is a cumulative delivery: it contains the previous 06O season-download
changes and the new 06P1 cross-source search changes. **You do not need to
import the earlier 06O ZIP separately.**

This refreshed archive also contains a complete replacement
`Kinetiq/Features/Downloads/KinetiqOfflineDownloads.swift` to fix the
`cannot find 'path' in scope` compiler error at the HLS completion accounting
step reported in GitHub Actions run 43881159501.

1. Check the latest `Kinetiq-iOS` commit in Working Copy. If it differs from
   the base above, compare the overlapping files before replacing them.
2. Extract the delivery ZIP in Files on your iPhone.
3. Copy each contained file into the corresponding location under the root
   of `Kinetiq-iOS`, preserving the relative path. Replace only the named
   files, **not** the entire `Kinetiq`, `docs`, or `KinetiqTests` folder.
4. Review the Working Copy diff. The package intentionally makes no changes
   to `Kinetiq.xcodeproj/project.pbxproj`, runtime package identities, user
   data, existing modules, or stored history.
5. Commit/push to GitHub and run the existing Xcode Actions workflow. The
   Linux workspace that prepared this ZIP could not compile Swift/UIKit.
6. If CI passes, run the acceptance checks in
   `docs/BATCH_06P1_SOURCE_SEARCH.md` and
   `docs/IMPORT_06O_SEASON_DOWNLOADS.md` on your iPhone.

This release changes discovery and navigation, but does not automatically
transfer Favorites or episode positions between different modules. The user
must select the result they wish to open; title similarity alone is not
treated as verified media equivalence.
