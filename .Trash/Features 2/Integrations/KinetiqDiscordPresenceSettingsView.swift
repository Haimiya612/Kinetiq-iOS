import SwiftUI
import UIKit

/// The feature has its own screen; it does not add controls to the player or
/// change the app's four-tab navigation.
@MainActor
struct KinetiqDiscordPresenceSettingsView: View {
    @ObservedObject private var presence = KinetiqDiscordPresenceManager.shared
    @State private var credentialInput = ""
    @State private var tokenSavedNotice = false
    @State private var streamingURLInput = ""
    @State private var streamingURLNotice = ""
    @State private var posterAssetInput = ""
    @State private var posterAssetNotice = ""
    @State private var customStatusDraft = ""
    @State private var customStatusSavedNotice = false

    private var enabledBinding: Binding<Bool> {
        Binding(get: { presence.enabled }, set: { presence.setEnabled($0) })
    }

    private var activityTypeBinding: Binding<KinetiqDiscordActivityType> {
        Binding(get: { presence.activityType }, set: { presence.setActivityType($0) })
    }

    private var nameStyleBinding: Binding<KinetiqDiscordNameStyle> {
        Binding(get: { presence.nameStyle }, set: { presence.setNameStyle($0) })
    }

    private var headingModeBinding: Binding<KinetiqDiscordHeadingMode> {
        Binding(get: { presence.headingMode }, set: { presence.setHeadingMode($0) })
    }

    private var rotationTargetBinding: Binding<KinetiqDiscordRotationTarget> {
        Binding(get: { presence.rotationTarget }, set: { presence.setRotationTarget($0) })
    }

    private var rotationIntervalBinding: Binding<Double> {
        Binding(get: { Double(presence.rotationIntervalSeconds) },
                set: { presence.setRotationInterval(Int($0.rounded())) })
    }

    private var artworkStyleBinding: Binding<KinetiqDiscordArtworkStyle> {
        Binding(get: { presence.artworkStyle }, set: { presence.setArtworkStyle($0) })
    }

