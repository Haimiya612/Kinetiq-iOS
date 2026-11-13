import SwiftUI
import UIKit

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
    case signature, cinema, anime, aurora, nocturne, studio, prism, atelier, signal, ember, vault, zen, nebula
    var id: String { rawValue }
    var name: String {
        switch self {
        case .signature: "Kinetiq Original"
        case .cinema: "Netflix-inspired"
        case .anime: "Crunchyroll-inspired"
        case .aurora: "Hulu-inspired"
        case .nocturne: "Apple TV-inspired"
        case .studio: "Prime Video-inspired"
        case .prism: "HBO Max-inspired"
        case .atelier: "MUBI-inspired"
        case .signal: "YouTube-inspired"
        case .ember: "HIDIVE-inspired"
        case .vault: "Plex-inspired"
        case .zen: "Criterion Channel-inspired"
        case .nebula: "Disney+-inspired"
        }
    }
    var subtitle: String {
        switch self {
        case .signature: "Original Kinetiq · luminous cyan shelves"
        case .cinema: "Theater-style artwork · editorial headings"
        case .anime: "Anime-first posters · expressive color"
        case .aurora: "Soft glass · luminous gradients"
        case .nocturne: "Nearly-black canvas · minimal distractions"
        case .studio: "Clean cobalt shelves and discovery"
        case .prism: "Luminous cinematic spectacle"
        case .atelier: "Art-house editorial warmth"
        case .signal: "Bold, fast-moving media discovery"
        case .ember: "Warm anime-first chapter energy"
        case .vault: "Personal-library warmth and precision"
        case .zen: "Quiet monochrome and mindful media"
        case .nebula: "Cosmic violet atmosphere"
        }
    }
    var symbol: String {
        switch self {
        case .signature: "waveform.path"
        case .cinema: "film.stack"
        case .anime: "sparkles.tv"
        case .aurora: "sparkles"
        case .nocturne: "moon.stars.fill"
        case .studio: "rectangle.stack.fill"
        case .prism: "diamond.inset.filled"
        case .atelier: "rectangle.portrait.on.rectangle.portrait"
        case .signal: "bolt.circle.fill"
        case .ember: "flame.fill"
        case .vault: "square.stack.3d.up.fill"
        case .zen: "circle.dotted.circle.fill"
        case .nebula: "moon.stars"
        }
    }
    var accent: Color {
        KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.accentKey) ?? defaultAccent
    }
    var defaultAccent: Color {
        switch self {
        case .signature: Color(red: 0.25, green: 0.76, blue: 0.91)
        case .cinema: Color(red: 0.98, green: 0.30, blue: 0.34)
        case .anime: Color(red: 1.00, green: 0.55, blue: 0.22)
        case .aurora: Color(red: 0.27, green: 0.89, blue: 0.79)
        case .nocturne: Color(red: 0.63, green: 0.58, blue: 1.00)
        case .studio: Color(red: 0.4039, green: 0.7373, blue: 1.0000)
        case .prism: Color(red: 0.4745, green: 0.6392, blue: 1.0000)
        case .atelier: Color(red: 0.9216, green: 0.7333, blue: 0.5176)
        case .signal: Color(red: 1.0000, green: 0.3686, blue: 0.4078)
        case .ember: Color(red: 1.0000, green: 0.6314, blue: 0.2941)
        case .vault: Color(red: 0.9059, green: 0.7294, blue: 0.3882)
        case .zen: Color(red: 0.8941, green: 0.8902, blue: 0.8627)
        case .nebula: Color(red: 0.8196, green: 0.6039, blue: 1.0000)
        }
    }
    var highlight: Color {
        switch self {
        case .signature: Color(red: 0.30, green: 0.57, blue: 0.99)
        case .cinema: Color(red: 1.00, green: 0.63, blue: 0.36)
        case .anime: Color(red: 0.76, green: 0.34, blue: 0.98)
        case .aurora: Color(red: 0.20, green: 0.61, blue: 1.00)
        case .nocturne: Color(red: 0.33, green: 0.38, blue: 0.86)
        case .studio: Color(red: 0.1176, green: 0.4000, blue: 0.8627)
        case .prism: Color(red: 0.8471, green: 0.6314, blue: 1.0000)
        case .atelier: Color(red: 0.8275, green: 0.5098, blue: 0.4510)
        case .signal: Color(red: 1.0000, green: 0.6863, blue: 0.3961)
        case .ember: Color(red: 1.0000, green: 0.3569, blue: 0.5098)
        case .vault: Color(red: 0.6431, green: 0.5333, blue: 0.3569)
        case .zen: Color(red: 0.6078, green: 0.6471, blue: 0.6667)
        case .nebula: Color(red: 0.4275, green: 0.5451, blue: 1.0000)
        }
    }
    var backdrop: Color {
        KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.backgroundKey) ?? defaultBackdrop
    }
    var defaultBackdrop: Color {
        switch self {
        case .signature: Color(red: 0.035, green: 0.053, blue: 0.083)
        case .cinema: Color(red: 0.065, green: 0.030, blue: 0.046)
        case .anime: Color(red: 0.078, green: 0.038, blue: 0.088)
        case .aurora: Color(red: 0.020, green: 0.069, blue: 0.083)
        case .nocturne: Color(red: 0.021, green: 0.024, blue: 0.052)
        case .studio: Color(red: 0.0275, green: 0.0627, blue: 0.1176)
        case .prism: Color(red: 0.0431, green: 0.0627, blue: 0.1686)
        case .atelier: Color(red: 0.1098, green: 0.0824, blue: 0.0784)
        case .signal: Color(red: 0.0863, green: 0.0392, blue: 0.0824)
        case .ember: Color(red: 0.1216, green: 0.0627, blue: 0.0784)
        case .vault: Color(red: 0.0667, green: 0.0667, blue: 0.0627)
        case .zen: Color(red: 0.0863, green: 0.1020, blue: 0.1137)
        case .nebula: Color(red: 0.0667, green: 0.0431, blue: 0.1412)
        }
    }
    var cardSurface: Color {
        KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.surfaceKey)?.opacity(0.30)
            ?? Color.white.opacity(self == .nocturne ? 0.045 : 0.078)
    }
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

