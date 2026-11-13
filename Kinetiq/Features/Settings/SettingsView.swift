import SwiftUI
import Foundation

// MARK: - Release Notes Models

struct ReleaseNotesDocument: Codable {
    let releases: [KinetiqRelease]
}

struct KinetiqRelease: Codable, Identifiable {
    let version: String
    let date: String
    let title: String
    let notes: [KinetiqReleaseItem]

    var id: String { version }
}

struct KinetiqReleaseItem: Codable, Identifiable {
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

// MARK: - Release Notes Store

@MainActor
final class WhatsNewStore: ObservableObject {
    @Published private(set) var releases: [KinetiqRelease] = []

    private let cacheKey = "kinetiq.cachedReleaseNotes"
    private let lastSeenKey = "kinetiq.lastSeenWhatsNewVersion"

    private let remoteURL = URL(
        string: "https://raw.githubusercontent.com/Haimiya612/Kinetiq-iOS/main/release-notes.json"
    )!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }

    // Local fallback in case GitHub is unavailable on first launch.
    private let fallbackJSON = """
    {
      "releases": [
        {
          "version": "0.2.0",
          "date": "2026-11-02",
          "title": "A new chapter for Kinetiq",
          "notes": [
            {
              "symbol": "sparkles",
              "title": "A refreshed identity",
              "detail": "Kinetiq now has its own visual identity and app icon."
            },
            {
              "symbol": "square.grid.2x2",
              "title": "Five main destinations",
              "detail": "Home, Discover, Library, Modules and Profile form the foundation of the app."
            },
            {
              "symbol": "wand.and.stars",
              "title": "Refined animations",
              "detail": "Navigation and interface transitions have received a visual polish."
            },
            {
              "symbol": "gearshape",
              "title": "Appearance settings",
              "detail": "The settings area provides access to app appearance and version information."
            }
          ]
        },
        {
          "version": "0.3.0",
          "date": "2026-11-02",
          "title": "A better way to watch",
          "notes": [
            {
              "symbol": "arrow.up.left.and.arrow.down.right",
              "title": "Full-screen video player",
              "detail": "The player now gives your video the entire screen, with controls layered above it instead of taking up permanent layout space."
            },
            {
              "symbol": "slider.horizontal.3",
              "title": "Floating player controls",
              "detail": "Playback, audio, subtitle and other options open as translucent overlays while the video remains visible behind them."
            },
            {
              "symbol": "hand.tap",
              "title": "Tap to reveal or hide",
              "detail": "Tap the video to show or hide the player interface. Controls also fade away automatically during playback and remain available while paused."
            },
            {
              "symbol": "play.rectangle",
              "title": "Improved playback experience",
              "detail": "The updated layout makes better use of the display while keeping essential playback actions close at hand."
            }
          ]
        }
      ]
    }
    """

    var eligibleReleases: [KinetiqRelease] {
        releases
            .filter {
                $0.version.compare(
                    appVersion,
                    options: .numeric
                ) != .orderedDescending
            }
            .sorted {
                $0.version.compare(
                    $1.version,
                    options: .numeric
                ) == .orderedAscending
            }
    }

    var unseenReleases: [KinetiqRelease] {
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""

        return eligibleReleases.filter {
            lastSeen.isEmpty ||
            $0.version.compare(lastSeen, options: .numeric) == .orderedDescending
        }
    }

    var hasUnseenReleases: Bool {
        !unseenReleases.isEmpty
    }

    func load() async {
        // Load cached data immediately, so the UI has something available offline.
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey) {
            decodeAndStore(cachedData)
        } else if let fallbackData = fallbackJSON.data(using: .utf8) {
            decodeAndStore(fallbackData)
        }

