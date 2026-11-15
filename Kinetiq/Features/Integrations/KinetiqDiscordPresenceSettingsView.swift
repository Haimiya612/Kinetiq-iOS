import SwiftUI

/// The feature has its own screen; it does not add controls to the player or
/// change the app's four-tab navigation.
@MainActor
struct KinetiqDiscordPresenceSettingsView: View {
    @ObservedObject private var presence = KinetiqDiscordPresenceManager.shared
    @State private var credentialInput = ""
    @State private var tokenSavedNotice = false

    private var enabledBinding: Binding<Bool> {
        Binding(get: { presence.enabled }, set: { presence.setEnabled($0) })
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
                Text(presence.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Watching \(KinetiqDiscordActivity.description(for: current))")
                            .font(.headline)
                        Text(KinetiqDiscordActivity.state(for: current))
                            .font(.subheadline)
                        Text(current.isPictureInPicture ? "Picture in Picture" : "In Kinetiq")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if KinetiqDiscordActivity.publicArtwork(for: current) != nil {
                            Label("Public HTTPS poster eligible", systemImage: "photo")
                                .font(.caption)
                        } else {
                            Label("No public poster available", systemImage: "photo.badge.exclamationmark")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Play an anime episode to preview the activity. A sample activity can also be sent after connecting.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("1. Connect and wait for Gateway READY.\n2. Play an anime and check the Rich Presence from another Discord account.\n3. Check episode changes, Sub/Dub, pause/resume, and the anime poster.\n4. Enable PiP, leave Kinetiq, and check whether the activity survives app suspension.\n5. Disconnect and confirm the activity disappears.")
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
        .onDisappear { credentialInput = "" }
    }
}