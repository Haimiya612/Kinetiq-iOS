import SwiftUI

@main
struct KinetiqApp: App {
    @StateObject private var taglineStore: LaunchTaglineStore
    @AppStorage(AppStorageKey.appearance) private var appearanceRawValue = AppAppearance.system.rawValue

    init() {
        _taglineStore = StateObject(wrappedValue: LaunchTaglineStore())
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(tagline: taglineStore.tagline)
                .preferredColorScheme(AppAppearance(rawValue: appearanceRawValue)?.colorScheme)
        }
    }
}
