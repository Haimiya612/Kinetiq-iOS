# Kinetiq master development programme — 395 references

This document protects the owner's **master batch numbering** and requirements
from accidental relabelling when a small corrective delivery happens to use
a similar name. This map is transcribed from the owner-provided catalogue on
20 November 2026. The full underlying 395-entry ledger is not bundled with
this document, so catalogue-by-catalogue acceptance must be reconciled against
the original ledger before any batch is marked complete.

| Batch | Authoritative scope | Ref IDs | Count |
| --- | --- | --- | ---: |
| M01 | Universal Identity, Source Flight Control & Continuity | R033–R050, B095–B117, B187–B196 | 51 |
| M02 | Season Downloads, Travel Vault & Quality Forge | R123–R138, B162–B186 | 41 |
| M03 | Player Pro, Timeline & Episode Navigation | R001–R032, B001–B038 | 70 |
| M04 | SubStudio & Japanese Language Tools | R067–R092, B069–B094 | 52 |
| M05 | Smart Media Library & Collections | B142–B161 | 20 |
| M06 | Kinetiq Brain AI, Discovery & Release Radar | R108–R122, B118–B141 | 39 |
| M07 | Video Studio, Audio Studio & Player Parity | R051–R066, R093–R107, B039–B068 | 61 |
| M08 | Watch Rooms, Social & Privacy | R139–R153, B197–B214 | 33 |
| M09 | Accessibility, Diagnostics & Recovery | R154–R170, B215–B225 | 28 |
| **Total** | **Nine independently owned major batches** | **R001–R170, B001–B225** | **395** |

Additional unnumbered-in-the-original-ledger programmes:

- **M10:** Complete all 13 streaming-inspired experiences, preserving Home,
  Favorites, Downloads and Settings tabs and RGB Studio.
- **M11:** Native manga, music, servers and living room/Apple TV expansion.
- **M12:** Release integrity, migration safety, Xcode/CI, regression testing,
  manifests and cumulative source ZIP delivery.

## Honest implementation and acceptance status

- M01–M04 have source deliveries and partial contracts/handoffs in this repo.
  They are **not automatically 100% complete** across all ledger references.
- **M04 iPhone baseline:** 9 PASS, 1 NOT TESTED (Japanese transcript/Romaji
  lacked a suitable Japanese subtitle track).
- **M05A (20 November):** A *small corrective patch series* for player errors,
  subtitle controls, search ranking, player personalization, Brain history,
  Discord lifecycle, and related M04 feedback. **M05A does not count as
  satisfying M05 Smart Media Library B142–B161.**
- M05's 20 Smart Library items remain to be individually audited and built.
- M06–M12 remain roadmap programmes until implementation and acceptance prove
  otherwise. Existing work from these domains may be reused after audit.
- App version stays **0.3.0**. No claim of successful macOS Xcode compilation
  is implied by the source ZIP or the GitHub importer.

## ZIP import rule

The one-time GitHub workflow `.github/workflows/import-kinetiq-zip.yml` accepts
a full cumulative source tree in `Kinetiq-update.zip` at the repo root. It mirrors
allowlisted code/docs folders (removing stale files) and commits the result.
It **never imports `.github/` from the ZIP**, protecting existing workflows.
The workflow must be installed directly into GitHub *once* before this method
works. See `docs/IPHONE_ZIP_TO_GITHUB.md` for the exact phone-only steps.
