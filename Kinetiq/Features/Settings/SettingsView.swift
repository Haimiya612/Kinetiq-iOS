import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.appearance) private var appearanceRawValue = AppAppearance.system.rawValue

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("About Kinetiq") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Platform", value: "iOS")
                    LabeledContent("Distribution", value: "Sideload")
                }

                Section("The idea") {
                    Text("Your Streams, Your Modules, Your Rules.")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    Text("Kinetiq is being built as a fluid, modular media experience.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