// MARK: - Batch 06D: distinct app-wide experience design tokens
extension KinetiqVisualTheme {
    var stageColors: [Color] {
        switch self {
        case .signature:
            return [Color(red: 0.08, green: 0.20, blue: 0.38),
                    Color(red: 0.13, green: 0.34, blue: 0.57),
                    Color(red: 0.34, green: 0.22, blue: 0.58)]
        case .cinema:
            return [Color(red: 0.11, green: 0.025, blue: 0.04),
                    Color(red: 0.32, green: 0.06, blue: 0.10),
                    Color(red: 0.07, green: 0.035, blue: 0.07)]
        case .anime:
            return [Color(red: 0.34, green: 0.09, blue: 0.48),
                    Color(red: 0.90, green: 0.22, blue: 0.40),
                    Color(red: 1.00, green: 0.48, blue: 0.18)]
        case .aurora:
            return [Color(red: 0.02, green: 0.25, blue: 0.39),
                    Color(red: 0.04, green: 0.45, blue: 0.38),
                    Color(red: 0.13, green: 0.23, blue: 0.53)]
        case .nocturne:
            return [Color(red: 0.045, green: 0.045, blue: 0.09),
                    Color(red: 0.09, green: 0.08, blue: 0.19),
                    Color(red: 0.02, green: 0.025, blue: 0.052)]
        case .studio: return [Color(red: 0.0510, green: 0.1922, blue: 0.3451), Color(red: 0.0706, green: 0.3647, blue: 0.6275), Color(red: 0.0392, green: 0.0745, blue: 0.1529)]
        case .prism: return [Color(red: 0.0588, green: 0.1333, blue: 0.4157), Color(red: 0.3137, green: 0.2196, blue: 0.7059), Color(red: 0.0627, green: 0.1765, blue: 0.3647)]
        case .atelier: return [Color(red: 0.3176, green: 0.2039, blue: 0.1725), Color(red: 0.1647, green: 0.1137, blue: 0.1216), Color(red: 0.0824, green: 0.0627, blue: 0.0784)]
        case .signal: return [Color(red: 0.2627, green: 0.0706, blue: 0.1569), Color(red: 0.5020, green: 0.1098, blue: 0.2118), Color(red: 0.1333, green: 0.0824, blue: 0.1569)]
        case .ember: return [Color(red: 0.4588, green: 0.1922, blue: 0.1490), Color(red: 0.7216, green: 0.2941, blue: 0.1804), Color(red: 0.2549, green: 0.0745, blue: 0.1569)]
        case .vault: return [Color(red: 0.2039, green: 0.1608, blue: 0.0980), Color(red: 0.1294, green: 0.1137, blue: 0.0863), Color(red: 0.0667, green: 0.0667, blue: 0.0627)]
        case .zen: return [Color(red: 0.1882, green: 0.2039, blue: 0.2196), Color(red: 0.1255, green: 0.1451, blue: 0.1608), Color(red: 0.0627, green: 0.0784, blue: 0.0902)]
        case .nebula: return [Color(red: 0.2078, green: 0.0902, blue: 0.3647), Color(red: 0.2510, green: 0.1765, blue: 0.6510), Color(red: 0.0745, green: 0.1176, blue: 0.2941)]
        }
    }

