import SwiftUI
import Foundation
import UserNotifications
import CryptoKit

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

    // Retained to preserve existing user preferences.
    @AppStorage("kinetiq.appearance.liquidGlassButtons")
    private var useLiquidGlassDock = false

    @StateObject private var whatsNewStore = WhatsNewStore()
    @State private var showingWhatsNew = false
    @State private var showingThemeGallery = false
    @AppStorage(KinetiqEpisodeAlerts.enabledKey)
    private var episodeAlertsEnabled = false
    @AppStorage(KinetiqEpisodeAlerts.favoritesOnlyKey)
    private var episodeAlertsFavoritesOnly = true
    @State private var episodeAlertStatus: String?
    @AppStorage(KinetiqEpisodeAlerts.genreRecommendationsKey)
    private var genreNotificationsEnabled = false
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

                Section("Anime Discovery") {
                    NavigationLink {
                        KinetiqAiringCalendarView()
                    } label: {
                        Label("Anime release calendar", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        KinetiqMetadataSettingsView()
                    } label: {
                        Label("Episode metadata & artwork", systemImage: "photo.on.rectangle.angled")
                    }
                }

                Section {
                    Toggle("iPhone episode notifications", isOn: $episodeAlertsEnabled)
                        .onChange(of: episodeAlertsEnabled) { _, enabled in
                            guard enabled else {
                                episodeAlertStatus = "Episode notifications paused."
                                Task { await KinetiqEpisodeAlerts.clearCalendarAlerts() }
                                return
                            }
                            Task {
                                do {
                                    let granted = try await KinetiqEpisodeAlerts.requestPermission()
                                    if !granted { episodeAlertsEnabled = false }
                                    episodeAlertStatus = granted
                                        ? "Allowed: verified releases can be scheduled."
                                        : "Permission denied. Check iOS Settings."
                                } catch {
                                    episodeAlertsEnabled = false
                                    episodeAlertStatus = "Unable to request permission."
                                }
                            }
                        }
                    Toggle("Only followed or favorited anime", isOn: $episodeAlertsFavoritesOnly)
                        .disabled(!episodeAlertsEnabled)
                    Toggle("Notify for preferred genres", isOn: $genreNotificationsEnabled)
                        .disabled(!episodeAlertsEnabled || episodeAlertsFavoritesOnly)
                    Button("Send test alert in 10 seconds", systemImage: "bell.badge") {
                        Task {
                            do {
                                try await KinetiqEpisodeAlerts.schedulePreview()
                                episodeAlertStatus = "Test scheduled. Lock the screen or switch apps."
                            } catch {
                                episodeAlertStatus = "Unable to schedule. Check permission."
                            }
                        }
                    }
                    .disabled(!episodeAlertsEnabled)
                    if let episodeAlertStatus {
                        Text(episodeAlertStatus).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Episode Notifications")
                } footer: {
                    Text("Calendar alerts use published airtimes and are delivered locally after scheduling. Newly announced dates while the app is closed require a later push service.")
                }

                Section("Integrations") {
                    NavigationLink {
                        KinetiqDiscordPresenceSettingsView()
                    } label: {
                        Label("Discord Presence Lab", systemImage: "person.crop.circle.badge.checkmark")
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

            Section {
                HStack {
                    Text("External subtitle offset")
                    Spacer()
                    Text(String(format: "%+.2f s", settings.sourceTimingOffset))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.sourceTimingOffset, in: -5...5, step: 0.25)
                    .accessibilityLabel("External subtitle timing offset")
                Button("Reset subtitle timing") { settings.sourceTimingOffset = 0 }
                    .disabled(settings.sourceTimingOffset == 0)
            } header: {
                Text("Synchronization")
            } footer: {
                Text("Correct imported and module-provided SRT/WebVTT subtitles by up to five seconds. Embedded tracks keep their original timestamps.")
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
    @AppStorage(KinetiqRGBPalette.enabledKey)
    private var rgbStudioEnabled = false
    @State private var showingRGBOverrideDecision = false

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
                    themeCollection("KINETIQ ORIGINAL", choices: [.signature])
                    themeCollection("CINEMATIC & SERIES", choices: [.cinema, .prism, .nebula, .aurora, .studio])
                    themeCollection("ANIME", choices: [.anime, .ember])
                    themeCollection("EDITORIAL CINEMA", choices: [.nocturne, .atelier, .zen])
                    themeCollection("LIBRARY & VIDEO", choices: [.vault, .signal])
                    rgbSection
                    motionSection
                    Text("These are independent Kinetiq experiences inspired by streaming design patterns, not affiliated with the named services. Shared source permissions, media history and player technology remain unchanged. iOS Reduce Motion takes precedence.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(theme.backdrop.ignoresSafeArea())
            .overlay(alignment: .top) {
                if showingRGBOverrideDecision {
                    rgbOverrideDecisionBanner
                        .transition(reduceMotion ? .opacity :
                            .move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 14)
                        .padding(.top, 7)
                } else {
                    KinetiqNoticeBannerHost()
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) :
                .spring(response: 0.43, dampingFraction: 0.84),
                value: showingRGBOverrideDecision)
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
            // Selecting a theme never silently disables RGB Studio or blocks navigation.
            if rgbStudioEnabled {
                withAnimation(reduceMotion ? nil : .spring(response: 0.43, dampingFraction: 0.84)) {
                    showingRGBOverrideDecision = true
                }
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
                    if option != .signature {
                        Text("Inspired by · independent Kinetiq UI")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
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

    /// Stays visible until the user chooses. A normal auto-dismiss notification
    /// would be inappropriate because it contains a configuration decision.
    private var rgbOverrideDecisionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "paintpalette.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 29)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RGB Studio is still enabled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Your new theme is selected, but custom RGB colors still override its accent, background and surface. Turn off RGB Studio to see the theme's original colors?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    rgbStudioEnabled = false
                    showingRGBOverrideDecision = false
                    KinetiqNoticeCenter.shared.post(
                        .success, title: "RGB Studio disabled",
                        message: "Your selected theme now uses its own colors. Your custom palette is saved for later.",
                        groupKey: "kinetiq.rgb.themeChoice.disabled"
                    )
                } label: {
                    Label("Yes", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Yes, disable RGB Studio")
                Button {
                    showingRGBOverrideDecision = false
                    KinetiqNoticeCenter.shared.post(
                        .information, title: "RGB Studio kept enabled",
                        message: "The theme changed, but your RGB custom colors remain active.",
                        groupKey: "kinetiq.rgb.themeChoice.kept"
                    )
                } label: {
                    Label("No", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("No, keep RGB Studio enabled")
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 8)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .contain)
    }

    // Live miniature of each preset's navigation and artwork geometry.
    private func themeMiniature(_ option: KinetiqVisualTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(7, option.cardCornerRadius * 0.5))
                .fill(option.backdrop)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(option.defaultAccent).frame(width: 5, height: 5)
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
                        Capsule().fill(option.defaultAccent).frame(width: 25, height: 9)
                    }
                    .padding(7)
                }
                .frame(height: 34)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: option.isEditorial ? 2 : 5)
                            .fill(index == 0 ? option.defaultAccent.opacity(0.75)
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
                .strokeBorder(option.defaultAccent.opacity(0.30), lineWidth: 1)
        }
    }

    private var rgbSection: some View {
        NavigationLink {
            KinetiqRGBStudio()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text("RGB Studio")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Custom accent, background & surface · precise RGB 0–255 · HEX")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(17)
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Customize app-wide RGB colors. No player settings are changed.")
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
// MARK: - Real iPhone Episode Notifications (06K.6B)

@MainActor
enum KinetiqEpisodeAlerts {
    static let enabledKey = "kinetiq.episodeAlerts.enabled"
    static let favoritesOnlyKey = "kinetiq.episodeAlerts.favoritesOnly"
    static let didOpenEpisode = Notification.Name("kinetiq.episodeAlerts.openEpisode")
    static let didOpenCalendar = Notification.Name("kinetiq.episodeAlerts.openCalendar")
    static let genreRecommendationsKey = "kinetiq.episodeAlerts.genreRecommendations"
    struct Route {
        let animeTitle: String
        let alternativeTitles: [String]
        let sourceID: String?
        let animeID: String?
    }
    private static var pendingRoute: Route?
    private static var pendingCalendar = false
    static func takePendingCalendar() -> Bool {
        defer { pendingCalendar = false }
        return pendingCalendar
    }
    static func takePendingRoute() -> Route? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
    static func route(from userInfo: [AnyHashable: Any]) -> Route? {
        let title = (userInfo["animeTitle"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (userInfo["sourceID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let anime = (userInfo["animeID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !title.isEmpty || (source != nil && anime != nil) else { return nil }
        return Route(animeTitle: title,
                     alternativeTitles: userInfo["animeAliases"] as? [String] ?? [],
                     sourceID: source, animeID: anime)
    }
    static func openAnime(_ title: String, alternativeTitles: [String] = []) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        pendingCalendar = false
        pendingRoute = Route(animeTitle: clean, alternativeTitles: alternativeTitles,
                             sourceID: nil, animeID: nil)
        NotificationCenter.default.post(name: didOpenEpisode, object: nil)
    }
    static func receiveResponse(userInfo: [AnyHashable: Any]) {
        if let route = route(from: userInfo) {
            pendingCalendar = false
            pendingRoute = route
            NotificationCenter.default.post(name: didOpenEpisode, object: nil)
            return
        }
        // Compatibility with already-scheduled calendar notifications that
        // predate the anime title payload.
        if (userInfo["kinetiqCalendar"] as? Bool) == true {
            pendingRoute = nil
            pendingCalendar = true
            NotificationCenter.default.post(name: didOpenCalendar, object: nil)
            return
        }
    }
    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }

    /// Only schedule verified dates; never invent episode release times.
    @discardableResult
    static func scheduleVerifiedEpisode(
        animeTitle: String, episodeNumber: String?, episodeName: String?,
        sourceID: String, animeID: String, releaseDate: Date,
        episodeImageURL: URL? = nil
    ) async throws -> Bool {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              releaseDate > Date().addingTimeInterval(5),
              !animeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sourceID.isEmpty, !animeID.isEmpty else { return false }
        if UserDefaults.standard.object(forKey: favoritesOnlyKey) as? Bool != false {
            guard ModuleAnimeCollectionStore.shared.favorites.contains(where: {
                $0.sourceID == sourceID && $0.animeID == animeID
            }) else { return false }
        }
        let number = episodeNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = episodeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [sourceID, animeID, number ?? "", name ?? ""].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let content = UNMutableNotificationContent()
        content.title = String(animeTitle.prefix(110))
        let label = number.flatMap { $0.isEmpty ? nil : "Episode \($0)" } ?? "New episode"
        content.subtitle = name.flatMap { $0.isEmpty ? nil : "\(label) · \($0)" } ?? label
        content.body = "Tap to find this anime across your trusted Kinetiq sources."
        content.sound = .default
        content.threadIdentifier = "kinetiq.episodes"
        var notificationInfo: [String: Any] = ["sourceID": sourceID, "animeID": animeID,
                                                "animeTitle": animeTitle]
        if let name, !name.isEmpty { notificationInfo["episodeName"] = name }
        if let episodeImageURL, episodeImageURL.scheme == "https" {
            if episodeImageURL.query == nil, episodeImageURL.user == nil {
                notificationInfo["artworkURL"] = episodeImageURL.absoluteString
            }
            if let artwork = await KinetiqEpisodeNotificationArtwork.attachment(for: episodeImageURL) {
                content.attachments = [artwork]
            }
        }
        content.userInfo = notificationInfo
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: releaseDate
        )
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "kinetiq.episode.\(digest)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        )
        return true
    }

    static func schedulePreview() async throws {
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            throw NSError(domain: "KinetiqEpisodeAlerts", code: 1)
        }
        let content = UNMutableNotificationContent()
        content.title = "Kinetiq · Test notification"
        content.subtitle = "Episode 1 — Sample episode"
        content.body = "Preview only. No new episode was detected."
        content.sound = .default
        content.threadIdentifier = "kinetiq.episodes"
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "kinetiq.episode.preview",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            )
        )
    }
}

/// Native iPhone notification artwork must be a local attachment. A remote
/// HTTPS cover/still is downloaded to a size-limited cache at schedule time.
/// Missing or unsupported artwork never prevents the episode alert itself.
@MainActor
private enum KinetiqEpisodeNotificationArtwork {
    static func attachment(for imageURL: URL) async -> UNNotificationAttachment? {
        guard imageURL.scheme?.lowercased() == "https" else { return nil }
        let identifier = SHA256.hash(data: Data(imageURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KinetiqEpisodeArtwork", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            for ext in ["jpg", "png"] {
                let cached = folder.appendingPathComponent("\(identifier).\(ext)")
                if FileManager.default.fileExists(atPath: cached.path),
                   let existing = try? UNNotificationAttachment(
                    identifier: "kinetiq-episode-cover", url: cached, options: nil
                   ) { return existing }
            }

            var request = URLRequest(url: imageURL)
            request.timeoutInterval = 6
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let ext: String
            switch response.mimeType?.lowercased() {
            case "image/jpeg", "image/jpg": ext = "jpg"
            case "image/png": ext = "png"
            default: return nil
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0 && fileSize <= 4_000_000 else { return nil }
            let destination = folder.appendingPathComponent("\(identifier).\(ext)")
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return try? UNNotificationAttachment(identifier: "kinetiq-episode-cover",
                                                 url: destination, options: nil)
        } catch {
            return nil
        }
    }
}
// MARK: - 06K.7 · Anime schedule models and verified release provider

struct KinetiqCalendarMedia: Codable, Identifiable {
    struct Title: Codable { let english: String?; let romaji: String?; let native: String? }
    struct Cover: Codable { let large: String? }
    struct StartDate: Codable { let year: Int?; let month: Int?; let day: Int? }
    struct StreamingEpisode: Codable {
        let title: String?
        let thumbnail: String?

        func episodeName(number: Int) -> String? {
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let prefix = "(?i)^\\s*(?:(?:episode|ep\\.?)\\s*)?0*\(number)\\s*[-:–—]?\\s*"
            let stripped = title.replacingOccurrences(of: prefix, with: "",
                options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? nil : stripped
        }
    }
    let id: Int
    let title: Title
    let synonyms: [String]?
    let genres: [String]?
    let coverImage: Cover?
    let isAdult: Bool?
    let siteUrl: String?
    let status: String?
    let startDate: StartDate?
    let streamingEpisodes: [StreamingEpisode]?
    var name: String {
        [title.english, title.romaji, title.native]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Anime"
    }
    var names: [String] {
        [title.english, title.romaji, title.native].compactMap { $0 } + (synonyms ?? [])
    }
    func episodeMetadata(number: Int) -> StreamingEpisode? {
        guard number > 0 else { return nil }
        let expression = "(?i)(?:\\b(?:episode|ep\\.?)\\s*0*\(number)\\b|^0*\(number)\\b)"
        return streamingEpisodes?.first {
            $0.title?.range(of: expression, options: .regularExpression) != nil
        }
    }
    var premiereDate: String {
        guard let d = startDate, let year = d.year else { return "Release date TBA" }
        if let month = d.month, let day = d.day,
           let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) {
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
        if let month = d.month,
           let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) {
            return date.formatted(.dateTime.month(.wide).year())
        }
        return String(year)
    }
}
struct KinetiqCalendarEpisode: Codable, Identifiable {
    let id: Int
    let episode: Int
    let airingAt: Int
    let media: KinetiqCalendarMedia?
    var date: Date { Date(timeIntervalSince1970: TimeInterval(airingAt)) }
}
private struct KinetiqCalendarResponse: Decodable {
    struct Payload: Decodable {
        struct Page: Decodable {
            struct PageInfo: Decodable { let hasNextPage: Bool? }
            let pageInfo: PageInfo?
            let airingSchedules: [KinetiqCalendarEpisode]?
            let media: [KinetiqCalendarMedia]?
        }
        let page: Page?
        enum CodingKeys: String, CodingKey { case page = "Page" }
    }
    struct APIError: Decodable { let message: String? }
    let data: Payload?
    let errors: [APIError]?
}
enum KinetiqCalendarRelevance {
    static func key(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }
    static func isFavorite(_ media: KinetiqCalendarMedia, names: Set<String>) -> Bool {
        media.names.contains { names.contains(key($0)) }
    }
    static func matchesGenre(_ media: KinetiqCalendarMedia, genres: Set<String>) -> Bool {
        !Set(media.genres ?? []).intersection(genres).isEmpty
    }
}

@MainActor
final class KinetiqCalendarStore: ObservableObject {
    @Published private(set) var episodes: [KinetiqCalendarEpisode] = []
    @Published private(set) var premieres: [KinetiqCalendarMedia] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var updatedAt: Date?

    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private static let episodesQuery = """
    query ($page:Int!, $after:Int!, $before:Int!) {
      Page(page:$page, perPage:50) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater:$after, airingAt_lesser:$before, sort:TIME) {
          id episode airingAt
          media { id title { english romaji native } synonyms genres
                  coverImage { large } isAdult siteUrl status
                  startDate { year month day }
                  streamingEpisodes { title thumbnail } }
        }
      }
    }
    """
    private static let premieresQuery = """
    query {
      Page(page:1, perPage:40) {
        media(type:ANIME, status:NOT_YET_RELEASED, sort:START_DATE, isAdult:false) {
          id title { english romaji native } synonyms genres
          coverImage { large } isAdult siteUrl status
          startDate { year month day }
          streamingEpisodes { title thumbnail }
        }
      }
    }
    """

    func refresh(force: Bool = false) async {
        guard !loading else { return }
        if !force, let updatedAt, Date().timeIntervalSince(updatedAt) < 900 { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let after = Int(Date().timeIntervalSince1970)
            let before = after + 14 * 86400
            var found: [KinetiqCalendarEpisode] = []
            for page in 1...7 {
                let result = try await send(Self.episodesQuery,
                                            variables: ["page":page, "after":after, "before":before])
                guard !Task.isCancelled else { return }
                guard let content = result.data?.page else { throw URLError(.cannotParseResponse) }
                found.append(contentsOf: (content.airingSchedules ?? []).filter {
                    $0.media != nil && $0.media?.isAdult != true && $0.date > Date()
                })
                if content.pageInfo?.hasNextPage != true { break }
            }
            var seen = Set<Int>()
            episodes = found.filter { seen.insert($0.id).inserted }
                .sorted { $0.airingAt < $1.airingAt }
            updatedAt = Date()
            do {
                let result = try await send(Self.premieresQuery, variables: [:])
                premieres = (result.data?.page?.media ?? []).filter { $0.isAdult != true }
            } catch {
                self.error = "Upcoming premieres are temporarily unavailable."
            }
        } catch {
            self.error = "Couldn't refresh the airing calendar. Try again when connected."
        }
    }

    private func send(_ query: String, variables: [String: Int]) async throws -> KinetiqCalendarResponse {
        let data = try JSONSerialization.data(withJSONObject: [
            "query": query, "variables": variables
        ])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(KinetiqCalendarResponse.self, from: responseData)
        if decoded.errors?.isEmpty == false { throw URLError(.cannotParseResponse) }
        return decoded
    }
}

extension KinetiqEpisodeAlerts {
    static func clearCalendarAlerts() async {
        let center = UNUserNotificationCenter.current()
        let pending: [UNNotificationRequest] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { items in
                continuation.resume(returning: items)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers:
            pending.filter { $0.identifier.hasPrefix("kinetiq.calendar.") }.map(\.identifier)
        )
    }

    // Local schedule only. A published airing time is not proof that a
    // connected video module already has the full episode.
    static func syncCalendar(
        events: [KinetiqCalendarEpisode],
        followed: Set<Int>,
        favoriteNames: Set<String>,
        preferredGenres: Set<String>
    ) async throws -> Int {
        guard !events.isEmpty else { return 0 }
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            await clearCalendarAlerts()
            return 0
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return 0 }
        let favoritesOnly = UserDefaults.standard.object(forKey: favoritesOnlyKey) as? Bool != false
        let genreOptIn = !favoritesOnly && UserDefaults.standard.bool(forKey: genreRecommendationsKey)
        let matches = events.filter { item in
            guard let media = item.media, media.isAdult != true,
                  item.date.timeIntervalSinceNow > 10 else { return false }
            let saved = followed.contains(media.id) ||
                KinetiqCalendarRelevance.isFavorite(media, names: favoriteNames)
            return saved || (genreOptIn &&
                KinetiqCalendarRelevance.matchesGenre(media, genres: preferredGenres))
        }.sorted { $0.airingAt < $1.airingAt }
        await clearCalendarAlerts()
        var count = 0
        for item in matches.prefix(40) {
            guard !Task.isCancelled, let media = item.media else { break }
            let episodeInfo = media.episodeMetadata(number: item.episode)
            let episodeName = episodeInfo?.episodeName(number: item.episode)
            let content = UNMutableNotificationContent()
            content.title = String(media.name.prefix(110))
            content.subtitle = episodeName.map { "Episode \(item.episode) · \($0)" }
                ?? "Episode \(item.episode) · scheduled release"
            content.body = "Expected airtime: \(item.date.formatted(date: .abbreviated, time: .shortened)). Streaming sources may publish it later."
            content.sound = .default
            content.threadIdentifier = "kinetiq.calendar"
            var info: [String: Any] = [
                "kinetiqCalendar": true, "mediaID": media.id,
                "animeTitle": media.name, "animeAliases": media.names,
                "episodeNumber": item.episode
            ]
            if let episodeName { info["episodeName"] = episodeName }
            let artworkCandidates = [episodeInfo?.thumbnail, media.coverImage?.large]
                .compactMap { $0 }
            if let displayedArtwork = artworkCandidates.first,
               let url = URL(string: displayedArtwork), url.scheme == "https" {
                info["artworkURL"] = url.absoluteString
            }
            for candidate in artworkCandidates {
                guard let url = URL(string: candidate), url.scheme == "https" else { continue }
                if let attachment = await KinetiqEpisodeNotificationArtwork.attachment(for: url) {
                    content.attachments = [attachment]
                    break
                }
            }
            content.userInfo = info
            try await center.add(UNNotificationRequest(
                identifier: "kinetiq.calendar.\(media.id).\(item.episode)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(10, item.date.timeIntervalSinceNow), repeats: false
                )
            ))
            count += 1
        }
        return count
    }
}

// MARK: - 06K.7 · Anime Calendar (Home and Settings)

@MainActor
struct KinetiqAiringCalendarView: View {
    private static let genres = [
        "Romance","Comedy","Slice of Life","Drama","Action","Adventure",
        "Fantasy","Mystery","Supernatural","Sci-Fi","Psychological","Sports","Music"
    ]
    @StateObject private var calendarStore = KinetiqCalendarStore()
    @StateObject private var favorites = ModuleAnimeCollectionStore.shared
    @AppStorage("kinetiq.calendar.followed.v1") private var followedRaw = ""
    @AppStorage("kinetiq.calendar.genres.v1") private var genresRaw = ""
    @AppStorage(KinetiqEpisodeAlerts.enabledKey) private var notificationsEnabled = false
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRaw = KinetiqVisualTheme.signature.rawValue

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var premieresMode = false
    @State private var forYou = false
    @State private var searchText = ""
    @State private var notificationMessage: String?
    @State private var sourceLookup: KinetiqAnimeSourceRequest?

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRaw) ?? .signature
    }
    private var followed: Set<Int> {
        Set(followedRaw.split(separator: ",").compactMap { Int($0) })
    }
    private var chosenGenres: Set<String> {
        Set(genresRaw.split(separator: "|").map(String.init))
    }
    private var favoriteNames: Set<String> {
        Set(favorites.favorites.map { KinetiqCalendarRelevance.key($0.title) })
    }
    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }
    private func isRelevant(_ media: KinetiqCalendarMedia) -> Bool {
        followed.contains(media.id) ||
        KinetiqCalendarRelevance.isFavorite(media, names: favoriteNames) ||
        KinetiqCalendarRelevance.matchesGenre(media, genres: chosenGenres)
    }
    private func findInSources(_ media: KinetiqCalendarMedia) {
        sourceLookup = KinetiqAnimeSourceRequest(title: media.name,
                                                 alternativeTitles: media.names)
    }
    private var todaysEpisodes: [KinetiqCalendarEpisode] {
        calendarStore.episodes.filter { event in
            guard let media = event.media else { return false }
            return Calendar.current.isDate(event.date, inSameDayAs: day) &&
                (!forYou || isRelevant(media)) &&
                (searchText.isEmpty || media.name.localizedCaseInsensitiveContains(searchText))
        }
    }
    private var upcomingTitles: [KinetiqCalendarMedia] {
        calendarStore.premieres.filter {
            (!forYou || isRelevant($0)) &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func follow(_ media: KinetiqCalendarMedia) {
        var ids = followed
        if !ids.insert(media.id).inserted { ids.remove(media.id) }
        followedRaw = ids.sorted().map(String.init).joined(separator: ",")
    }
    private func chooseGenre(_ genre: String) {
        var names = chosenGenres
        if !names.insert(genre).inserted { names.remove(genre) }
        genresRaw = names.sorted().joined(separator: "|")
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("UPCOMING ANIME")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                        Text("Release calendar")
                            .font(.system(size: 26, weight: .bold,
                                          design: theme.isEditorial ? .serif : .rounded))
                    }
                }
                Text("Follow anime you care about. Recommendations use your saved titles and selected genres.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("Notify me when followed episodes air", isOn: $notificationsEnabled)
                    .font(.subheadline.weight(.semibold))
                    .tint(theme.accent)
                    .padding(12)
                    .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 13))
                Picker("Browse", selection: $premieresMode) {
                    Text("Episode schedule").tag(false)
                    Text("Coming soon").tag(true)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    Toggle("For You", isOn: $forYou)
                        .font(.subheadline.weight(.semibold))
                        .tint(theme.accent)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(Self.genres, id: \.self) { genre in
                            Button {
                                chooseGenre(genre)
                            } label: {
                                Label(genre, systemImage: chosenGenres.contains(genre)
                                      ? "checkmark.circle.fill" : "heart")
                            }
                        }
                    } label: {
                        Label(chosenGenres.isEmpty ? "Genres" : "\(chosenGenres.count) genres",
                              systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .background(theme.cardBackground, in: Capsule())
                    }
                    .accessibilityLabel("Select preferred genres")
                }
                if calendarStore.loading {
                    ProgressView("Checking release schedules…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if let error = calendarStore.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if premieresMode {
                    Text("Upcoming premieres")
                        .font(.title3.weight(.bold))
                    Text("Following a series with no announced airtime saves your interest. No notification is scheduled until a verified episode time exists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if upcomingTitles.isEmpty && !calendarStore.loading {
                        ContentUnavailableView("No upcoming titles found", systemImage: "sparkles.tv",
                            description: Text("Try a different genre or refresh the calendar."))
                    }
                    ForEach(upcomingTitles) { media in
                        animeCard(media, episode: nil, releaseDate: nil)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days, id: \.self) { date in
                                let selected = Calendar.current.isDate(date, inSameDayAs: day)
                                Button {
                                    day = date
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                            .font(.caption2.weight(.semibold))
                                        Text(date.formatted(.dateTime.day()))
                                            .font(.title3.weight(.bold))
                                        Circle()
                                            .fill(theme.accent)
                                            .opacity(calendarStore.episodes.contains(where: {
                                                Calendar.current.isDate($0.date, inSameDayAs: date)
                                            }) ? 1 : 0)
                                            .frame(width: 5, height: 5)
                                    }
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .frame(width: 56, height: 78)
                                    .background(selected ? theme.accent : theme.cardBackground,
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            }
                        }
                    }
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title3.weight(.bold))
                    if todaysEpisodes.isEmpty && !calendarStore.loading {
                        ContentUnavailableView("No episodes listed", systemImage: "calendar",
                            description: Text("Try another day, or adjust the For You filter."))
                    }
                    ForEach(todaysEpisodes) { event in
                        if let media = event.media {
                            animeCard(media, episode: event.episode, releaseDate: event.date)
                        }
                    }
                }
                if let notificationMessage {
                    Label(notificationMessage, systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Airing information: AniList public API. All displayed times use your iPhone's time zone. Broadcast time does not guarantee stream availability in a connected module.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 18)
        }
        .background(KinetiqExperienceBackground())
        .navigationTitle("Anime Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find an upcoming anime")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await calendarStore.refresh(force: true)
                        await syncNotifications()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 40, height: 40)
                }
                .disabled(calendarStore.loading)
                .accessibilityLabel("Refresh anime calendar")
            }
        }
        .task {
            await calendarStore.refresh()
            await syncNotifications()
        }
        .onChange(of: followedRaw) { _, _ in Task { await syncNotifications() } }
        .onChange(of: genresRaw) { _, _ in Task { await syncNotifications() } }
        .onChange(of: notificationsEnabled) { _, enabled in
            Task {
                if enabled {
                    do {
                        let allowed = try await KinetiqEpisodeAlerts.requestPermission()
                        if allowed { await syncNotifications() }
                        else {
                            notificationsEnabled = false
                            notificationMessage = "Notification permission was denied."
                        }
                    } catch {
                        notificationsEnabled = false
                        notificationMessage = "Could not request iOS notification permission."
                    }
                } else {
                    await KinetiqEpisodeAlerts.clearCalendarAlerts()
                    notificationMessage = nil
                }
            }
        }
        .sheet(item: $sourceLookup) { request in
            KinetiqAnimeSourceLookupSheet(request: request)
        }
    }

    private func animeCard(_ media: KinetiqCalendarMedia,
                           episode: Int?, releaseDate: Date?) -> some View {
        let episodeInfo = episode.flatMap { media.episodeMetadata(number: $0) }
        let episodeName = episode.flatMap { episodeInfo?.episodeName(number: $0) }
        let artworkURL = (episodeInfo?.thumbnail ?? media.coverImage?.large)
            .flatMap { URL(string: $0) }
        return HStack(alignment: .top, spacing: 13) {
            Button { findInSources(media) } label: {
                AsyncImage(url: artworkURL) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFill()
                    } else {
                        Image(systemName: "film.stack")
                            .resizable().scaledToFit().padding(22)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 125)
                .background(theme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Find \(media.name) across all sources")
            VStack(alignment: .leading, spacing: 7) {
                Button { findInSources(media) } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Text(media.name)
                            .font(.subheadline.weight(.bold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.accent)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search all sources for \(media.name)")
                Text(releaseDate.map {
                    "Episode \(episode ?? 1) · \($0.formatted(date: .omitted, time: .shortened))"
                } ?? media.premiereDate)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.accent)
                if let episodeName {
                    Text(episodeName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Text((media.genres ?? []).prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Button {
                        follow(media)
                    } label: {
                        Label(followed.contains(media.id) ? "Following" : "Follow",
                              systemImage: followed.contains(media.id) ? "checkmark" : "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .frame(minHeight: 38)
                            .background(theme.accent.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(followed.contains(media.id)
                                        ? "Unfollow \(media.name)" : "Follow \(media.name)")
                    Button { findInSources(media) } label: {
                        Label("Find sources", systemImage: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Searches every installed trusted video module")
                }
                .foregroundStyle(theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func syncNotifications() async {
        guard notificationsEnabled, !calendarStore.episodes.isEmpty else { return }
        do {
            let count = try await KinetiqEpisodeAlerts.syncCalendar(
                events: calendarStore.episodes,
                followed: followed,
                favoriteNames: favoriteNames,
                preferredGenres: chosenGenres
            )
            notificationMessage = "\(count) future release alert(s) scheduled."
        } catch {
            notificationMessage = "Could not schedule release alerts. Check iOS settings."
        }
    }
}