        // Then try to retrieve the latest release notes from GitHub.
        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return
            }

            // Validate before replacing the existing cache.
            let document = try JSONDecoder().decode(
                ReleaseNotesDocument.self,
                from: data
            )

            guard !document.releases.isEmpty else { return }

            releases = document.releases.sorted {
                $0.version.compare(
                    $1.version,
                    options: .numeric
                ) == .orderedAscending
            }

            UserDefaults.standard.set(data, forKey: cacheKey)

        } catch {
            // Keep cached or fallback notes. No popup or crash caused by network failure.
            print("Kinetiq: Could not refresh release notes: \(error.localizedDescription)")
        }
    }

    func markLatestAsSeen() {
        guard let latest = eligibleReleases.last else { return }

        UserDefaults.standard.set(
            latest.version,
            forKey: lastSeenKey
        )
    }

    private func decodeAndStore(_ data: Data) {
        do {
            let document = try JSONDecoder().decode(
                ReleaseNotesDocument.self,
                from: data
            )

            releases = document.releases.sorted {
                $0.version.compare(
                    $1.version,
                    options: .numeric
                ) == .orderedAscending
            }
        } catch {
            print("Kinetiq: Could not read cached release notes.")
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue

    @AppStorage(AppStorageKey.accentColor)
    private var accentColorRawValue = AppAccentColor.kinetiq.rawValue

    // Retained to preserve existing user preferences.
    @AppStorage("kinetiq.appearance.liquidGlassButtons")
    private var useLiquidGlassDock = false

    @StateObject private var whatsNewStore = WhatsNewStore()
    @State private var showingWhatsNew = false
    @State private var showingThemeGallery = false
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var visualThemeRawValue = KinetiqVisualTheme.signature.rawValue

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }

    private var supportsLiquidGlassDock: Bool {
        if #available(iOS 26.0, *) {
            return true
        }

        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Appearance

                Section("Appearance") {
                    Button {
                        showingThemeGallery = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paintpalette.fill")
                                .font(.title3)
                                .foregroundStyle(KinetiqPalette.accent)
                                .frame(width: 38, height: 38)
                                .background(KinetiqPalette.accent.opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Themes")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(KinetiqVisualTheme(rawValue: visualThemeRawValue)?.name ?? "Signature")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose an app-wide experience and motion intensity")

                    VStack(alignment: .leading, spacing: 9) {
                        Text("System appearance")
                            .font(.subheadline.weight(.semibold))

                        Picker("System appearance", selection: $appearanceRawValue) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title)
                                    .tag(appearance.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent colour")
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(
                                    .flexible(),
                                    spacing: 12
                                ),
                                count: 3
                            ),
                            spacing: 14
                        ) {
                            ForEach(AppAccentColor.allCases) { accent in
                                accentOption(accent)
                            }
                        }

                        Text("Choose the colour used throughout Kinetiq's interface.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)

                    Toggle(isOn: $useLiquidGlassDock) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Liquid Glass dock")
                                .font(.body.weight(.medium))

                            Text("Show an interactive glass highlight that slides between the navigation tabs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                        }
                    }
                    .disabled(!supportsLiquidGlassDock)

                    if !supportsLiquidGlassDock {
                        Text("Liquid Glass dock requires iOS 26 or later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Playback") {
                    NavigationLink {
                        KinetiqSubtitleSettingsView()
                    } label: {
                        Label("Subtitles", systemImage: "captions.bubble")
                    }
                }

                // MARK: Modules & Sources

                Section("Modules & Sources") {
                    NavigationLink {
                        ModuleSourcesView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title3)
                                .foregroundStyle(KinetiqPalette.accent)
                                .frame(width: 38, height: 38)
                                .background(
                                    KinetiqPalette.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Manage Modules & Sources")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Add repository.json links and choose active modules.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: What's New

                Section("What's New") {
                    Button {
                        showingWhatsNew = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.title3)
                                .foregroundStyle(KinetiqPalette.cyan)
                                .frame(width: 38, height: 38)
                                .background(
                                    KinetiqPalette.cyan.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Update Log")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("See what's new in Kinetiq")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("v\(version)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }

                // MARK: About

                Section("About Kinetiq") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Platform", value: "iOS")
                    LabeledContent("Distribution", value: "Sideload")
                }

                Section("The idea") {
                    Text("Your Streams, Your Modules, Your Rules.")
                        .font(.system(.body, design: .rounded).weight(.semibold))

                    Text("Kinetiq is being built as a fluid, modular media experience.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(KinetiqExperienceBackground())
            .task {
                await whatsNewStore.load()
            }
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView(releases: whatsNewStore.eligibleReleases)
            }
            .sheet(isPresented: $showingThemeGallery) {
                KinetiqThemeGallery()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Accent Colour Option

    private func accentOption(_ accent: AppAccentColor) -> some View {
        let isSelected = accentColorRawValue == accent.rawValue

        return Button {
            accentColorRawValue = accent.rawValue
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(accent.accent)
                    .frame(width: 34, height: 34)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected
                                    ? Color.primary.opacity(0.45)
                                    : Color.primary.opacity(0.10),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }

                Text(accent.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accent.title) accent colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Subtitle Settings

@MainActor
private struct KinetiqSubtitleSettingsView: View {
    @ObservedObject private var settings = KinetiqSubtitleSettings.shared
    @State private var customTag = ""
    @State private var invalidTag = false

    init() {}

    private var languages: [String] {
        let choices = ["automatic", "off"] + KinetiqSubtitleSettings.commonLanguages
        return choices.contains(settings.language) ? choices : choices + [settings.language]
    }

    var body: some View {
        Form {
            Section {
                Picker("Default subtitles", selection: Binding(
                    get: { settings.language },
                    set: { value in _ = settings.setLanguage(value) }
                )) {
                    ForEach(languages, id: \.self) { tag in
                        Text(KinetiqSubtitleSettings.title(for: tag)).tag(tag)
                    }
                }
                DisclosureGroup("Other language") {
                    TextField("Language tag, e.g. en-GB", text: $customTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: customTag) { _, _ in invalidTag = false }
                    Button("Use language") {
                        if let tag = KinetiqCaptionLanguage.normalized(customTag), tag != "off" {
                            settings.setLanguage(tag)
                            customTag = ""
                            invalidTag = false
                        } else { invalidTag = true }
                    }
                    .disabled(customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if invalidTag { Text("Enter a language tag such as en or en-GB.").font(.caption) }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Automatic uses the system selection. If your chosen language is unavailable, optional captions stay off. You can pick another track in the player.")
            }

            Section {
                Picker("Size", selection: $settings.appearance.size) {
                    ForEach(KinetiqSubtitleAppearance.Size.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Text colour", selection: $settings.appearance.ink) {
                    ForEach(KinetiqSubtitleAppearance.Ink.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Background", selection: $settings.appearance.background) {
                    ForEach(KinetiqSubtitleAppearance.Background.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                KinetiqCaptionText(text: "Subtitle preview")
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 10))
                Button("Reset appearance") { settings.appearance = .init() }
                    .disabled(settings.appearance == .init())
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to source captions and native WebVTT subtitles. Other embedded formats use their native appearance.")
            }
        }
        .navigationTitle("Subtitles")
    }
}

// MARK: - What's New Screen

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let releases: [KinetiqRelease]

    @State private var appeared = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        Text("THE LATEST UPDATES")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2.5)
                            .foregroundStyle(KinetiqPalette.cyan)

                        Text("What's New")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .tracking(-1.2)

                        Text("Everything that's new in Kinetiq.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if releases.isEmpty {
                        ContentUnavailableView(
                            "No Release Notes",
                            systemImage: "doc.text",
                            description: Text("There are no update notes available for this version yet.")
                        )
                    } else {
                        ForEach(
                            Array(releases.reversed().enumerated()),
                            id: \.element.id
                        ) { index, release in
                            releaseSection(release)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(
                                    reduceMotion
                                        ? nil
                                        : .spring(
                                            response: 0.48,
                                            dampingFraction: 0.84
                                        )
                                        .delay(Double(index) * 0.07),
                                    value: appeared
                                )
                        }
                    }

                    Text("KINETIQ  •  YOUR MEDIA UNIVERSE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(24)
                .padding(.bottom, 18)
            }
        }
        // The action is outside the ScrollView and remains visible.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueFooter
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: Fixed Continue Footer

    private var continueFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text("Continue to Kinetiq")
                    Image(systemName: "arrow.right")
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background {
                    LinearGradient(
                        colors: [
                            KinetiqPalette.cyan,
                            KinetiqPalette.blue,
                            KinetiqPalette.violet
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image("KinetiqLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )

                Text("KINETIQ")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2)
            }

            Spacer()

            Text("VERSION \(version)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
    }

    // MARK: Release Sections

    private func releaseSection(_ release: KinetiqRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("VERSION \(release.version)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(KinetiqPalette.cyan)

                Spacer()

                Text(release.date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(release.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(spacing: 10) {
                ForEach(release.notes) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(KinetiqPalette.cyan)
                            .frame(width: 44, height: 44)
                            .background(
                                KinetiqPalette.cyan.opacity(0.11),
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(
                                    .system(
                                        .subheadline,
                                        design: .rounded
                                    )
                                    .weight(.bold)
                                )

                            Text(item.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                                .lineSpacing(3)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(
                            cornerRadius: 19,
                            style: .continuous
                        )
                    )
                }
            }
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Batch 06C: Theme gallery and motion preferences
// Only accessed through Settings → Appearance → Themes.
@MainActor
private struct KinetiqThemeGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var chosenTheme = KinetiqVisualTheme.signature.rawValue
    @AppStorage(KinetiqMotionMode.storageKey)
    private var chosenMotion = KinetiqMotionMode.balanced.rawValue

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: chosenTheme) ?? .signature
    }
    private var motion: KinetiqMotionMode {
        KinetiqMotionMode(rawValue: chosenMotion) ?? .balanced
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    Text("CHOOSE YOUR EXPERIENCE")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.67))
                        .padding(.top, 4)
                    themeCollection("KINETIQ ORIGINALS", choices: [.signature, .cinema, .anime, .aurora, .nocturne])
                    themeCollection("PREMIUM STREAMING", choices: [.studio, .prism, .atelier, .vault])
                    themeCollection("ENERGY & ATMOSPHERE", choices: [.signal, .ember, .zen, .nebula])
                    motionSection
                    Text("Thirteen theme presets redesign the app layout, color family and supported player surfaces without changing saved media, modules or account data. iOS Reduce Motion takes precedence.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(theme.backdrop.ignoresSafeArea())
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func themeCollection(_ title: String, choices: [KinetiqVisualTheme]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.caption2.weight(.bold)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.65))
                .accessibilityAddTraits(.isHeader)
            ForEach(choices) { choice in themeCard(choice) }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [theme.highlight.opacity(0.69), theme.accent.opacity(0.44), theme.backdrop],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack {
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 92))
                    .rotationEffect(.degrees(-14))
                    .foregroundStyle(.white.opacity(0.20))
                    .padding(18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("MAKE IT YOURS")
                    .font(.system(size: 10, weight: .heavy)).tracking(2.2)
                Text("Thirteen ways to watch.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Original experiences, one shared media library.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .frame(height: 182)
        .accessibilityElement(children: .combine)
    }

    private func themeCard(_ option: KinetiqVisualTheme) -> some View {
        let isCurrent = option == theme
        return Button {
            withAnimation(reduceMotion ? nil : motion.animation) {
                chosenTheme = option.rawValue
            }
        } label: {
            HStack(spacing: 14) {
                themeMiniature(option)
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCurrent ? option.accent : .white.opacity(0.30))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(option.cardSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(isCurrent ? option.accent.opacity(0.8) : .white.opacity(0.08), lineWidth: isCurrent ? 1.5 : 1))
            .scaleEffect(isCurrent && !reduceMotion && motion == .expressive ? 1.005 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name) theme")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // Live miniature of each preset's navigation and artwork geometry.
    private func themeMiniature(_ option: KinetiqVisualTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(7, option.cardCornerRadius * 0.5))
                .fill(option.backdrop)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(option.accent).frame(width: 5, height: 5)
                    Capsule().fill(.white.opacity(0.75)).frame(width: 27, height: 3)
                    Spacer(minLength: 0)
                }
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: max(3, option.cardCornerRadius * 0.25))
                        .fill(LinearGradient(colors: option.stageColors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    HStack {
                        Image(systemName: option.heroSymbol)
                            .font(.system(size: option.isEnergetic ? 20 : 17, weight: .light))
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        Capsule().fill(option.accent).frame(width: 25, height: 9)
                    }
                    .padding(7)
                }
                .frame(height: 34)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: option.isEditorial ? 2 : 5)
                            .fill(index == 0 ? option.accent.opacity(0.75)
                                             : option.highlight.opacity(0.42))
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 116, height: 78)
        .overlay {
            RoundedRectangle(cornerRadius: max(7, option.cardCornerRadius * 0.5))
                .strokeBorder(option.accent.opacity(0.30), lineWidth: 1)
        }
    }

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Motion intensity", systemImage: "waveform.path")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 7) {
                ForEach(KinetiqMotionMode.allCases) { choice in
                    Button {
                        withAnimation(reduceMotion ? nil : choice.animation) {
                            chosenMotion = choice.rawValue
                        }
                    } label: {
                        Text(choice.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chosenMotion == choice.rawValue ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(chosenMotion == choice.rawValue ? theme.accent : .white.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            if reduceMotion {
                Text("Reduce Motion is enabled in iOS Accessibility. Kinetiq will keep animations minimal.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(16)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 20))
    }
}