    var cardBackground: Color {
        if let custom = KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.surfaceKey) {
            return custom.opacity(0.30)
        }
        return self == .signature
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color.white.opacity(self == .nocturne ? 0.042 : 0.09)
    }

    var cardCornerRadius: CGFloat {
        switch self {
        case .signature: 19
        case .cinema: 9
        case .anime: 24
        case .aurora: 27
        case .nocturne: 12
        case .studio: 14
        case .prism: 29
        case .atelier: 4
        case .signal: 18
        case .ember: 22
        case .vault: 6
        case .zen: 7
        case .nebula: 30
        }
    }
    var dockCornerRadius: CGFloat {
        switch self {
        case .signature: 34
        case .cinema: 12
        case .anime: 25
        case .aurora: 34
        case .nocturne: 15
        case .studio: 17
        case .prism: 30
        case .atelier: 6
        case .signal: 20
        case .ember: 26
        case .vault: 9
        case .zen: 10
        case .nebula: 34
        }
    }
    var heroHeight: CGFloat {
        switch self {
        case .signature: 258
        case .cinema: 330
        case .anime: 270
        case .aurora: 290
        case .nocturne: 215
        case .studio: 284
        case .prism: 338
        case .atelier: 344
        case .signal: 241
        case .ember: 285
        case .vault: 265
        case .zen: 250
        case .nebula: 315
        }
    }
    var eyebrow: String {
        switch self {
        case .signature: "ONE HOME. EVERY STORY."
        case .cinema: "NOW SHOWING · KINETIQ"
        case .anime: "YOUR NEXT OBSESSION"
        case .aurora: "DISCOVER WITHOUT LIMITS"
        case .nocturne: "JUST YOU AND THE STORY"
        case .studio: "YOUR PERSONAL PREMIERE"
        case .prism: "BEYOND THE FRAME"
        case .atelier: "A COLLECTION, CURATED"
        case .signal: "TUNED TO YOU"
        case .ember: "ON TO THE NEXT ARC"
        case .vault: "YOUR COLLECTION. YOUR RULES."
        case .zen: "A LITTLE LESS NOISE"
        case .nebula: "DISCOVER NEW WORLDS"
        }
    }
    var homeHeadline: String {
        switch self {
        case .signature: "Your world of media."
        case .cinema: "The screen is yours."
        case .anime: "Find your next favorite."
        case .aurora: "Follow your curiosity."
        case .nocturne: "Less noise. More story."
        case .studio: "Everything, in view."
        case .prism: "Stories in every shade."
        case .atelier: "Discover with intention."
        case .signal: "Find it. Play it."
        case .ember: "Your story starts here."
        case .vault: "Made for your collection."
        case .zen: "A quieter way to watch."
        case .nebula: "Follow the unknown."
        }
    }
    var heroHeadline: String {
        switch self {
        case .signature: "Every kind of story.\nOne place to find it."
        case .cinema: "Your private\nscreening room."
        case .anime: "Your next\nbig adventure."
        case .aurora: "A whole universe\nof discoveries."
        case .nocturne: "Press play.\nDisappear awhile."
        case .studio: "A home for\nevery screen."
        case .prism: "One universe.\nInfinite stories."
        case .atelier: "Stories worth\nstaying for."
        case .signal: "What are you\nwatching next?"
        case .ember: "Every episode.\nEvery emotion."
        case .vault: "Everything yours.\nAll in one place."
        case .zen: "Stay with\nthe story."
        case .nebula: "A universe of\nnew favorites."
        }
    }
    var heroDescription: String {
        switch self {
        case .signature: "A universe built around what you love."
        case .cinema: "A cinematic home for the stories that stay with you."
        case .anime: "New worlds and familiar favorites await."
        case .aurora: "Explore the unexpected, your way."
        case .nocturne: "Your media, without distractions."
        case .studio: "Your personal media, organized beautifully."
        case .prism: "Find your next great watch, with color and clarity."
        case .atelier: "An editorial home for unforgettable cinema."
        case .signal: "A faster path to the media that matters."
        case .ember: "Dive into a story, a world, a new favorite."
        case .vault: "Your personal media, front and center."
        case .zen: "A considered experience for every moment."
        case .nebula: "Bring your favorite stories into orbit."
        }
    }
    var heroSymbol: String {
        switch self {
        case .signature: "play.rectangle.on.rectangle.fill"
        case .cinema: "film.stack.fill"
        case .anime: "sparkles.tv.fill"
        case .aurora: "sparkles.rectangle.stack.fill"
        case .nocturne: "play.square.stack.fill"
        case .studio: "play.rectangle.fill"
        case .prism: "sparkles.tv.fill"
        case .atelier: "theatermasks.fill"
        case .signal: "bolt.fill"
        case .ember: "flame.fill"
        case .vault: "externaldrive.fill"
        case .zen: "circle.grid.2x2"
        case .nebula: "moon.stars.fill"
        }
    }
    var usesPosterGrid: Bool { [.cinema, .anime, .studio, .prism, .ember, .signal].contains(self) }
}

