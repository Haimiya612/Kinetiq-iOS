import SwiftUI

// MARK: - System appearance (existing storage contract retained)
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
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

// MARK: - Existing user accent preferences (never change persisted raw values)
enum AppAccentColor: String, CaseIterable, Identifiable, Equatable {
    case kinetiq, ocean, violet, rose, emerald, amber
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
    var accent: Color {
        switch self {
        case .kinetiq: Color(red: 0.25, green: 0.76, blue: 0.91)
        case .ocean: Color(red: 0.23, green: 0.51, blue: 0.92)
        case .violet: Color(red: 0.56, green: 0.38, blue: 0.89)
        case .rose: Color(red: 0.88, green: 0.32, blue: 0.52)
        case .emerald: Color(red: 0.15, green: 0.63, blue: 0.46)
        case .amber: Color(red: 0.86, green: 0.51, blue: 0.19)
        }
    }
    var cyanTone: Color {
        switch self {
        case .kinetiq: Color(red: 0.22, green: 0.82, blue: 0.91)
        case .ocean: Color(red: 0.32, green: 0.70, blue: 0.98)
        case .violet: Color(red: 0.72, green: 0.58, blue: 0.97)
        case .rose: Color(red: 0.96, green: 0.52, blue: 0.66)
        case .emerald: Color(red: 0.29, green: 0.79, blue: 0.62)
        case .amber: Color(red: 0.98, green: 0.72, blue: 0.31)
        }
    }
    var blueTone: Color {
        switch self {
        case .kinetiq: Color(red: 0.31, green: 0.53, blue: 0.96)
        case .ocean: Color(red: 0.21, green: 0.42, blue: 0.83)
        case .violet: Color(red: 0.42, green: 0.43, blue: 0.88)
        case .rose: Color(red: 0.80, green: 0.33, blue: 0.63)
        case .emerald: Color(red: 0.16, green: 0.54, blue: 0.66)
        case .amber: Color(red: 0.76, green: 0.47, blue: 0.22)
        }
    }
    var violetTone: Color {
        switch self {
        case .kinetiq: Color(red: 0.55, green: 0.39, blue: 0.91)
        case .ocean: Color(red: 0.41, green: 0.38, blue: 0.82)
        case .violet: Color(red: 0.53, green: 0.30, blue: 0.81)
        case .rose: Color(red: 0.70, green: 0.29, blue: 0.69)
        case .emerald: Color(red: 0.29, green: 0.46, blue: 0.63)
        case .amber: Color(red: 0.68, green: 0.36, blue: 0.40)
        }
    }
}

// MARK: - Batch 06C: Distinct original Kinetiq experience presets
// These are app-local appearance choices, not clones of third-party brands.
// New storage key does not alter legacy accent, light/dark or subtitle settings.
enum KinetiqVisualTheme: String, CaseIterable, Identifiable {
    static let storageKey = "kinetiq.visualTheme.v1"
    case signature, cinema, anime, aurora, nocturne
    var id: String { rawValue }
    var name: String {
        switch self {
        case .signature: "Signature"
        case .cinema: "Cinema"
        case .anime: "Anime Pulse"
        case .aurora: "Aurora"
        case .nocturne: "Nocturne"
        }
    }
    var subtitle: String {
        switch self {
        case .signature: "The original Kinetiq cyan"
        case .cinema: "Dramatic, editorial and focused"
        case .anime: "Electric color and expressive energy"
        case .aurora: "Fresh gradients and soft contrast"
        case .nocturne: "Quiet, immersive, nearly black"
        }
    }
    var symbol: String {
        switch self {
        case .signature: "waveform.path"
        case .cinema: "film.stack"
        case .anime: "sparkles.tv"
        case .aurora: "sparkles"
        case .nocturne: "moon.stars.fill"
        }
    }
    var accent: Color {
        switch self {
        case .signature: Color(red: 0.25, green: 0.76, blue: 0.91)
        case .cinema: Color(red: 0.98, green: 0.30, blue: 0.34)
        case .anime: Color(red: 1.00, green: 0.55, blue: 0.22)
        case .aurora: Color(red: 0.27, green: 0.89, blue: 0.79)
        case .nocturne: Color(red: 0.63, green: 0.58, blue: 1.00)
        }
    }
    var highlight: Color {
        switch self {
        case .signature: Color(red: 0.30, green: 0.57, blue: 0.99)
        case .cinema: Color(red: 1.00, green: 0.63, blue: 0.36)
        case .anime: Color(red: 0.76, green: 0.34, blue: 0.98)
        case .aurora: Color(red: 0.20, green: 0.61, blue: 1.00)
        case .nocturne: Color(red: 0.33, green: 0.38, blue: 0.86)
        }
    }
    var backdrop: Color {
        switch self {
        case .signature: Color(red: 0.035, green: 0.053, blue: 0.083)
        case .cinema: Color(red: 0.065, green: 0.030, blue: 0.046)
        case .anime: Color(red: 0.078, green: 0.038, blue: 0.088)
        case .aurora: Color(red: 0.020, green: 0.069, blue: 0.083)
        case .nocturne: Color(red: 0.021, green: 0.024, blue: 0.052)
        }
    }
    var cardSurface: Color { Color.white.opacity(self == .nocturne ? 0.045 : 0.078) }
    static var chosen: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .signature
    }
}

enum KinetiqMotionMode: String, CaseIterable, Identifiable {
    static let storageKey = "kinetiq.motionMode.v1"
    case expressive, balanced, quiet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expressive: "Expressive"
        case .balanced: "Balanced"
        case .quiet: "Quiet"
        }
    }
    var animation: Animation {
        switch self {
        case .expressive: .spring(response: 0.48, dampingFraction: 0.79)
        case .balanced: .spring(response: 0.35, dampingFraction: 0.88)
        case .quiet: .easeOut(duration: 0.14)
        }
    }
    static var chosen: KinetiqMotionMode {
        KinetiqMotionMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .balanced
    }
}