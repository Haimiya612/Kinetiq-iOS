# Batch 06L — Discord Presence Lab (experimental)

## Scope

This is an **opt-in prototype**, not an official Discord integration and not a
confirmed working Discord Rich Presence implementation. Discord prohibits
automating normal user accounts. Discord may reject its Gateway payloads,
restrict the account, or change the protocol without notice.

The native Swift implementation does not need Discord.app, a desktop, an
external web service, Node.js, or a localhost HTTP server. It uses a local
`URLSessionWebSocketTask` connected to Discord's Gateway when the user
explicitly enables the experiment.

### In Settings → Integrations → Discord Presence Lab

- Disabled by default and entirely optional.
- `SecureField` to enter a new personal session credential on the iPhone.
- Keychain device-only storage; never save the credential to UserDefaults,
  Git, telemetry, diagnostics, or console output.
- Connect/reconnect, disconnect, forget token, connection status, and send a
  sample activity to isolate Gateway behavior from player behavior.
- Preview the intended anime details without exposing the credential.

### Module playback → Presence

- Anime title and episode number are read from the existing playback session.
- Sub/Dub, pause/resume, elapsed time, duration and PiP state update the
  activity preview.
- The anime's main poster is preferred. Only unsigned, public-looking HTTPS
  image URLs are eligible; if none is safe, no picture is sent.
- Activity type `3` (`Watching`) and the configured public Discord application
  ID are included in the experimental Gateway presence payload.
- At most one playback update is attempted per ~30 seconds for an unchanged
  episode and state. Changes to episode or play/pause bypass that delay.
- Ending module playback clears the activity for an active Gateway session.

### Known limits

1. Discord's **documented** Gateway Update Presence command is for bot/app
   sessions. Using it with a personal user token is unsupported. `READY` means
   the session connected; it does **not** prove activity visibility to friends.
2. Rich Presence artwork is a separate concern: even if presence text appears,
   Discord may reject external poster URLs for this unsupported transport.
3. The operating system may suspend a WebSocket when Kinetiq is in background,
   including while the video continues in Picture in Picture. Native PiP
   playback does **not** grant unlimited background networking.
4. This build instruments **module-backed** AVPlayer playback. Local Library
   items and web-fallback embeds are intentionally not advertised yet.
5. No automatic retry loop is used for authentication errors. Reconnect is
   manual; a transient interruption can attempt reconnect on the next app
   foreground activation.
6. Credential validity is not guaranteed indefinitely. Replace an expired
   token in Settings; the app never attempts to scrape a login form.

## Privacy and account recovery

Never paste a real session token into a chat, repo, issue, or build log. If it
has been exposed, change the Discord account password to invalidate existing
sessions, then remove the exposed token from Kinetiq. Use a fresh credential
only inside the on-device SecureField if you still decide to test.

## Rollout / acceptance criteria

Use `docs/TEST_06L.md` for iPhone tests. Keep the feature disabled by default
unless external visibility, artwork, PiP and disconnection are independently
verified. No SDK token, OAuth secret, or personal session token is bundled.

This batch does not alter the four main tabs, source identities, server
selection, media resolution, AirPlay, PiP configuration, player appearance,
module repository handling, or prior history and downloads.
