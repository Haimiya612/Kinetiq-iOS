
import SwiftUI

@main
struct KinetiqApp: App {
    @StateObject private var taglineStore: LaunchTaglineStore

    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue

    @AppStorage("kinetiq.lastSeenWhatsNewVersion")
    private var lastSeenWhatsNewVersion = ""

    @State private var showingWhatsNew = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    init() {
        _taglineStore = StateObject(wrappedValue: LaunchTaglineStore())
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(tagline: taglineStore.tagline)
                .preferredColorScheme(
                    AppAppearance(rawValue: appearanceRawValue)?.colorScheme
                )
                .task {
                    guard lastSeenWhatsNewVersion != currentVersion else {
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(450))

                    guard !Task.isCancelled else { return }
                    showingWhatsNew = true
                }
                .sheet(
                    isPresented: $showingWhatsNew,
                    onDismiss: {
                        lastSeenWhatsNewVersion = currentVersion
                    }
                ) {
                    WhatsNewView()
                }
        }
    }
}