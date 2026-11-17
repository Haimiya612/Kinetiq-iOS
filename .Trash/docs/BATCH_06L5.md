# Batch 06L5 — Rich Presence presentation and offline download checkpoint

This checkpoint incorporates all source files from the original 06L package,
the later 06L4 Presence changes, and the previously staged offline-download
work. It is a full-file replacement ZIP for Working Copy, not a patch script.

## Activity heading

- The Rich Presence activity `name` requests **Kinetiq**, not the anime name.
- Settings → Discord Presence Lab → Rich Presence appearance allows these
  name suffixes: `Kinetiq`, `on Kinetiq`, `via Kinetiq`, `with Kinetiq`,
  `in Kinetiq`, `from Kinetiq`.
- The activity type (codes 0–5) supplies the verb, e.g. Watching or Listening.
  Streaming without a real supported streaming URL still falls back to Watching.
- The anime name remains under activity details; the real episode title, if
  the source provides one, appears after the episode number in the state.

## Seeking and playback state

- A +10s / −10s seek can make AVPlayer briefly report not-playing while
  buffering. Presence now uses the user's explicit playback intent after an
  episode first starts; seek buffering will not be reported as a pause.
- Explicit Pause and the sleep timer still report paused.
- The ordinary player UI continues using AVPlayer's actual status.

## Cover image

- The public anime poster URL (or AniList metadata cover when available) is
  still requested with the activity.
- To diagnose why a poster does not appear, Settings offers an **optional**
  uploaded Discord Rich Presence asset key. Upload an image in the Developer
  Portal first, then type that asset name for a separate image-rendering test.
- Discord's official Social SDK supports external image URLs, but the
  experimental personal Gateway protocol may not display them. There is no
  guarantee that dynamic anime artwork can appear with this connection mode.

## Downloads

- Includes the offline episode-download coordinator and UI with concrete
  retained background HLS sessions, direct-download sessions, source retry,
  quality and subtitle checks, and clearer errors.
- Real download success **must be tested on an iPhone**. The earlier screenshot
  saying the background download service was unavailable was from an older
  build; the session retention fix has not yet been confirmed on-device.

## Compatibility

- Keep the four tabs: Home, Favorites, Downloads, Settings.
- Preserve all source names, local playback, subtitle configuration, PiP and
  player appearance.
- The ZIP contains no Discord account token, browser cookies, video media or
  private server payloads. The personal Gateway experiment remains unsupported
  by Discord and can pose account risk; it is disabled by default.
