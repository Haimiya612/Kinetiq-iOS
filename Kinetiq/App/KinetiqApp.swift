import SwiftUI

@main
struct KinetiqApp: App {
    @StateObject private var taglineStore: LaunchTaglineStore
    @StateObject private var whatsNewStore = WhatsNewStore()

    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue

    @State private var showingWhatsNew = false
    @State private var checkedForUpdates = false

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
                    guard !checkedForUpdates else { return }
                    checkedForUpdates = true

                    await whatsNewStore.load()

                    guard
                        !Task.isCancelled,
                        whatsNewStore.hasUnseenReleases
                    else {
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(450))

                    guard !Task.isCancelled else { return }
                    showingWhatsNew = true
                }
                .sheet(
                    isPresented: $showingWhatsNew,
                    onDismiss: {
                        whatsNewStore.markLatestAsSeen()
                    }
                ) {
                    WhatsNewView(
                        releases: whatsNewStore.unseenReleases
                    )
                }
        }
    }
}