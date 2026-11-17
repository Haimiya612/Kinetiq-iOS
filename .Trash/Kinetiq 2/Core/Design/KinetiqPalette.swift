import SwiftUI

// MARK: - Dynamic Application Palette
// Original legacy presets remain the default and original storage keys
// are never mutated by choosing a streaming-inspired experience.
enum KinetiqPalette {
    private static var selectedAccent: AppAccentColor {
        let raw = UserDefaults.standard.string(forKey: AppStorageKey.accentColor)
        return AppAccentColor(rawValue: raw ?? "") ?? .kinetiq
    }

    private static var visualTheme: KinetiqVisualTheme { KinetiqVisualTheme.chosen }

    static var accent: Color {
        if let custom = KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.accentKey) {
            return custom
        }
        return visualTheme == .signature ? selectedAccent.accent : visualTheme.accent
    }

    static var cyan: Color {
        if let custom = KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.accentKey) {
            return custom
        }
        return visualTheme == .signature ? selectedAccent.cyanTone : visualTheme.accent
    }

    static var blue: Color {
        visualTheme == .signature ? selectedAccent.blueTone : visualTheme.highlight
    }

    static var violet: Color {
        visualTheme == .signature ? selectedAccent.violetTone : visualTheme.highlight
    }

    static let mutedText = Color.secondary
}