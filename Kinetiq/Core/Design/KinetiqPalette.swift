import SwiftUI

// MARK: - Dynamic Application Palette
// The original accent palette remains the default. Custom experience themes
// supply coordinated colors without destroying the user's saved accent.
enum KinetiqPalette {
    private static var selectedAccent: AppAccentColor {
        let raw = UserDefaults.standard.string(forKey: AppStorageKey.accentColor)
        return AppAccentColor(rawValue: raw ?? "") ?? .kinetiq
    }

    private static var visualTheme: KinetiqVisualTheme { KinetiqVisualTheme.chosen }

    static var accent: Color {
        visualTheme == .signature ? selectedAccent.accent : visualTheme.accent
    }

    static var cyan: Color {
        visualTheme == .signature ? selectedAccent.cyanTone : visualTheme.accent
    }

    static var blue: Color {
        visualTheme == .signature ? selectedAccent.blueTone : visualTheme.highlight
    }

    static var violet: Color {
        visualTheme == .signature ? selectedAccent.violetTone : visualTheme.highlight
    }

    static let mutedText = Color.secondary
}