extension KinetiqVisualTheme {
    var isEditorial: Bool { [.cinema, .atelier, .vault].contains(self) }
    var isQuiet: Bool { [.nocturne, .zen, .atelier].contains(self) }
    var isAtmospheric: Bool { [.aurora, .prism, .nebula].contains(self) }
    var isEnergetic: Bool { [.anime, .ember, .signal].contains(self) }
    var preferredFontDesign: Font.Design { isEditorial ? .serif : (isEnergetic ? .rounded : .default) }
}

// Background is behind the main app only, never over an AVPlayer surface.
struct KinetiqExperienceBackground: View {
    @AppStorage(KinetiqRGBPalette.enabledKey) private var rgbEnabled = false
    @AppStorage(KinetiqRGBPalette.accentKey) private var rgbAccent = ""
    @AppStorage(KinetiqRGBPalette.backgroundKey) private var rgbBackground = ""
    @AppStorage(KinetiqRGBPalette.surfaceKey) private var rgbSurface = ""
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRawValue = KinetiqVisualTheme.signature.rawValue

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRawValue) ?? .signature
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if theme == .signature && KinetiqRGBPalette.customColor(for: KinetiqRGBPalette.backgroundKey) == nil {
                    Color(uiColor: .systemBackground)
                } else {
                    theme.backdrop
                    LinearGradient(
                        colors: [
                            theme.stageColors[0].opacity(theme == .nocturne ? 0.32 : 0.75),
                            theme.backdrop,
                            theme.stageColors[2].opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if theme.isAtmospheric || theme.isEnergetic {
                        Circle()
                            .fill(theme.accent.opacity(theme == .anime ? 0.18 : 0.14))
                            .frame(width: 320, height: 320)
                            .blur(radius: 75)
                            .offset(x: geometry.size.width * 0.35,
                                    y: -geometry.size.height * 0.27)
                    }
                    if theme.isEditorial {
                        LinearGradient(
                            colors: [.black.opacity(0.26), .clear, .black.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
// MARK: - 06J streaming experience semantics (presentation only)
// Stable raw values above are user-data identifiers. Do not rename or reorder them.
extension KinetiqVisualTheme {
    enum ExperienceFamily: String {
        case original, cinematic, anime, editorial, library, video, series
    }
    var family: ExperienceFamily {
        switch self {
        case .signature: .original
        case .cinema, .prism, .nebula: .cinematic
        case .anime, .ember: .anime
        case .nocturne, .atelier, .zen: .editorial
        case .studio, .vault: .library
        case .signal: .video
        case .aurora: .series
        }
    }
    // A theme can change layout priorities, never create a catalogue or entitlement.
    var prefersLocalLibrary: Bool { self == .vault }
    var prefersEpisodeOrganization: Bool { family == .anime || family == .series }
    var prefersCompactThumbnails: Bool { self == .signal }
    var prefersEditorialCopy: Bool { family == .editorial }
    var inspirationDisclosure: String {
        self == .signature ? "Independent Kinetiq design" : "Design inspiration only. Not affiliated with the named service."
    }
}


// MARK: - Batch 06J: App-only RGB customization (no player overlays)
// These keys are independent of legacy accent presets and persisted theme IDs.
enum KinetiqRGBPalette {
    static let enabledKey = "kinetiq.rgb.enabled.v1"
    static let accentKey = "kinetiq.rgb.accent.hex.v1"
    static let backgroundKey = "kinetiq.rgb.background.hex.v1"
    static let surfaceKey = "kinetiq.rgb.surface.hex.v1"
    static let savedPalettesKey = "kinetiq.rgb.savedPalettes.v1"

    static func normalizedHEX(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6,
              hex.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value) ||
                  (65...70).contains(scalar.value) ||
                  (97...102).contains(scalar.value)
              }),
              let value = UInt32(hex, radix: 16) else { return nil }
        return String(format: "#%06X", value)
    }

    static func color(hex: String) -> Color? {
        guard let normalized = normalizedHEX(hex),
              let value = UInt32(normalized.dropFirst(), radix: 16) else { return nil }
        return Color(.sRGB,
                     red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255,
                     opacity: 1)
    }

    static func rgb(_ color: Color) -> (red: Int, green: Int, blue: Int) {
        let ui = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }
        return (64, 192, 232)
    }

    static func hex(_ color: Color) -> String {
        let c = rgb(color)
        return String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
    }

    static func customColor(for key: String) -> Color? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey),
              let hex = defaults.string(forKey: key) else { return nil }
        return color(hex: hex)
    }

    static func luminance(of color: Color) -> Double {
        let c = rgb(color)
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    static func contrastWithWhite(on color: Color) -> Double {
        1.05 / (luminance(of: color) + 0.05)
    }

    static func readableText(on color: Color) -> Color {
        luminance(of: color) > 0.179 ? .black : .white
    }
}

// Accessible from Settings > Themes > RGB Studio. The editor is not installed in
// the media player hierarchy and cannot interfere with PiP, captions, or gestures.
@MainActor
struct KinetiqRGBStudio: View {
    private enum Role: String, CaseIterable, Identifiable {
        case accent = "Accent", background = "Background", surface = "Surface"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .accent: "paintbrush.fill"
            case .background: "square.on.square.fill"
            case .surface: "rectangle.inset.filled"
            }
        }
    }

    @AppStorage(KinetiqRGBPalette.enabledKey) private var enabled = false
    @AppStorage(KinetiqRGBPalette.accentKey) private var accentHEX = ""
    @AppStorage(KinetiqRGBPalette.backgroundKey) private var backgroundHEX = ""
    @AppStorage(KinetiqRGBPalette.surfaceKey) private var surfaceHEX = ""
    @AppStorage(KinetiqRGBPalette.savedPalettesKey) private var savedPalettesJSON = ""
    @AppStorage(KinetiqVisualTheme.storageKey) private var themeID = KinetiqVisualTheme.signature.rawValue
    @State private var role: Role = .accent
    @State private var hexDraft = ""
    @State private var invalidHEX = false
    @State private var newPaletteName = ""

    private struct SavedPalette: Codable, Identifiable {
        let id: String
        let name: String
        let accent: String
        let background: String
        let surface: String
    }
    private var savedPalettes: [SavedPalette] {
        guard let data = savedPalettesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SavedPalette].self, from: data)) ?? []
    }
    private func writePalettes(_ palettes: [SavedPalette]) {
        guard let data = try? JSONEncoder().encode(palettes) else { return }
        savedPalettesJSON = String(decoding: data, as: UTF8.self)
    }
    private func savePalette() {
        let name = newPaletteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var palettes = savedPalettes
        palettes.append(SavedPalette(id: UUID().uuidString,
                                     name: name,
                                     accent: storedHEX(.accent),
                                     background: storedHEX(.background),
                                     surface: storedHEX(.surface)))
        writePalettes(palettes)
        newPaletteName = ""
    }
    private func loadPalette(_ palette: SavedPalette) {
        accentHEX = palette.accent
        backgroundHEX = palette.background
        surfaceHEX = palette.surface
        enabled = true
        hexDraft = storedHEX(role)
        invalidHEX = false
    }
    private func removePalette(_ palette: SavedPalette) {
        writePalettes(savedPalettes.filter { $0.id != palette.id })
    }

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeID) ?? .signature
    }
    private func baseColor(_ role: Role) -> Color {
        switch role {
        case .accent: theme.defaultAccent
        case .background: theme.defaultBackdrop
        case .surface: Color(red: 0.16, green: 0.19, blue: 0.25)
        }
    }
    private func storedHEX(_ role: Role) -> String {
        let raw: String
        switch role {
        case .accent: raw = accentHEX
        case .background: raw = backgroundHEX
        case .surface: raw = surfaceHEX
        }
        return KinetiqRGBPalette.normalizedHEX(raw) ?? KinetiqRGBPalette.hex(baseColor(role))
    }
    private func setHEX(_ value: String, for role: Role) {
        guard let normalized = KinetiqRGBPalette.normalizedHEX(value) else { return }
        switch role {
        case .accent: accentHEX = normalized
        case .background: backgroundHEX = normalized
        case .surface: surfaceHEX = normalized
        }
        hexDraft = normalized
        invalidHEX = false
    }
    private func ensureColors() {
        if KinetiqRGBPalette.normalizedHEX(accentHEX) == nil {
            accentHEX = KinetiqRGBPalette.hex(theme.defaultAccent)
        }
        if KinetiqRGBPalette.normalizedHEX(backgroundHEX) == nil {
            backgroundHEX = KinetiqRGBPalette.hex(theme.defaultBackdrop)
        }
        if KinetiqRGBPalette.normalizedHEX(surfaceHEX) == nil {
            surfaceHEX = KinetiqRGBPalette.hex(baseColor(.surface))
        }
    }
    private var selectedColor: Color {
        KinetiqRGBPalette.color(hex: storedHEX(role)) ?? baseColor(role)
    }
    private var pickerBinding: Binding<Color> {
        Binding(get: { selectedColor }, set: { setHEX(KinetiqRGBPalette.hex($0), for: role) })
    }
    private func channelBinding(_ channel: Int) -> Binding<Double> {
        Binding(
            get: {
                let c = KinetiqRGBPalette.rgb(selectedColor)
                return Double(channel == 0 ? c.red : (channel == 1 ? c.green : c.blue))
            },
            set: { value in
                var c = KinetiqRGBPalette.rgb(selectedColor)
                let rounded = max(0, min(255, Int(value.rounded())))
                switch channel {
                case 0: c.red = rounded
                case 1: c.green = rounded
                default: c.blue = rounded
                }
                setHEX(String(format: "#%02X%02X%02X", c.red, c.green, c.blue), for: role)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable custom RGB colors", isOn: $enabled)
                    .tint(theme.defaultAccent)
                    .onChange(of: enabled) { _, newValue in
                        if newValue { ensureColors() }
                    }
                Text("Customizations are saved on this device. All thirteen experiences preserve their original layouts and media data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: { Text("RGB Studio") }

            Section("Color role") {
                Picker("Edit", selection: $role) {
                    ForEach(Role.allCases) { choice in
                        Label(choice.rawValue, systemImage: choice.icon).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: role) { _, newValue in
                    hexDraft = storedHEX(newValue)
                    invalidHEX = false
                }
                ColorPicker("Choose \(role.rawValue.lowercased()) color", selection: pickerBinding, supportsOpacity: false)
                    .disabled(!enabled)
            }

            Section("Precise RGB · 0–255") {
                ForEach(0..<3, id: \.self) { index in
                    let binding = channelBinding(index)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(["Red", "Green", "Blue"][index])
                            Spacer()
                            TextField("0–255", value: Binding<Int>(
                                get: { Int(binding.wrappedValue) },
                                set: { binding.wrappedValue = Double(max(0, min(255, $0))) }
                            ), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .frame(width: 65)
                                .accessibilityLabel("\(["Red", "Green", "Blue"][index]) channel, 0 to 255")
                        }
                        Slider(value: binding, in: 0...255, step: 1)
                            .tint(index == 0 ? .red : (index == 1 ? .green : .blue))
                            .accessibilityLabel(["Red", "Green", "Blue"][index])
                            .accessibilityValue("\(Int(binding.wrappedValue)) of 255")
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    TextField("#RRGGBB", text: $hexDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .submitLabel(.done)
                        .onSubmit(applyHEX)
                        .accessibilityLabel("Six digit hexadecimal color")
                    Button("Apply HEX", action: applyHEX)
                }
                if invalidHEX {
                    Text("Enter a six-digit HEX color, for example #FF483F.")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .disabled(!enabled)

            Section("Saved palettes") {
                HStack(spacing: 8) {
                    TextField("Palette name", text: $newPaletteName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(savePalette)
                    Button("Save", action: savePalette)
                        .disabled(newPaletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(savedPalettes) { palette in
                    Button {
                        loadPalette(palette)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(KinetiqRGBPalette.color(hex: palette.accent) ?? .gray)
                                .frame(width: 20, height: 20)
                            Circle().fill(KinetiqRGBPalette.color(hex: palette.background) ?? .black)
                                .frame(width: 20, height: 20)
                            Circle().fill(KinetiqRGBPalette.color(hex: palette.surface) ?? .gray)
                                .frame(width: 20, height: 20)
                            Text(palette.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            removePalette(palette)
                        } label: {
                            Label("Delete palette", systemImage: "trash")
                        }
                    }
                }
                if savedPalettes.isEmpty {
                    Text("Save your own RGB combinations and restore them with one tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Live preview") {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(KinetiqRGBPalette.color(hex: backgroundHEX) ?? theme.defaultBackdrop)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("KINETIQ", systemImage: theme.heroSymbol)
                                .font(.caption.weight(.heavy))
                            Spacer()
                            Text(theme.name).font(.caption)
                        }
                        .foregroundStyle(KinetiqRGBPalette.readableText(on: KinetiqRGBPalette.color(hex: backgroundHEX) ?? theme.defaultBackdrop))
                        Text("Every story starts here.")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(KinetiqRGBPalette.readableText(on: KinetiqRGBPalette.color(hex: backgroundHEX) ?? theme.defaultBackdrop))
                        HStack {
                            Text("Explore")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 17)
                                .padding(.vertical, 10)
                                .foregroundStyle(KinetiqRGBPalette.readableText(on: KinetiqRGBPalette.color(hex: accentHEX) ?? theme.defaultAccent))
                                .background(KinetiqRGBPalette.color(hex: accentHEX) ?? theme.defaultAccent, in: Capsule())
                            Spacer()
                            RoundedRectangle(cornerRadius: 7)
                                .fill(KinetiqRGBPalette.color(hex: surfaceHEX) ?? baseColor(.surface))
                                .frame(width: 64, height: 48)
                        }
                    }
                    .padding(20)
                }
                .frame(height: 208)
                .accessibilityElement(children: .combine)
                if enabled,
                   KinetiqRGBPalette.contrastWithWhite(
                       on: KinetiqRGBPalette.color(hex: backgroundHEX) ?? theme.defaultBackdrop
                   ) < 4.5 {
                    Label("High-brightness backgrounds can reduce contrast on older dark-themed screens. Choose a darker background for readability.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Restore this role's default") {
                    setHEX(KinetiqRGBPalette.hex(baseColor(role)), for: role)
                }
                Button("Reset all custom colors", role: .destructive) {
                    enabled = false
                    accentHEX = ""
                    backgroundHEX = ""
                    surfaceHEX = ""
                    hexDraft = KinetiqRGBPalette.hex(baseColor(role))
                    invalidHEX = false
                }
            }
        }
        .navigationTitle("RGB Studio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hexDraft = storedHEX(role)
        }
        .onChange(of: themeID) { _, _ in
            hexDraft = storedHEX(role)
        }
    }

    private func applyHEX() {
        guard let hex = KinetiqRGBPalette.normalizedHEX(hexDraft) else {
            invalidHEX = true
            return
        }
        setHEX(hex, for: role)
    }
}