    var body: some View {
        Form {
            Section {
                Label("Unofficial experiment", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("Automating a personal Discord account is unsupported and may lead to account restrictions. This feature is off by default. The Discord Social SDK is the supported alternative, but its iPhone integration is different.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Enable Presence Lab", isOn: enabledBinding)
            } header: {
                Text("Experimental Discord Presence")
            } footer: {
                Text("Only enable this if you understand the account risk. A successful Gateway connection does not prove Discord displays the activity.")
            }

            Section("Local credential") {
                SecureField("Paste a fresh Discord session token", text: $credentialInput)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityHint("Stored in this iPhone's Keychain, not the app settings")

                Button {
                    tokenSavedNotice = presence.saveCredential(credentialInput)
                    if tokenSavedNotice { credentialInput = "" }
                } label: {
                    Label("Save locally", systemImage: "key.horizontal.fill")
                }
                .disabled(credentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                LabeledContent("Credential", value: presence.hasCredential ? "Saved in Keychain" : "Not saved")

                if tokenSavedNotice {
                    Text("Saved. The field was cleared. Switch Presence Lab on to connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    presence.forgetCredential()
                    credentialInput = ""
                    tokenSavedNotice = false
                } label: {
                    Label("Forget token on this iPhone", systemImage: "trash")
                }
                .disabled(!presence.hasCredential)
            }

            Section("Connection") {
                LabeledContent("Status", value: presence.connection.rawValue)
                LabeledContent("Last stage", value: presence.connectionStage)
                LabeledContent("Playback sync", value: presence.playbackSyncStatus)
                Text(presence.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(presence.safeDiagnostics)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Safe connection diagnostics")

                Button {
                    UIPasteboard.general.string = presence.safeDiagnostics
                } label: {
                    Label("Copy safe diagnostics", systemImage: "doc.on.doc")
                }

                HStack {
                    Button("Reconnect", systemImage: "arrow.clockwise") {
                        presence.connect()
                    }
                    .disabled(!presence.enabled || !presence.hasCredential)

                    Spacer()

                    Button("Disconnect", systemImage: "stop.circle") {
                        presence.disconnect()
                    }
                    .disabled(presence.connection == .off ||
                              presence.connection == .disconnected)
                }

                Button("Send sample anime activity", systemImage: "play.rectangle.on.rectangle") {
                    presence.sendTestActivity()
                }
                .disabled(presence.connection != .connected)

                if let sentAt = presence.lastSentAt {
                    LabeledContent("Last submitted") {
                        Text(sentAt, style: .time)
                    }
                }
                Text("Rapid +10s taps and slider jumps are combined into one settled update. Presence refreshes obey a conservative rolling rate limit; the activity can briefly trail the player while a seek is in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current activity preview") {
                if let current = presence.lastPreview {
                    HStack(alignment: .top, spacing: 12) {
                        ModuleAnimeArtworkView(url: presence.publicPosterURL)
                            .frame(width: 68, height: 98)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Anime poster preview")

                        VStack(alignment: .leading, spacing: 7) {
                            Text(KinetiqDiscordActivity.description(for: current))
                                .font(.headline)
                            Text(KinetiqDiscordActivity.state(for: current))
                                .font(.subheadline)
                            Text("\(KinetiqDiscordActivity.clock(current.position)) / \(KinetiqDiscordActivity.clock(current.duration))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Label(current.isPictureInPicture ? "Picture in Picture" : "In Kinetiq",
                                  systemImage: current.isPictureInPicture ? "pip" : "play.rectangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if let assetKey = presence.posterAssetKey {
                        Label("Testing Developer Portal asset: \(assetKey)", systemImage: "photo")
                            .font(.caption)
                        Text("The uploaded asset key takes priority over automatic anime posters. Clear it below to test Discord media-proxy artwork.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if presence.publicPosterURL != nil {
                        Label("Public poster available; awaiting Discord media-proxy verification",
                              systemImage: "photo")
                            .font(.caption)
                    } else {
                        Label("Looking for a public anime poster, or no match found",
                              systemImage: "photo.badge.exclamationmark")
                            .font(.caption)
                    }
                } else {
                    Text("Play an anime episode to preview the activity. A sample activity can also be sent after connecting.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Discord activity", selection: activityTypeBinding) {
                    ForEach(KinetiqDiscordActivityType.allCases) { type in
                        Text("\(type.rawValue) · \(type.title)")
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)

                Text(presence.activityType.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent("Remembered activity", value: presence.activityType.title)
                Text("Your chosen activity type is saved on this iPhone and reused after restarting or reconnecting. Playback updates do not reset Listening or Competing to Watching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presence.activityType == .streaming {
                    TextField("https://twitch.tv/your-channel", text: $streamingURLInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("Twitch or YouTube streaming URL")

                    Button("Save streaming URL", systemImage: "link") {
                        let accepted = presence.saveStreamingURL(streamingURLInput)
                        streamingURLNotice = accepted
                            ? (presence.streamingURL == nil
                                ? "Stream URL removed. Watching will be used as a fallback."
                                : "Stream URL saved locally. Discord acceptance is not guaranteed.")
                            : "Enter a valid HTTPS Twitch or YouTube streaming URL."
                    }

                    if !streamingURLNotice.isEmpty {
                        Text(streamingURLNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if presence.streamingURL == nil {
                        Label("No valid stream URL: Kinetiq will publish Watching instead.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else if presence.activityType == .custom {
                    TextField("Custom text (e.g. Streaming)", text: $customStatusDraft, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityHint("Enter any text, without a stream URL. Anime, episode and language placeholders are available.")
                    Button("Save custom status", systemImage: "square.and.arrow.down") {
                        presence.setCustomStatusText(customStatusDraft)
                        customStatusSavedNotice = true
                    }
                    .disabled(customStatusDraft == presence.customStatusText)
                    Text("Streaming works here as ordinary Custom Status text; no Twitch or YouTube URL is needed. You can also use {anime}, {episode}, or {language}. Leave the field blank for the original automatic anime status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if customStatusSavedNotice {
                        Label("Custom status saved on this iPhone.", systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                    if let preview = presence.lastPreview {
                        LabeledContent("Status preview", value: KinetiqDiscordHeadingPolicy.customStatusWithHeading(
                            customStatusDraft, for: preview, mode: presence.headingMode,
                            style: presence.nameStyle,
                            alternateShowsAnime: presence.rotationShowsAnimeTitle,
                            rotationTarget: presence.rotationTarget))
                    }
                    Label("Discord Custom Status does not include the normal Rich Presence poster or progress bar.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Activity type · Codes 0–5")
            } footer: {
                Text("Changes are stored on this iPhone and sent with the next activity update. Discord determines which activity types and fields it displays.")
            }

            Section("Rich Presence appearance") {
                Picker("Activity heading", selection: nameStyleBinding) {
                    ForEach(KinetiqDiscordNameStyle.allCases) { style in
                        if style == .empty {
                            Text("Empty").tag(style)
                        } else {
                            Text("\(presence.activityType.title) \(style.rawValue)").tag(style)
                        }
                    }
                }
                .pickerStyle(.menu)
                Text(presence.activityType == .custom
                    ? "Custom Status adds the selected Kinetiq wording after your text. Choose Empty to display only your custom text."
                    : "Empty uses Kinetiq as a fallback, because Discord requires a Rich Presence activity name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Heading display", selection: headingModeBinding) {
                    ForEach(KinetiqDiscordHeadingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                if presence.headingMode == .animeAndKinetiq {
                    Text("Places the anime title before your selected Kinetiq wording—for example, Watching Blue Box with Kinetiq. Empty shows the anime title alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if presence.headingMode == .animePipeKinetiq {
                    Text("Separates the anime title and Kinetiq with a vertical bar—for example, Watching Blue Box | Kinetiq.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if presence.headingMode == .alternating {
                    Picker("Alternate with", selection: rotationTargetBinding) {
                        ForEach(KinetiqDiscordRotationTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rotation interval")
                            Spacer()
                            Text("\(presence.rotationIntervalSeconds) seconds")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: rotationIntervalBinding, in: 5...60, step: 5)
                            .accessibilityLabel("Discord heading rotation interval")
                            .accessibilityValue("\(presence.rotationIntervalSeconds) seconds")
                        HStack {
                            Text("5 seconds")
                            Spacer()
                            Text("60 seconds")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Text("Playback and seek updates take priority. Discord rate limits can delay a rotation beyond the selected interval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Requested heading", value: presence.requestedHeading)
                Text(presence.activityType == .custom
                    ? "The anime and Kinetiq heading formats also apply to Custom Status text. Custom Status has no Rich Presence poster or progress bar."
                    : "Anime + Kinetiq preserves your selected wording; Anime | Kinetiq uses the bar separator. Automatic rotation switches from the original Kinetiq heading to your chosen alternate. The anime poster, details and playback timestamps remain unchanged. Discord may override the heading with its registered application name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if presence.activityType != .custom {
                    Text("Elapsed and total playback time are sent in milliseconds. The progress bar works best with Listening and Watching.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Anime artwork · experimental") {
                Text("Kinetiq automatically selects high-resolution anime covers and registers them with Discord's media proxy. Choose how each cover fits Discord's square activity thumbnail. The personal Gateway method remains unofficial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Artwork quality", selection: artworkStyleBinding) {
                    ForEach(KinetiqDiscordArtworkStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Text(presence.artworkStyle.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let previewURL = presence.artworkPreviewURL {
                    HStack(alignment: .center, spacing: 14) {
                        ModuleAnimeArtworkView(url: previewURL)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("Selected square Discord artwork")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Discord artwork preview")
                                .font(.subheadline.weight(.semibold))
                            Text("Square presentation · 1024 × 1024 when enhanced")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Discord controls the thumbnail's displayed size.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Text("Smart Square and Full Poster use the public wsrv.nl image service for resizing. Only the public cover URL is shared; no video URL, account credential or playback data is sent to that service. Original HD does not use the image service. If processing fails, Kinetiq automatically returns to the original poster.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Artwork resolution")
                        .font(.subheadline.weight(.medium))
                    Text(presence.artworkResolutionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                TextField("Developer Portal asset key (optional)", text: $posterAssetInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Discord Rich Presence uploaded image asset key")

                Button("Apply image asset test", systemImage: "photo.on.rectangle") {
                    posterAssetNotice = presence.savePosterAssetKey(posterAssetInput)
                        ? (presence.posterAssetKey == nil
                            ? "Dynamic anime posters restored."
                            : "Uploaded asset selected. Verify it on another Discord account.")
                        : "Use only letters, digits, hyphens or underscores (1–64 characters)."
                }
                if let key = presence.posterAssetKey {
                    LabeledContent("Current asset", value: key)
                    Button("Use automatic anime posters") {
                        posterAssetInput = ""
                        _ = presence.savePosterAssetKey("")
                        posterAssetNotice = "Dynamic anime posters restored."
                    }
                }
                if !posterAssetNotice.isEmpty {
                    Text(posterAssetNotice).font(.caption).foregroundStyle(.secondary)
                }
                Text("For the asset test, first upload an image under your Discord application's Rich Presence assets and enter its asset name here. This is optional and does not upload artwork from Kinetiq.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("To test automatic artwork, clear any earlier test key (including alya_poster), start an episode, wait for 'Discord media proxy resolved', and check the result from a second account. A resolved identifier does not prove Discord rendered it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Text("1. Confirm activity and artwork on another Discord account.\n2. Seek and pause the video; check that elapsed/total time behaves correctly.\n3. Start PiP and leave Kinetiq; verify playback and presence independently.\n4. Return and check whether the app resynchronizes the activity.\n5. Never share session tokens or raw network captures.")
                    .font(.footnote)
            } header: {
                Text("What to test")
            } footer: {
                Text("iOS does not guarantee background WebSocket execution in PiP. There is no local server or desktop dependency. Never paste a session token in GitHub, a chat, or diagnostics.")
            }
        }
        .navigationTitle("Discord Presence Lab")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(KinetiqExperienceBackground())
        .onAppear {
            streamingURLInput = presence.streamingURL?.absoluteString ?? ""
            posterAssetInput = presence.posterAssetKey ?? ""
            customStatusDraft = presence.customStatusText
        }
        .onDisappear { credentialInput = "" }
    }
}
