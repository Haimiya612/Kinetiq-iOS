import Combine
import Foundation

@MainActor
final class LaunchTaglineStore: ObservableObject {
    @Published private(set) var tagline: String

    init(defaults: UserDefaults = .standard) {
        let key = AppStorageKey.lastLaunchTagline
        let previous = defaults.string(forKey: key)
        let selected = TaglineSelector.next(previous: previous)
        tagline = selected
        defaults.set(selected, forKey: key)
    }
}
