import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your library is empty",
                systemImage: "rectangle.stack",
                description: Text("Local media playback is part of the next development milestone.")
            )
            .navigationTitle("Library")
        }
    }
}
