# Kinetiq 06K.11 — Episode Metadata & Anime Details

## Scope

- Keep the module's episode ID, original URL, source name, Sub/Dub flags and
  watch/download/resume identity unchanged. Supplemental metadata is display-only.
- Decode module-provided episode titles, thumbnails, summaries, duration and dates
  when the source supplies them. Do not interpret an arbitrary title as an ID.
- Find optional anime posters and landscape banners through AniList, with strict
  title/season matching, small bounded requests, and in-memory caching.
- Optionally enrich episode titles, stills, descriptions and air dates from TMDB
  only when the user configures their own read token in Settings > Episode Metadata.
- Reuse Kinetiq's existing artwork cache. A banner is shown edge to edge; a
  portrait-only cover appears in full against a blurred copy of itself.
- Show 16:9 episode images or a numbered placeholder; keep play, download,
  per-language watch history and actions intact.

## Data priority

1. Installed module: episode ID, number, link, Sub/Dub, supplied episode metadata.
2. AniList: unambiguous anime artwork and available streaming-episode previews.
3. Optional TMDB: unambiguous season-specific episode metadata.
4. Kinetiq: episode number and existing generic thumbnail if metadata is absent.

AniList does not promise complete episode-by-episode coverage. The TMDB integration
requires an API read token; it is disabled by default and stored only in the iOS
Keychain when provided. Neither metadata service supplies video URLs. Ambiguous
matches are rejected rather than attaching another season's information.

## Compatibility guardrails

- No changes to the existing player implementation, PiP integration, download
  engine, main-tab layout, module package management or stored collection format.
- Kinetiq still keeps Personal/Local Library media separate from streaming modules.
- Keep existing source branding and separate Sub/Dub history and resume positions.
- Artwork cards are rendered through the app theme's existing corner radius and
  accent color. Controls have 44-point touch areas.

## Verification

See `docs/TEST_06K11.md`. GitHub Actions/Xcode compilation and a real iPhone
test are required; a Linux static source inspection cannot validate iOS runtime.
