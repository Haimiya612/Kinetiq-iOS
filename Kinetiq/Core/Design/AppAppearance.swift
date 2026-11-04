
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Accent Themes

enum AppAccentColor: String, CaseIterable, Identifiable, Equatable {
    case kinetiq
    case ocean
    case violet
    case rose
    case emerald
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kinetiq: "Kinetiq Cyan"
        case .ocean: "Ocean Blue"
        case .violet: "Violet"
        case .rose: "Rose"
        case .emerald: "Emerald"
        case .amber: "Amber"
        }
    }

    // Main interactive colour.
    var accent: Color {
        switch self {
        case .kinetiq:
            Color(red: 0.25, green: 0.76, blue: 0.91)
        case .ocean:
            Color(red: 0.23, green: 0.51, blue: 0.92)
        case .violet:
            Color(red: 0.56, green: 0.38, blue: 0.89)
        case .rose:
            Color(red: 0.88, green: 0.32, blue: 0.52)
        case .emerald:
            Color(red: 0.15, green: 0.63, blue: 0.46)
        case .amber:
            Color(red: 0.86, green: 0.51, blue: 0.19)
        }
    }

    // Lighter palette colour.
    var cyanTone: Color {
        switch self {
        case .kinetiq:
            Color(red: 0.22, green: 0.82, blue: 0.91)
        case .ocean:
            Color(red: 0.32, green: 0.70, blue: 0.98)
        case .violet:
            Color(red: 0.72, green: 0.58, blue: 0.97)
        case .rose:
            Color(red: 0.96, green: 0.52, blue: 0.66)
        case .emerald:
            Color(red: 0.29, green: 0.79, blue: 0.62)
        case .amber:
            Color(red: 0.98, green: 0.72, blue: 0.31)
        }
    }

    // Deeper palette colour.
    var blueTone: Color {
        switch self {
        case .kinetiq:
            Color(red: 0.31, green: 0.53, blue: 0.96)
        case .ocean:
            Color(red: 0.21, green: 0.42, blue: 0.83)
        case .violet:
            Color(red: 0.42, green: 0.43, blue: 0.88)
        case .rose:
            Color(red: 0.80, green: 0.33, blue: 0.63)
        case .emerald:
            Color(red: 0.16, green: 0.54, blue: 0.66)
        case .amber:
            Color(red: 0.76, green: 0.47, blue: 0.22)
        }
    }

    // Complementary palette colour.
    var violetTone: Color {
        switch self {
        case .kinetiq:
            Color(red: 0.55, green: 0.39, blue: 0.91)
        case .ocean:
            Color(red: 0.41, green: 0.38, blue: 0.82)
        case .violet:
            Color(red: 0.53, green: 0.30, blue: 0.81)
        case .rose:
            Color(red: 0.70, green: 0.29, blue: 0.69)
        case .emerald:
            Color(red: 0.29, green: 0.46, blue: 0.63)
        case .amber:
            Color(red: 0.68, green: 0.36, blue: 0.40)
        }
    }
}