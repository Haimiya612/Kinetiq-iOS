
import SwiftUI

// MARK: - Dynamic Application Palette

enum KinetiqPalette {

    private static var selectedTheme: AppAccentColor {
        let storedValue = UserDefaults.standard.string(
            forKey: AppStorageKey.accentColor
        )

        return AppAccentColor(rawValue: storedValue ?? "") ?? .kinetiq
    }

    static var accent: Color {
        selectedTheme.accent
    }

    static var cyan: Color {
        selectedTheme.cyanTone
    }

    static var blue: Color {
        selectedTheme.blueTone
    }

    static var violet: Color {
        selectedTheme.violetTone
    }

    static let mutedText = Color.secondary
}