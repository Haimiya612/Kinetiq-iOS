import SwiftUI

struct MainTabView: View {
    let tagline: String

    var body: some View {
        TabView {
            HomeView(tagline: tagline)
                .tabItem {
                    Label("Home", systemImage: "sparkles")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "rectangle.stack")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(KinetiqPalette.accent)
    }
}
