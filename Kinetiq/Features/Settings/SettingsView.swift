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

    @AppStorage("kinetiq.appearance.liquidGlassButtons")
    private var useLiquidGlassButtons = false

    @StateObject private var whatsNewStore = WhatsNewStore()
    @State private var showingWhatsNew = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }

    private var supportsLiquidGlassButtons: Bool {
        if #available(iOS 26.0, *) {
            return true
        }

        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $useLiquidGlassButtons) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Liquid Glass buttons")
                                .font(.body.weight(.medium))

                            Text("Use the native iOS 26 button appearance across Kinetiq.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(!supportsLiquidGlassButtons)

                    if !supportsLiquidGlassButtons {
                        Text("Liquid Glass buttons require iOS 26 or later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
            .task {
                await whatsNewStore.load()
            }
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView(releases: whatsNewStore.eligibleReleases)
            }
        }
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
                        ForEach(Array(releases.reversed().enumerated()), id: \.element.id) { index, release in
                            releaseSection(release)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(
                                    reduceMotion
                                    ? nil
                                    : .spring(response: 0.48, dampingFraction: 0.84)
                                        .delay(Double(index) * 0.07),
                                    value: appeared
                                )
                        }
                    }

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
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.top, 4)

                    Text("KINETIQ  •  YOUR MEDIA UNIVERSE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(24)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image("KinetiqLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .frame(width: 38, height: 38)
                    .background {
                        LinearGradient(
                            colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))

                            Text(item.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )
                }
            }
        }
        .padding(.bottom, 10)
    }
}
