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

    private var enabledBinding: Binding<Bool> {
        Binding(get: { presence.enabled }, set: { presence.setEnabled($0) })
    }

    private var activityTypeBinding: Binding<KinetiqDiscordActivityType> {
        Binding(get: { presence.activityType }, set: { presence.setActivityType($0) })
    }

    private var nameStyleBinding: Binding<KinetiqDiscordNameStyle> {
        Binding(get: { presence.nameStyle }, set: { presence.setNameStyle($0) })
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
                    Label("Custom Status shows 🍿, the anime and episode. The standard poster and time bar are not part of this mode.",
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
                        Text("\(presence.activityType.title) \(style.rawValue)").tag(style)
                    }
                }
                .pickerStyle(.menu)
                LabeledContent("Requested heading", value:
                    presence.activityType == .custom
                        ? "Custom Status"
                        : "\(presence.activityType.title) \(presence.nameStyle.rawValue)")
                Text("Kinetiq stays in the heading; the anime title, episode name and language stay in the activity details. Discord may override the heading with its registered application name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("The elapsed/total progress is sent in milliseconds. The progress bar works best with Listening and Watching.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Anime artwork · experimental") {
                Text("Kinetiq now requests a Discord media-proxy identifier for each public anime poster, preferring AniList artwork where available. Unlike an ordinary image URL, Discord can recognize the resulting mp:external asset. This endpoint and personal Gateway method are unofficial, so visibility is not guaranteed.")
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
        }
        .onDisappear { credentialInput = "" }
    }
}
