import SwiftUI
import UIKit

// MARK: - Continue Watching Thumbnail View

private struct ContinueWatchingThumbnailView: View {
    let mediaID: String
    let url: URL

    @State private var image: UIImage?

    private var requestID: String {
        "\(mediaID)|\(url.standardizedFileURL.path)"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: requestID) {
            image = nil

            let loadedImage = await LocalMediaThumbnailCache.shared.image(
                for: mediaID,
                url: url
            )

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.22)) {
                image = loadedImage
            }
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KinetiqPalette.blue,
                    KinetiqPalette.violet,
                    KinetiqPalette.cyan.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(.white.opacity(0.17), lineWidth: 1)
                .frame(width: 105, height: 105)
                .offset(x: 125, y: -10)

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

// MARK: - Home Media Mode

enum HomeMediaMode: String, CaseIterable, Identifiable {
    case video = "Video"
    case manga = "Manga"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .manga: "book.closed.fill"
        }
    }
}

// MARK: - Home Content Routing

/// Manga is a separate experience regardless of the selected video source.
enum HomeContentRoute: Equatable {
    case manga
    case localVideo
    case remoteVideo
    case unavailableSource

    static func resolve(
        mode: HomeMediaMode,
        isLocalLibrarySelected: Bool,
        sourceAvailable: Bool
    ) -> HomeContentRoute {
        if mode == .manga { return .manga }
        if isLocalLibrarySelected { return .localVideo }
        return sourceAvailable ? .remoteVideo : .unavailableSource
    }
}

// MARK: - Home View

struct HomeView: View {
    let tagline: String
    let continueWatching: [PlaybackHistoryEntry]

    let onDiscover: () -> Void
    let onModules: () -> Void
    let onContinueWatching: (PlaybackHistoryEntry) -> Void
    let onOpenLibrary: () -> Void

    @AppStorage("kinetiq.home.selectedMode.v1")
    private var selectedModeRawValue = HomeMediaMode.video.rawValue

    @State private var appeared = false
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRawValue = KinetiqVisualTheme.signature.rawValue
    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRawValue) ?? .signature
    }
    @State private var selectedSourceToBrowse: ModuleSourceOption?
    @State private var browseSourceInSearch = false
    @State private var showingSourcePicker = false
    @State private var openManageModulesAfterDismiss = false

    private var selectedMode: HomeMediaMode {
        HomeMediaMode(rawValue: selectedModeRawValue) ?? .video
    }

    @StateObject private var moduleSourceStore = ModuleSourceStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: remoteStreamingEnabled ? 4 : 13) {
            if remoteStreamingEnabled {
                streamingToolbar
            } else {
                sourcePicker
                mediaModeSwitcher
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: remoteStreamingEnabled ? 17 : 27) {
                    if !remoteStreamingEnabled { header }

                    switch HomeContentRoute.resolve(
                        mode: selectedMode,
                        isLocalLibrarySelected: moduleSourceStore.isLocalLibrarySelected,
                        sourceAvailable: moduleSourceStore.activeSource != nil
                    ) {
                    case .manga:
                        mangaPlaceholder
                    case .localVideo:
                        videoContent
                    case .remoteVideo:
                        if let activeSource = moduleSourceStore.activeSource {
                            remoteSourceHome(activeSource)
                                .id(activeSource.id) // Source data cannot leak across identities.
                        }
                    case .unavailableSource:
                        selectedModulePlaceholder
                    }
                }
                .padding(.horizontal, remoteStreamingEnabled ? 16 : 21)
                .padding(.top, remoteStreamingEnabled ? 6 : (theme == .nocturne ? 4 : 12))
                .padding(.bottom, 40)
            }
        }
        .padding(.top, remoteStreamingEnabled ? 3 : 10)
        .background(KinetiqExperienceBackground())
        .sheet(isPresented: $showingSourcePicker, onDismiss: {
            if openManageModulesAfterDismiss {
                openManageModulesAfterDismiss = false
                onModules()
            }
        }) {
            KinetiqSourcePickerSheet(
                store: moduleSourceStore,
                onManageModules: {
                    openManageModulesAfterDismiss = true
                    showingSourcePicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
        .sheet(item: $selectedSourceToBrowse) { source in
            KinetiqFocusedSourceSheet(
                source: source,
                startInSearch: browseSourceInSearch,
                initialQuery: "",
                onClose: { selectedSourceToBrowse = nil }
            )
        }
        .task {
            await moduleSourceStore.loadSavedRepositoriesIfNeeded()
        }
        .onAppear {
            LocalMediaThumbnailCache.shared.removeOrphans()

            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.72, dampingFraction: 0.88)
            ) {
                appeared = true
            }
        }
        .onChange(of: continueWatching.map(\.id)) { _, _ in
            // A completed item can disappear from Continue Watching while
            // its local file remains. Only files actually removed from the
            // library have their thumbnails cleaned up.
            LocalMediaThumbnailCache.shared.removeOrphans()
        }
    }

    private var remoteStreamingEnabled: Bool {
        selectedMode == .video && !moduleSourceStore.isLocalLibrarySelected &&
        moduleSourceStore.activeSource != nil
    }

    /// One compact, safe-area-respecting navigation row. The source selector
    /// remains a button, and Search is a separate 44-point target.
    private var streamingToolbar: some View {
        HStack(spacing: 10) {
            Button { showingSourcePicker = true } label: {
                HStack(spacing: 9) {
                    KinetiqModuleIcon(source: moduleSourceStore.activeSource, size: 35)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KINETIQ  ·  HOME")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.2)
                        Text(moduleSourceStore.activeSourceTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change source, current: \(moduleSourceStore.activeSourceTitle)")

            Button {
                selectedModeRawValue = HomeMediaMode.manga.rawValue
            } label: {
                Image(systemName: "book.closed")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(theme.cardBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch to manga")

            Button(action: onDiscover) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(theme.cardBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search all connected modules")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // Search is a distinct destination; Explore is in the Home feed.
    private func openSourceSearch() { onDiscover() }

    private func openSourceBrowser(_ source: ModuleSourceOption, search: Bool = false) {
        browseSourceInSearch = search
        selectedSourceToBrowse = source
    }

    // MARK: Local Media Resolution

    private func localMediaURL(
        for entry: PlaybackHistoryEntry
    ) -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "KinetiqMedia",
            isDirectory: true
        )
        .appendingPathComponent(
            entry.id,
            isDirectory: false
        )
    }

    // MARK: Source / Module Picker

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("ACTIVE SOURCE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("KINETIQ SOURCES", systemImage: "square.stack.3d.up")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(KinetiqPalette.accent)
            }

            Button {
                showingSourcePicker = true
            } label: {
                HStack(spacing: 12) {
                    KinetiqModuleIcon(source: moduleSourceStore.activeSource, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(moduleSourceStore.activeSourceTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(moduleSourceStore.activeSourceSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KinetiqPalette.accent)
                        .frame(width: 31, height: 31)
                        .background(KinetiqPalette.accent.opacity(0.10), in: Circle())
                }
                .padding(10)
                .background(
                    theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(KinetiqPalette.accent.opacity(theme == .anime ? 0.38 : 0.13),
                                      lineWidth: theme == .cinema ? 0.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose source. Current: \(moduleSourceStore.activeSourceTitle)")
            .accessibilityHint("Opens the Kinetiq module source picker with repository icons")
        }
        .padding(.horizontal, 21)
    }

    // MARK: Selected Module Placeholder

    private var selectedModulePlaceholder: some View {
        KinetiqAsyncStateView(
            kind: moduleSourceStore.isRefreshing ? .loading : .failure,
            title: moduleSourceStore.isRefreshing ? "Refreshing Sources" : "Source Unavailable",
            message: moduleSourceStore.isRefreshing
                ? "Checking the repository for your previously selected source."
                : "Your source selection is preserved. The repository could not provide this module; refresh to reconnect.",
            actionTitle: "Retry Repository Refresh"
        ) {
            Task { await moduleSourceStore.refreshAll() }
        }
        .padding(.top, 12)
    }

    // MARK: Video / Manga Switcher

    private var mediaModeSwitcher: some View {
        HStack(spacing: 5) {
            ForEach(HomeMediaMode.allCases) { mode in
                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeInOut(duration: 0.15)
                            : .spring(
                                response: 0.34,
                                dampingFraction: 0.78
                            )
                    ) {
                        selectedModeRawValue = mode.rawValue
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .semibold))

                        Text(mode.rawValue)
                            .font(
                                .system(
                                    size: 13,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                    }
                    .foregroundStyle(
                        selectedMode == mode
                            ? .white
                            : Color.primary.opacity(0.72)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selectedMode == mode {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .fill(KinetiqPalette.accent)
                        }
                    }
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedMode == mode ? .isSelected : []
                )
            }
        }
        .padding(5)
        .background(
            theme.cardBackground,
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .padding(.horizontal, 21)
    }

    // MARK: Video Home

    private var videoContent: some View {
        VStack(alignment: .leading, spacing: theme == .nocturne ? 20 : 27) {
            switch theme {
            case .signature:
                introduction.entrance(appeared, delay: 0.04)
                heroCard.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                librarySection.entrance(appeared, delay: 0.22)
            case .cinema:
                heroCard.entrance(appeared, delay: 0.04)
                introduction.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                librarySection.entrance(appeared, delay: 0.22)
            case .anime:
                introduction.entrance(appeared, delay: 0.04)
                animeSpotlight.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                heroCard.entrance(appeared, delay: 0.20)
                librarySection.entrance(appeared, delay: 0.24)
            case .aurora:
                introduction.entrance(appeared, delay: 0.04)
                heroCard.entrance(appeared, delay: 0.10)
                librarySection.entrance(appeared, delay: 0.16)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.22)
                }
            case .nocturne:
                introduction.entrance(appeared, delay: 0.04)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.10)
                }
                librarySection.entrance(appeared, delay: 0.16)
                heroCard.entrance(appeared, delay: 0.22)
            case .studio, .vault:
                introduction.entrance(appeared, delay: 0.04)
                librarySection.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                heroCard.entrance(appeared, delay: 0.22)
            case .prism, .nebula:
                heroCard.entrance(appeared, delay: 0.04)
                introduction.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                librarySection.entrance(appeared, delay: 0.22)
            case .signal:
                introduction.entrance(appeared, delay: 0.04)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.10)
                }
                heroCard.entrance(appeared, delay: 0.16)
                librarySection.entrance(appeared, delay: 0.22)
            case .ember:
                introduction.entrance(appeared, delay: 0.04)
                animeSpotlight.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                librarySection.entrance(appeared, delay: 0.22)
            case .atelier, .zen:
                introduction.entrance(appeared, delay: 0.04)
                librarySection.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                heroCard.entrance(appeared, delay: 0.22)
            }
        }
    }

    // MARK: - Remote Home · full content-first streaming experience

    private func remoteSourceHome(_ source: ModuleSourceOption) -> some View {
        KinetiqStreamingHome(
            source: source,
            onBrowse: { openSourceBrowser(source) },
            onSearch: { openSourceBrowser(source, search: true) }
        )
    }

    private var animeSpotlight: some View {
        Button(action: openSourceSearch) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 34))
                    .frame(width: 73, height: 82)
                    .background(.white.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text("ANIME PULSE")
                        .font(.caption2.weight(.black)).tracking(2)
                    Text("Find something to binge.")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)
                    Text("Discover stories across your sources")
                        .font(.caption).opacity(0.85)
                }
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(17)
            .background(
                LinearGradient(colors: [theme.stageColors[0], theme.stageColors[1]],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: theme.cardCornerRadius)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
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
                .shadow(
                    color: KinetiqPalette.blue.opacity(0.20),
                    radius: 12,
                    x: 0,
                    y: 5
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("KINETIQ")
                    .font(.system(size: theme == .cinema ? 18 : 15,
                                  weight: .black,
                                  design: theme == .cinema ? .serif : .rounded))
                    .tracking(2.2)

                Text("YOUR MEDIA UNIVERSE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: openSourceSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(
                        theme.cardBackground,
                        in: Circle()
                    )
            }
            .accessibilityLabel(moduleSourceStore.activeSource.map { "Search \($0.title)" } ?? "Open local media library")
        }
    }

    // MARK: Introduction

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(theme.eyebrow)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(KinetiqPalette.accent)

            Text(theme.homeHeadline)
                .font(.system(size: theme == .cinema ? 41 : theme == .nocturne ? 29 : 34,
                              weight: theme == .nocturne ? .medium : .bold,
                              design: theme == .cinema ? .serif : .rounded))
                .tracking(-1.25)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                tagline.isEmpty
                    ? "Movies, series and anime -- all moving together."
                    : tagline
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Hero Card

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.stageColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(KinetiqPalette.cyan.opacity(0.22))
                        .frame(width: 210, height: 210)
                        .offset(x: proxy.size.width * 0.43, y: -58)

                    Circle()
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                        .frame(width: 235, height: 235)
                        .offset(x: proxy.size.width * 0.38, y: -48)

                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 285, height: 285)
                        .offset(x: proxy.size.width * 0.38, y: -48)

                    Image(systemName: theme.heroSymbol)
                        .font(.system(size: 76, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.18))
                        .rotationEffect(.degrees(-13))
                        .offset(x: proxy.size.width * 0.30, y: -8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(KinetiqPalette.cyan)
                        .frame(width: 6, height: 6)

                    Text(theme == .cinema ? "NOW SHOWING" : theme == .anime ? "FEATURED EXPERIENCE" : "THE KINETIQ EXPERIENCE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Text(theme.heroHeadline)
                    .font(.system(size: theme == .cinema ? 31 : theme == .nocturne ? 26 : 27,
                                  weight: theme == .nocturne ? .medium : .bold,
                                  design: theme == .cinema ? .serif : .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(theme.heroDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                Button(action: openSourceSearch) {
                    HStack(spacing: 9) {
                        Text("Explore Kinetiq")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        Color(red: 0.10, green: 0.20, blue: 0.34)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                }
                .padding(.top, 2)
            }
            .padding(21)
        }
        .frame(height: theme.heroHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(
            color: KinetiqPalette.blue.opacity(0.20),
            radius: 22,
            x: 0,
            y: 12
        )
    }

    // MARK: Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "Continue watching",
                detail: "PICK UP WHERE YOU LEFT OFF"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueWatching) { entry in
                        Button {
                            onContinueWatching(entry)
                        } label: {
                            continueWatchingCard(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Continue \(entry.title), \(entry.progressPercent) percent watched"
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func continueWatchingCard(
        _ entry: PlaybackHistoryEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .bottomLeading) {
                ContinueWatchingThumbnailView(
                    mediaID: entry.id,
                    url: localMediaURL(for: entry)
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.04),
                        .black.opacity(0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    Label(
                        "\(entry.progressPercent)%",
                        systemImage: "play.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.38), in: Capsule())

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 25, height: 25)
                        .background(
                            .black.opacity(0.28),
                            in: Circle()
                        )
                }
                .padding(10)
            }
            .frame(width: 224, height: 112)
            .clipShape(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .strokeBorder(
                    Color.white.opacity(0.10),
                    lineWidth: 0.8
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack {
                    Text("\(entry.progressPercent)% watched")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    Text("\(entry.remainingTimeText) left")
                        .foregroundStyle(KinetiqPalette.accent)
                }
                .font(.system(size: 10, weight: .semibold))

                ProgressView(value: entry.progress)
                    .tint(KinetiqPalette.accent)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 224, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Library Entry

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                "Your library",
                detail: "YOUR PERSONAL COLLECTION"
            )

            Button(action: onOpenLibrary) {
                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(KinetiqPalette.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            KinetiqPalette.accent.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open your library")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.primary)

                        Text("Browse and play your imported videos")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(15)
                .background(
                    theme.cardBackground,
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.primary.opacity(0.045),
                        lineWidth: 0.7
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your local video library")
        }
    }

    // MARK: Manga Placeholder

    private var mangaPlaceholder: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A NEW WAY TO READ.")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.3)
                    .foregroundStyle(KinetiqPalette.accent)

                Text("Your manga universe.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Discover, organize and read manga from the sources you choose."
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            KinetiqPalette.violet.opacity(0.20),
                            KinetiqPalette.blue.opacity(0.12),
                            theme.cardBackground
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Circle()
                    .fill(KinetiqPalette.violet.opacity(0.12))
                    .frame(width: 190, height: 190)
                    .blur(radius: 3)
                    .offset(x: 105, y: -50)

                VStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 57, weight: .light))
                        .foregroundStyle(KinetiqPalette.violet)

                    Text("Manga is taking shape")
                        .font(
                            .system(
                                size: 18,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.primary)

                    Text(
                        "The manga library, source integration and reader will be built here."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 260)
                }
                .padding(25)
            }
            .frame(height: 260)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
            )
        }
        .padding(.top, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .entrance(appeared, delay: 0.05)
    }

    // MARK: Shared Section Heading

    private func sectionHeading(
        _ title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(-0.35)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Batch 06K.3 · Focused Source Catalogue
// Unlike the old embedded module browser, this screen owns a bounded vertical
// ScrollView and a single navigation bar. The keyboard never pushes a huge
// unscrollable VStack on top of the toolbar or the other controls.

@MainActor
private struct KinetiqFocusedSourceSheet: View {
    let source: ModuleSourceOption
    let startInSearch: Bool
    let initialQuery: String
    let onClose: () -> Void

    private enum Page: String, CaseIterable, Identifiable {
        case explore = "Explore"
        case search = "Search"
        var id: String { rawValue }
    }

    @StateObject private var packages = ModulePackageStore.shared
    @State private var runtime: SynthetiqModuleRuntime?
    @State private var page: Page
    @State private var searchText: String
    @State private var matches: [ModuleAnimeItem] = []
    @State private var selectedTitle: ModuleAnimeItem?
    @State private var loadingModule = true
    @State private var searching = false
    @State private var moduleError: String?
    @State private var searchError: String?
    @State private var diagnostics: String?
    @State private var searchRequest: UUID?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeID = KinetiqVisualTheme.signature.rawValue

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeID) ?? .signature
    }
    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(source: ModuleSourceOption, startInSearch: Bool,
         initialQuery: String, onClose: @escaping () -> Void) {
        self.source = source
        self.startInSearch = startInSearch
        self.initialQuery = initialQuery
        self.onClose = onClose
        _page = State(initialValue: startInSearch ? .search : .explore)
        _searchText = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    sourceTab(.explore, symbol: "rectangle.stack.fill")
                    sourceTab(.search, symbol: "magnifyingglass")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(theme.cardBackground)

                Divider().opacity(0.22)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 21) {
                        if loadingModule {
                            ProgressView("Preparing \(source.title)…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 45)
                        } else if let runtime {
                            if page == .explore {
                                exploreBody(runtime: runtime)
                            } else {
                                searchBody(runtime: runtime)
                            }
                        } else {
                            moduleFailure
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, 10, for: .scrollContent)
            }
            .background(KinetiqExperienceBackground())
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: source.id) { await prepareModule() }
        .onDisappear { searchRequest = nil }
        .sheet(item: $selectedTitle) { item in
            if let runtime {
                ModuleAnimeDetailsView(item: item, runtime: runtime,
                                       sourceID: source.id, sourceName: source.title)
            }
        }
    }

    private func sourceTab(_ choice: Page, symbol: String) -> some View {
        Button {
            searchFocused = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                page = choice
            }
        } label: {
            Label(choice.rawValue, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Color.primary)
                .background(page == choice ? theme.accent.opacity(0.20) : theme.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(page == choice ? theme.accent.opacity(0.75) : .clear,
                                      lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == choice ? .isSelected : [])
        .accessibilityHint("Show the source's \(choice.rawValue.lowercased()) screen")
    }

    private func exploreBody(runtime: SynthetiqModuleRuntime) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SOURCE CATALOGUE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.accent)
                Text("Explore titles")
                    .font(.system(size: theme.isEditorial ? 31 : 28,
                                  weight: .bold, design: theme.isEditorial ? .serif : .rounded))
                Text("Real collections provided by \(source.title). Tap a poster to see episodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A compact source-owned feed, without a second segmented control,
            // large redundant source header, or Favorites/Recent duplicates.
            KinetiqSourceDiscoveryView(
                runtime: runtime,
                sourceID: source.id,
                sourceName: source.title
            )
            Button {
                page = .search
            } label: {
                Label("Search \(source.title)", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func searchBody(runtime: SynthetiqModuleRuntime) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SEARCH THIS CATALOGUE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.accent)
                Text("Find something to watch")
                    .font(.system(size: theme.isEditorial ? 29 : 26,
                                  weight: .bold, design: theme.isEditorial ? .serif : .rounded))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search \(source.title)…", text: $searchText)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await performSearch() } }
                    .accessibilityLabel("Search \(source.title)")
                if !query.isEmpty {
                    Button {
                        searchFocused = false
                        Task { await performSearch() }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Submit search")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(minHeight: 52)
            .background(theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: 15))

            if searching {
                ProgressView("Searching \(source.title)…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else if let searchError {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Search didn't finish", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(searchError).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Button("Try again") { Task { await performSearch() } }
                        if let diagnostics {
                            Button("Copy diagnostics") {
                                UIPasteboard.general.string = diagnostics
                            }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            } else if matches.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Search titles" : "No matching titles",
                    systemImage: "magnifyingglass",
                    description: Text(query.isEmpty
                        ? "Enter an anime title to search this source's real catalogue."
                        : "Try a different title, spelling or language.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    Text("\(matches.count) RESULTS")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                        GridItem(.flexible(), spacing: 13)], spacing: 19) {
                        ForEach(matches) { item in
                            Button {
                                searchFocused = false
                                selectedTitle = item
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ModuleAnimeArtworkView(url: item.imageURL)
                                        .frame(height: 211)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(item.title)")
                        }
                    }
                }
            }
        }
    }

    private var moduleFailure: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Source unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(moduleError ?? "The module could not be prepared.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await prepareModule() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func prepareModule() async {
        loadingModule = true
        moduleError = nil
        runtime = nil
        defer { loadingModule = false }

        guard let record = packages.installedModule(for: source),
              FileManager.default.fileExists(atPath: record.entryScriptPath),
              FileManager.default.fileExists(atPath: record.manifestPath),
              ModuleRuntimeTrustStore.isTrusted(record) else {
            moduleError = "Install and trust this video module under Settings → Modules & Sources."
            return
        }
        do {
            let prepared = try SynthetiqModuleRuntime(record: record)
            guard !Task.isCancelled else { return }
            runtime = prepared
            if page == .search && !query.isEmpty { await performSearch() }
        } catch {
            moduleError = ModulePlaybackDiagnostics.redact(error.localizedDescription)
        }
    }

    private func performSearch() async {
        guard let runtime, !query.isEmpty else { return }
        let token = UUID()
        searchRequest = token
        let term = query
        matches = []
        searchError = nil
        diagnostics = nil
        searching = true
        defer { if searchRequest == token { searching = false } }
        do {
            let response = try await runtime.call(
                handler: "searchResults", arguments: [term]
            )
            guard !Task.isCancelled, searchRequest == token else { return }
            matches = ModuleRuntimeDecoder.searchResults(
                from: response, baseURL: runtime.baseURL,
                maximumResults: runtime.maximumHomeResults
            )
            if matches.isEmpty {
                diagnostics = "Search returned no matching titles for this source."
            }
        } catch {
            guard !Task.isCancelled, searchRequest == token else { return }
            searchError = ModulePlaybackDiagnostics.redact(error.localizedDescription)
            diagnostics = ModulePlaybackDiagnostics.simpleReport(
                source: source.title, phase: "searchResults", error: error
            )
        }
    }
}

// MARK: - Global Home Collection Routing
// A title saved from another source must never be passed to the currently
// selected module runtime. Load the original trusted source instead.

@MainActor
private struct KinetiqSavedTitleDestination: View {
    let entry: ModuleAnimeCollectionEntry
    @StateObject private var packages = ModulePackageStore.shared
    @StateObject private var sources = ModuleSourceStore.shared
    @State private var runtime: SynthetiqModuleRuntime?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let runtime {
                // Details owns its own NavigationStack and Done action.
                // Do not wrap it in another stack or create duplicate toolbars.
                ModuleAnimeDetailsView(item: entry.anime, runtime: runtime,
                                       sourceID: entry.sourceID, sourceName: entry.sourceName)
            } else {
                NavigationStack {
                    Group {
                        if let errorMessage {
                            ContentUnavailableView("Source unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(errorMessage))
                        } else {
                            ProgressView("Opening \(entry.sourceName)…")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(entry.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            }
        }
        .task(id: entry.id) { await loadSource() }
    }

    private func loadSource() async {
        guard let source = sources.availableSources.first(where: {
            $0.id == entry.sourceID
        }), let record = packages.installedModule(for: source),
           ModuleRuntimeTrustStore.isTrusted(record),
           FileManager.default.fileExists(atPath: record.entryScriptPath),
           FileManager.default.fileExists(atPath: record.manifestPath) else {
            errorMessage = "Reconnect or trust \(entry.sourceName) in Settings → Modules & Sources. Your saved title was not changed."
            return
        }
        do {
            let instance = try SynthetiqModuleRuntime(record: record)
            guard !Task.isCancelled else { return }
            runtime = instance
        } catch {
            errorMessage = ModulePlaybackDiagnostics.redact(error.localizedDescription)
        }
    }
}

// MARK: - Batch 06K.2 · Source-backed Streaming Home
// This is the actual Home surface, not the module browser or the Search sheet.
// Provider content always comes from discoveryHome/discoveryFeed; saved rows
// always come from the existing per-source collection. Nothing is fabricated.

@MainActor
private struct KinetiqStreamingHome: View {
    let source: ModuleSourceOption
    let onBrowse: () -> Void
    let onSearch: () -> Void

    private enum CatalogStatus {
        case idle, loading, loaded, unsupported, missingInstallation, failure
    }

    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeID = KinetiqVisualTheme.signature.rawValue
    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeID) ?? .signature
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @StateObject private var packages = ModulePackageStore.shared
    @StateObject private var sources = ModuleSourceStore.shared
    @StateObject private var repositoryTrust = KinetiqRepositoryTrustStore.shared

    @State private var runtime: SynthetiqModuleRuntime?
    @State private var shelves: [ModuleDiscoveryShelf] = []
    @State private var status: CatalogStatus = .idle
    @State private var failureSummary: String?
    @State private var currentRequest: UUID?
    @State private var chosenTitle: ModuleAnimeItem?
    @State private var chosenSavedTitle: ModuleAnimeCollectionEntry?
    @State private var chosenFeed: ModuleDiscoveryFeedSelection?

    private enum BrowseScope: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case shows = "Shows"
        case movies = "Movies"
        case newHot = "New & Hot"
        var id: String { rawValue }
    }
    @State private var browseScope: BrowseScope = .forYou
    @State private var categoryID: String?

    // The source decides what is popular or new. Never synthesize rankings.
    // A movie badge is set only when the source explicitly supplies isMovie.
    private var visibleShelves: [ModuleDiscoveryShelf] {
        let candidate = categoryID.map { id in shelves.filter { $0.id == id } } ?? shelves
        return candidate.compactMap { shelf in
            let items: [ModuleDiscoveryCard]
            switch browseScope {
            case .forYou: items = shelf.cards
            case .shows: items = shelf.cards.filter { $0.badge?.lowercased() != "movie" }
            case .movies: items = shelf.cards.filter { $0.badge?.lowercased() == "movie" }
            case .newHot:
                let title = shelf.title.lowercased()
                let knownLabels = ["new", "neu", "hot", "trending", "popular", "beliebt", "top", "aktuell", "derzeit"]
                items = knownLabels.contains(where: title.contains) ? shelf.cards : []
            }
            guard !items.isEmpty else { return nil }
            return ModuleDiscoveryShelf(id: shelf.id, title: shelf.title,
                                        style: shelf.style, feedID: shelf.feedID,
                                        cards: items)
        }
    }

    private var record: InstalledModuleRecord? {
        packages.installedModule(for: source)
    }

    private var authorizedSource: Bool {
        guard let record,
              ModuleRuntimeTrustStore.isTrusted(record),
              let repository = sources.repositories.first(where: {
                  $0.url.absoluteString == record.repositoryURL
              }) else { return false }
        return repositoryTrust.allowsRuntime(
            for: repository, installedModuleID: record.moduleID
        )
    }

    private var catalogIdentity: String {
        let suffix = record.map { "\($0.version)|\($0.packageSHA256)|\(authorizedSource)" }
            ?? "not-installed"
        return "\(source.id)|\(suffix)"
    }

    private var continues: [ModuleAnimeCollectionEntry] {
        collection.continueWatching.filter { !$0.isCompleted }
    }
    private var favorites: [ModuleAnimeCollectionEntry] {
        collection.favorites
    }
    private var recent: [ModuleAnimeCollectionEntry] {
        collection.entries.filter {
            $0.latestEpisodeDate != nil || $0.lastPlaybackDate != nil
        }.sorted {
            ($0.lastPlaybackDate ?? $0.latestEpisodeDate ?? .distantPast) >
                ($1.lastPlaybackDate ?? $1.latestEpisodeDate ?? .distantPast)
        }
    }

    // Home previews avoid surfacing the same title in three consecutive rails.
    // The complete history remains intact in the existing collection store.
    private var homeRecent: [ModuleAnimeCollectionEntry] {
        let alreadyVisible = Set((continues + favorites).map(\.id))
        return recent.filter { !alreadyVisible.contains($0.id) }
    }

    private var featured: ModuleAnimeItem? {
        let card = visibleShelves.lazy.compactMap { $0.cards.first?.anime }.first
        guard browseScope == .forYou, categoryID == nil else { return card }
        return card
            ?? continues.first(where: { $0.sourceID == source.id })?.anime
            ?? favorites.first(where: { $0.sourceID == source.id })?.anime
            ?? recent.first(where: { $0.sourceID == source.id })?.anime
    }

    private var compact: Bool { theme.prefersCompactThumbnails }
    private var editorial: Bool { theme.isEditorial }
    private var cardWidth: CGFloat { compact ? 109 : theme == .cinema ? 141 : 128 }
    private var cardHeight: CGFloat { compact ? 150 : theme == .cinema ? 197 : 176 }
    private var sectionSpacing: CGFloat { compact ? 19 : 27 }
    private var corner: CGFloat { theme == .nocturne ? 9 : theme.cardCornerRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            homeFilters
            personalizedHome
        }
        .task(id: catalogIdentity) {
            await loadCatalog()
        }
        .onDisappear { currentRequest = nil }
        .sheet(item: $chosenTitle) { item in
            if let runtime {
                ModuleAnimeDetailsView(item: item, runtime: runtime,
                                       sourceID: source.id, sourceName: source.title)
            } else {
                ContentUnavailableView("Source unavailable", systemImage: "wifi.exclamationmark",
                    description: Text("Open the module's catalogue to load its details."))
            }
        }
        .sheet(item: $chosenFeed) { selection in
            if let runtime {
                KinetiqStreamingFeedView(runtime: runtime, selection: selection,
                                         sourceID: source.id, sourceName: source.title,
                                         theme: theme)
            }
        }
        .sheet(item: $chosenSavedTitle) { entry in
            KinetiqSavedTitleDestination(entry: entry)
        }
    }

    /// Netflix-style inline filters control the actual Home catalogue.
    /// Categories come only from source-declared feed sections.
    private var homeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BrowseScope.allCases) { scope in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            browseScope = scope
                            categoryID = nil
                        }
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 43)
                            .background(browseScope == scope && categoryID == nil
                                ? theme.accent.opacity(0.24) : theme.cardBackground,
                                in: Capsule())
                            .overlay(Capsule().strokeBorder(
                                browseScope == scope && categoryID == nil
                                    ? theme.accent.opacity(0.8) : .white.opacity(0.08),
                                lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(browseScope == scope && categoryID == nil ? .isSelected : [])
                }
                Menu {
                    Button("All categories") {
                        categoryID = nil
                        browseScope = .forYou
                    }
                    ForEach(shelves) { shelf in
                        Button(shelf.title) {
                            browseScope = .forYou
                            categoryID = shelf.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(categoryID.flatMap { id in shelves.first(where: { $0.id == id })?.title }
                             ?? "Categories")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 43)
                    .background(categoryID == nil ? theme.cardBackground : theme.accent.opacity(0.24),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(categoryID == nil
                         ? .white.opacity(0.08) : theme.accent.opacity(0.8), lineWidth: 1))
                }
                .disabled(shelves.isEmpty)
                .accessibilityLabel("Browse source categories")
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Home catalogue filters")
    }

    @ViewBuilder
    private var personalizedHome: some View {
        // Filters never navigate away: the rail content changes in place.
        if browseScope != .forYou || categoryID != nil {
            if featured != nil { featuredHero }
            liveShelves
        } else if theme.prefersEpisodeOrganization {
            if !continues.isEmpty { savedShelf(continues, name: "Pick up where you left off", kind: "CONTINUE") }
            if !homeRecent.isEmpty { savedShelf(homeRecent, name: "Recently played", kind: "RECENT") }
            featuredHero
            liveShelves
            if !favorites.isEmpty { savedShelf(favorites, name: "Your watchlist", kind: "SAVED") }
        } else if theme == .anime || theme == .ember {
            featuredHero
            liveShelves
            if !continues.isEmpty { savedShelf(continues, name: "Keep watching", kind: "CONTINUE") }
            if !favorites.isEmpty { savedShelf(favorites, name: "My anime list", kind: "SAVED") }
            if !homeRecent.isEmpty { savedShelf(homeRecent, name: "Recently watched", kind: "RECENT") }
        } else if editorial {
            featuredHero
            if !favorites.isEmpty { savedShelf(favorites, name: "Your collection", kind: "SAVED") }
            liveShelves
            if !continues.isEmpty { savedShelf(continues, name: "Continue the story", kind: "CONTINUE") }
            if !homeRecent.isEmpty { savedShelf(homeRecent, name: "Recently viewed", kind: "RECENT") }
        } else {
            featuredHero
            if !continues.isEmpty { savedShelf(continues, name: "Continue watching", kind: "CONTINUE") }
            liveShelves
            if !favorites.isEmpty { savedShelf(favorites, name: "Saved for later", kind: "SAVED") }
            if !homeRecent.isEmpty { savedShelf(homeRecent, name: "Watch it again", kind: "RECENT") }
        }
    }

    private var featuredHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let featured {
                ModuleAnimeArtworkView(url: featured.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 255 : editorial ? 330 : 375)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.02), .black.opacity(0.30), .black.opacity(0.95)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            } else {
                LinearGradient(colors: theme.stageColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles.tv.fill")
                    Text("ON \(source.title.uppercased())")
                        .lineLimit(1)
                }
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.84))

                Text(featured?.title ?? source.title)
                    .font(.system(size: editorial ? 31 : compact ? 25 : 32,
                                  weight: editorial ? .medium : .bold,
                                  design: editorial ? .serif : .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(featured == nil
                     ? "Browse real titles from your selected module."
                     : "Explore episodes, languages and available servers.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button {
                        if let featured { openTitle(featured) }
                        else { onBrowse() }
                    } label: {
                        Label(featured == nil ? "Browse source" : "Episodes & details",
                              systemImage: "play.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .foregroundStyle(.black)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    if let featured {
                        Button {
                            collection.toggleFavorite(sourceID: source.id,
                                                      sourceName: source.title, anime: featured)
                        } label: {
                            Label(collection.isFavorite(sourceID: source.id, animeID: featured.id)
                                  ? "Saved" : "My List",
                                  systemImage: collection.isFavorite(sourceID: source.id, animeID: featured.id)
                                  ? "checkmark" : "plus")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.22),
                                            in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(19)
        }
        .frame(height: compact ? 255 : editorial ? 330 : 375)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var liveShelves: some View {
        if !visibleShelves.isEmpty {
            HStack(spacing: 6) {
                Text("EXPLORE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(theme.accent)
                Text("ON \(source.title.uppercased())")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            ForEach(visibleShelves) { shelf in
                liveShelf(shelf)
            }
            HStack(spacing: 9) {
                Button(action: onBrowse) {
                    Label("Full source browser", systemImage: "square.grid.2x2")
                }
                Spacer()
                Button {
                    Task { await loadCatalog() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .font(.caption.weight(.semibold))
            .tint(KinetiqPalette.accent)
            .buttonStyle(.plain)
        } else if !shelves.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ContentUnavailableView(
                    "No matching catalogue titles", systemImage: "rectangle.stack",
                    description: Text("This source hasn't identified titles for this filter. Try For You or choose another category.")
                )
                Button("Show all titles") {
                    browseScope = .forYou
                    categoryID = nil
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            catalogState
        }
    }

    @ViewBuilder
    private var catalogState: some View {
        switch status {
        case .idle, .loading:
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading real catalogue…").font(.subheadline.weight(.semibold))
                    Text(source.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(19)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: corner))
        case .loaded, .unsupported, .missingInstallation, .failure:
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: statusSymbol)
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle).font(.subheadline.weight(.semibold))
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if case .failure = status, let failureSummary, !failureSummary.isEmpty {
                    Text(failureSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Button("Copy Home diagnostics") {
                        UIPasteboard.general.string = [
                            "Kinetiq Home catalogue diagnostics",
                            "Source: " + ModulePlaybackDiagnostics.redact(source.title, limit: 80),
                            "Reason: " + failureSummary
                        ].joined(separator: "\n")
                    }
                    .font(.caption2.weight(.semibold))
                    .tint(theme.accent)
                }
                HStack(spacing: 15) {
                    Button("Open source", action: onBrowse)
                    if case .failure = status {
                        Button("Retry") { Task { await loadCatalog() } }
                    }
                    Spacer()
                    Button("Search", action: onSearch)
                }
                .font(.caption.weight(.semibold))
                .tint(theme.accent)
                .buttonStyle(.plain)
            }
            .padding(17)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: corner))
        }
    }

    private var statusSymbol: String {
        switch status {
        case .missingInstallation: "square.and.arrow.down"
        case .unsupported: "square.stack.3d.up"
        case .failure: "exclamationmark.triangle"
        case .idle, .loading, .loaded: "rectangle.stack"
        }
    }
    private var statusTitle: String {
        switch status {
        case .missingInstallation: "This source needs installation or trust"
        case .unsupported: "This module has no Home feed"
        case .failure: "The catalogue could not load"
        case .idle, .loading: "Loading catalogue"
        case .loaded: "No available Home titles"
        }
    }
    private var statusDescription: String {
        switch status {
        case .missingInstallation:
            "Your saved titles remain here. Open the source to install or approve it; Kinetiq never trusts modules automatically."
        case .unsupported:
            "This module does not publish discoveryHome shelves. Its regular Explore and Search remain available."
        case .failure:
            "The source could not supply a Home feed. Try again or open the regular source browser."
        case .idle, .loading: "Retrieving source titles"
        case .loaded: "The module returned no usable titles this time. Search and browsing are still available."
        }
    }

    private func liveShelf(_ shelf: ModuleDiscoveryShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(shelf.title)
                    .font(.system(size: editorial ? 21 : 19, weight: .bold,
                                  design: editorial ? .serif : .rounded))
                    .lineLimit(2)
                Spacer(minLength: 5)
                if let feedID = shelf.feedID {
                    Button("See all") {
                        chosenFeed = ModuleDiscoveryFeedSelection(id: feedID, title: shelf.title)
                    }
                    .font(.caption.weight(.semibold))
                    .tint(theme.accent)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: compact ? 9 : 12) {
                    ForEach(shelf.cards) { card in
                        poster(card.anime, badge: card.badge, progress: nil)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func savedShelf(_ entries: [ModuleAnimeCollectionEntry],
                            name: String, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(theme.accent)
                    Text(name)
                        .font(.system(size: editorial ? 21 : 19, weight: .bold,
                                      design: editorial ? .serif : .rounded))
                }
                Spacer(minLength: 5)
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: compact ? 9 : 12) {
                    ForEach(entries.prefix(24)) { entry in
                        poster(entry.anime, badge: nil,
                               progress: kind == "CONTINUE" ? entry.playbackFraction : nil,
                               savedEntry: entry)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func poster(_ anime: ModuleAnimeItem,
                        badge: String?, progress: Double?,
                        savedEntry: ModuleAnimeCollectionEntry? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let savedEntry, savedEntry.sourceID != source.id {
                    chosenSavedTitle = savedEntry
                } else {
                    openTitle(anime)
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    ModuleAnimeArtworkView(url: anime.imageURL)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 12))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(anime.title) details")
            if let progress, progress > 0 {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(theme.accent)
                    .frame(width: cardWidth)
            }
            if let savedEntry, savedEntry.sourceID != source.id {
                Text(savedEntry.sourceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 3) {
                Text(anime.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    collection.toggleFavorite(
                        sourceID: savedEntry?.sourceID ?? source.id,
                        sourceName: savedEntry?.sourceName ?? source.title,
                        anime: anime
                    )
                } label: {
                    Image(systemName: collection.isFavorite(
                        sourceID: savedEntry?.sourceID ?? source.id, animeID: anime.id)
                          ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collection.isFavorite(
                    sourceID: savedEntry?.sourceID ?? source.id, animeID: anime.id)
                    ? "Remove \(anime.title) from favorites" : "Save \(anime.title)")
            }
            .frame(width: cardWidth)
        }
        .frame(width: cardWidth)
    }

    private func openTitle(_ item: ModuleAnimeItem) {
        if runtime != nil { chosenTitle = item }
        else { onBrowse() }
    }

    private func loadCatalog() async {
        let token = UUID()
        currentRequest = token
        shelves = []
        runtime = nil
        status = .loading
        failureSummary = nil

        guard source.module.contentType?.lowercased() == "video" else {
            if currentRequest == token { status = .unsupported }
            return
        }
        guard let record,
              FileManager.default.fileExists(atPath: record.entryScriptPath),
              FileManager.default.fileExists(atPath: record.manifestPath),
              authorizedSource else {
            if currentRequest == token { status = .missingInstallation }
            return
        }
        do {
            let instance = try SynthetiqModuleRuntime(record: record)
            guard !Task.isCancelled, currentRequest == token else { return }
            runtime = instance
            let response = try await instance.call(handler: "discoveryHome", arguments: [])
            guard !Task.isCancelled, currentRequest == token else { return }
            shelves = ModuleDiscoveryDecoder.home(from: response, baseURL: instance.baseURL)
            status = .loaded
        } catch {
            guard !Task.isCancelled, currentRequest == token else { return }
            if case ModuleRuntimeError.missingHandler = error {
                status = .unsupported
            } else {
                status = .failure
                failureSummary = ModulePlaybackDiagnostics.redact(error.localizedDescription)
            }
        }
    }
}

// A source-advertised feed can be paginated without leaving the Home experience.
@MainActor
private struct KinetiqStreamingFeedView: View {
    @Environment(\.dismiss) private var dismiss
    let runtime: SynthetiqModuleRuntime
    let selection: ModuleDiscoveryFeedSelection
    let sourceID: String
    let sourceName: String
    let theme: KinetiqVisualTheme

    @State private var cards: [ModuleDiscoveryCard] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedTitle: ModuleAnimeItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(cards) { card in
                        Button { selectedTitle = card.anime } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ModuleAnimeArtworkView(url: card.anime.imageURL)
                                    .frame(height: 212)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(card.anime.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                if loading { ProgressView().padding(18) }
                if let errorText {
                    VStack(spacing: 9) {
                        Text("Could not load this page")
                        Text(errorText).font(.caption).foregroundStyle(.secondary)
                        Button("Retry") { Task { await next() } }
                    }
                    .padding(18)
                } else if hasMore && !loading {
                    Button("Load more") { Task { await next() } }
                        .buttonStyle(.borderedProminent)
                        .padding(18)
                } else if cards.isEmpty && !loading {
                    ContentUnavailableView("No titles in this feed", systemImage: "rectangle.stack")
                }
            }
            .background(KinetiqExperienceBackground())
            .navigationTitle(selection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await next() }
            .sheet(item: $selectedTitle) { item in
                ModuleAnimeDetailsView(item: item, runtime: runtime,
                                       sourceID: sourceID, sourceName: sourceName)
            }
        }
    }

    private func next() async {
        guard !loading && hasMore && nextPage <= 20 else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        let requestedPage = nextPage
        do {
            let response = try await runtime.call(
                handler: "discoveryFeed", arguments: [selection.id, requestedPage]
            )
            guard !Task.isCancelled else { return }
            let decoded = ModuleDiscoveryDecoder.feed(
                from: response, baseURL: runtime.baseURL, requestedPage: requestedPage
            )
            var seen = Set(cards.map(\.id))
            cards.append(contentsOf: decoded.cards.filter { seen.insert($0.id).inserted })
            nextPage = requestedPage + 1
            hasMore = decoded.hasMore && nextPage <= 20
        } catch {
            guard !Task.isCancelled else { return }
            errorText = ModulePlaybackDiagnostics.redact(error.localizedDescription)
        }
    }
}

// MARK: - Batch 06K.2 · Dedicated Search (distinct from content-first Home)

// MARK: - Unified Search
// Searching is explicit, source-scoped at the network boundary, and bounded
// to three concurrent trusted module runtimes. No fabricated titles or rankings.

private struct KinetiqUnifiedSearchHit: Identifiable {
    let source: ModuleSourceOption
    let item: ModuleAnimeItem
    var id: String { source.id + "|" + item.id }
}

@MainActor
struct DiscoverView: View {
    private enum SearchScope: String, CaseIterable, Identifiable {
        case all = "All sources"
        case files = "Your files"
        case online = "Online titles"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: "square.stack.3d.up"
            case .files: "iphone.gen3"
            case .online: "play.rectangle.on.rectangle"
            }
        }
    }

    @StateObject private var sources = ModuleSourceStore.shared
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @StateObject private var packages = ModulePackageStore.shared
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeID = KinetiqVisualTheme.signature.rawValue

    @State private var scope: SearchScope = .all
    @State private var searchText = ""
    @FocusState private var textFieldFocused: Bool
    @State private var submittedQuery = ""
    @State private var liveMatches: [KinetiqUnifiedSearchHit] = []
    @State private var searchToken: UUID?
    @State private var searchJobs: [Task<Void, Never>] = []
    @State private var completedSources = 0
    @State private var sourceCount = 0
    @State private var failures = 0
    @State private var selectedHit: KinetiqUnifiedSearchHit?
    @State private var selectedSavedTitle: ModuleAnimeCollectionEntry?
    @State private var selectedSource: ModuleSourceOption?
    @State private var showingLibrary = false
    @State private var requestedMediaID: String?
    @State private var localFiles: [URL] = []

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeID) ?? .signature
    }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { !query.isEmpty }
    private var searching: Bool { searchToken != nil && completedSources < sourceCount }

    private var videoSources: [ModuleSourceOption] {
        sources.availableSources
            .filter { $0.module.contentType?.lowercased() == "video" }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var authorizedSources: [ModuleSourceOption] {
        videoSources.filter { source in
            guard let record = packages.installedModule(for: source) else { return false }
            return FileManager.default.fileExists(atPath: record.entryScriptPath)
                && FileManager.default.fileExists(atPath: record.manifestPath)
                && ModuleRuntimeTrustStore.isTrusted(record)
        }
    }
    private var localMatches: [URL] {
        guard hasQuery else { return [] }
        return localFiles.filter { $0.deletingPathExtension().lastPathComponent
            .localizedCaseInsensitiveContains(query) }
    }
    private var savedMatches: [ModuleAnimeCollectionEntry] {
        guard hasQuery else { return [] }
        var seen = Set<String>()
        return (collection.favorites + collection.entries)
            .filter { $0.title.localizedCaseInsensitiveContains(query) ||
                      $0.sourceName.localizedCaseInsensitiveContains(query) }
            .filter { seen.insert($0.id).inserted }
            .prefix(10).map { $0 }
    }
    private var showFiles: Bool { scope == .all || scope == .files }
    private var showOnline: Bool { scope == .all || scope == .online }

    var body: some View {
        VStack(spacing: 0) {
            searchToolbar
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 23) {
                    if !hasQuery {
                        emptySearch
                    } else {
                        if showFiles { fileSection }
                        if showOnline {
                            savedSection
                            onlineSection
                        }
                    }
                    if showOnline { providerSelector }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(KinetiqExperienceBackground())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sources.loadSavedRepositoriesIfNeeded()
            loadLocalFiles()
        }
        .onChange(of: searchText) { _, _ in cancelSearch() }
        .onChange(of: scope) { _, _ in cancelSearch() }
        .onDisappear { stopWorkersPreservingResults() }
        .sheet(item: $selectedSource) { source in
            KinetiqFocusedSourceSheet(source: source, startInSearch: true,
                                     initialQuery: query, onClose: { selectedSource = nil })
        }
        .sheet(item: $selectedHit) { hit in
            KinetiqUnifiedSearchDestination(hit: hit)
        }
        .sheet(item: $selectedSavedTitle) { entry in
            KinetiqSavedTitleDestination(entry: entry)
        }
        .sheet(isPresented: $showingLibrary) {
            NavigationStack {
                LibraryView(requestedMediaID: $requestedMediaID)
                    .navigationTitle("Local Library")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingLibrary = false }
                        }
                    }
            }
        }
    }

    private var searchToolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search media and sources", text: $searchText)
                    .focused($textFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runOnlineSearch() }
                    .accessibilityLabel("Search media")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        textFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
                Button {
                    runOnlineSearch()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(theme.accent.opacity(0.24), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!hasQuery || !showOnline)
                .accessibilityLabel("Search connected modules")
            }
            .padding(.leading, 15)
            .padding(.trailing, 5)
            .frame(height: 54)
            .background(theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Menu {
                    ForEach(SearchScope.allCases) { option in
                        Button {
                            scope = option
                        } label: {
                            Label(option.rawValue, systemImage: option.symbol)
                        }
                    }
                } label: {
                    Label(scope.rawValue, systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(theme.cardBackground, in: Capsule())
                }
                .accessibilityLabel("Search options: \(scope.rawValue)")

                Spacer()
                if searching {
                    ProgressView()
                    Text("\(completedSources)/\(sourceCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var emptySearch: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Find your next story")
                .font(.system(size: theme.isEditorial ? 28 : 26, weight: .bold,
                              design: theme.isEditorial ? .serif : .rounded))
            Text("Search across trusted modules, your saved titles and videos on this device. Explore real poster collections directly on Home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("All sources", systemImage: "square.stack.3d.up")
                Spacer()
                Text("\(authorizedSources.count) ready")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(12)
            .background(theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        if !localMatches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Your files", detail: "ON THIS IPHONE")
                ForEach(localMatches.prefix(12), id: \.path) { url in
                    Button {
                        requestedMediaID = url.lastPathComponent
                        showingLibrary = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(theme.accent)
                                .frame(width: 44, height: 52)
                                .background(theme.accent.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 10))
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(theme.cardBackground,
                                    in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if scope == .files {
            ContentUnavailableView("No matching files", systemImage: "film",
                description: Text("No imported local videos matched your search."))
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        if !savedMatches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("From your watchlist & history", detail: "PERSONAL MEDIA")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(savedMatches) { entry in
                            Button { selectedSavedTitle = entry } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ModuleAnimeArtworkView(url: entry.anime.imageURL)
                                        .frame(width: 116, height: 158)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    Text(entry.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(entry.sourceName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 116, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionHeader("Online titles", detail: "LIVE MODULE SEARCH")
                Spacer(minLength: 3)
                if searching {
                    ProgressView()
                }
            }
            if !hasQuery { EmptyView() }
            else if submittedQuery != query {
                Button {
                    runOnlineSearch()
                } label: {
                    Label("Search across connected sources", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            } else if liveMatches.isEmpty && searching {
                ProgressView("Searching connected modules…")
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else if liveMatches.isEmpty {
                ContentUnavailableView(
                    authorizedSources.isEmpty ? "No trusted modules" : "No online results",
                    systemImage: "magnifyingglass",
                    description: Text(authorizedSources.isEmpty
                        ? "Install and approve a video module in Settings."
                        : "Try a different title or search a specific provider below.")
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 16) {
                    ForEach(liveMatches) { hit in
                        Button { selectedHit = hit } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ModuleAnimeArtworkView(url: hit.item.imageURL)
                                    .frame(height: 210)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(hit.item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(hit.source.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(hit.item.title) from \(hit.source.title)")
                    }
                }
            }
            if submittedQuery == query && sourceCount > 0 && !searching && failures > 0 {
                Text("\(failures) source(s) couldn't return results. Other results remain available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerSelector: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("Search a specific provider", detail: "CONNECTED SOURCES")
            if videoSources.isEmpty {
                ContentUnavailableView("No modules connected", systemImage: "square.stack.3d.up",
                    description: Text("Add providers in Settings → Modules & Sources."))
            } else {
                Menu {
                    ForEach(videoSources) { source in
                        Button(source.title) { selectedSource = source }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(theme.accent)
                        Text("Choose a module")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(.primary)
                    .padding(16)
                    .frame(minHeight: 52)
                    .background(theme.cardBackground,
                                in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
                }
                .accessibilityHint("Open the original module's search screen")
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.system(size: 20, weight: .bold,
                              design: theme.isEditorial ? .serif : .rounded))
        }
    }

    private func loadLocalFiles() {
        let folder = FileManager.default.urls(for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent("KinetiqMedia", isDirectory: true)
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        let formats: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
        localFiles = candidates.filter { formats.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func stopWorkersPreservingResults() {
        searchJobs.forEach { $0.cancel() }
        searchJobs = []
        searchToken = nil
        completedSources = sourceCount
    }

    private func cancelSearch() {
        searchJobs.forEach { $0.cancel() }
        searchJobs = []
        searchToken = nil
        submittedQuery = ""
        liveMatches = []
        completedSources = 0
        sourceCount = 0
        failures = 0
    }

    /// A maximum of three source workers can run concurrently. No module is
    /// automatically trusted, and each request uses the established runtime.
    private func runOnlineSearch() {
        cancelSearch()
        guard hasQuery else { return }
        textFieldFocused = false
        let term = query
        submittedQuery = term
        guard showOnline else { return }
        let all = authorizedSources
        let ordered = all.sorted { lhs, rhs in
            if lhs.id == sources.selectedSourceID { return true }
            if rhs.id == sources.selectedSourceID { return false }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        sourceCount = ordered.count
        guard !ordered.isEmpty else { return }

        let token = UUID()
        searchToken = token
        let workers = min(3, ordered.count)
        for worker in 0..<workers {
            let assigned = stride(from: worker, to: ordered.count, by: workers).map { ordered[$0] }
            let job = Task { @MainActor in
                for source in assigned {
                    guard !Task.isCancelled, searchToken == token else { return }
                    guard let record = packages.installedModule(for: source),
                          ModuleRuntimeTrustStore.isTrusted(record) else {
                        completedSources += 1
                        continue
                    }
                    do {
                        let runtime = try SynthetiqModuleRuntime(record: record)
                        let payload = try await runtime.call(handler: "searchResults", arguments: [term])
                        guard !Task.isCancelled, searchToken == token else { return }
                        let decoded = ModuleRuntimeDecoder.searchResults(
                            from: payload, baseURL: runtime.baseURL,
                            maximumResults: min(runtime.maximumHomeResults, 24))
                        var seen = Set(liveMatches.map(\.id))
                        for item in decoded.prefix(18) {
                            let hit = KinetiqUnifiedSearchHit(source: source, item: item)
                            if seen.insert(hit.id).inserted { liveMatches.append(hit) }
                        }
                    } catch {
                        guard !Task.isCancelled, searchToken == token else { return }
                        failures += 1
                    }
                    completedSources += 1
                }
            }
            searchJobs.append(job)
        }
    }
}

@MainActor
private struct KinetiqUnifiedSearchDestination: View {
    let hit: KinetiqUnifiedSearchHit
    @Environment(\.dismiss) private var dismiss
    @StateObject private var packages = ModulePackageStore.shared
    @State private var runtime: SynthetiqModuleRuntime?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let runtime {
                ModuleAnimeDetailsView(item: hit.item, runtime: runtime,
                    sourceID: hit.source.id, sourceName: hit.source.title)
            } else {
                NavigationStack {
                    Group {
                        if let errorText {
                            ContentUnavailableView("Title unavailable", systemImage: "exclamationmark.triangle",
                                description: Text(errorText))
                        } else {
                            ProgressView("Opening from \(hit.source.title)…")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(hit.item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            }
        }
        .task(id: hit.id) {
            guard let record = packages.installedModule(for: hit.source),
                  ModuleRuntimeTrustStore.isTrusted(record),
                  FileManager.default.fileExists(atPath: record.entryScriptPath),
                  FileManager.default.fileExists(atPath: record.manifestPath) else {
                errorText = "Install and approve the original source in Settings → Modules & Sources."
                return
            }
            do {
                let prepared = try SynthetiqModuleRuntime(record: record)
                guard !Task.isCancelled else { return }
                runtime = prepared
            } catch {
                errorText = ModulePlaybackDiagnostics.redact(error.localizedDescription)
            }
        }
    }
}

// MARK: - Entrance Animation

private extension View {
    func entrance(_ appeared: Bool, delay: Double) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 13)
            .animation(
                .spring(response: 0.62, dampingFraction: 0.88)
                    .delay(delay),
                value: appeared
            )
    }
}
// MARK: - Kinetiq Source Icon

/// Uses a repository-provided icon when its HTTPS URL points to a supported image.
/// SF Symbols remain visible for missing, untrusted or failed images.
struct KinetiqModuleIcon: View {
    let source: ModuleSourceOption?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(11, size * 0.27), style: .continuous)
                .fill(KinetiqPalette.accent.opacity(0.12))

            if let source, let iconURL = source.iconURL {
                AsyncImage(url: iconURL, transaction: Transaction(animation: .easeInOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(11, size * 0.27), style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: source?.symbol ?? "iphone")
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(KinetiqPalette.accent)
    }
}

// MARK: - Kinetiq Custom Source Picker

/// Custom SwiftUI picker replaces the system Menu, which cannot reliably show
/// third-party URL images in module rows. Source names remain provider-owned.
@MainActor
private struct KinetiqSourcePickerSheet: View {
    @ObservedObject var store: ModuleSourceStore
    let onManageModules: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleSources(in repository: ModuleRepositoryRecord) -> [ModuleSourceOption] {
        store.sources(in: repository).filter { source in
            normalizedSearch.isEmpty ||
            source.title.localizedCaseInsensitiveContains(normalizedSearch) ||
            source.subtitle.localizedCaseInsensitiveContains(normalizedSearch) ||
            source.module.moduleId.localizedCaseInsensitiveContains(normalizedSearch) ||
            repository.name.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }

    private var hasMatchingSources: Bool {
        store.repositories.contains { !visibleSources(in: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    introduction
                    searchField
                    manageModulesRow

                    if store.repositories.isEmpty && store.isRefreshing {
                        ProgressView("Refreshing connected repositories…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if !hasMatchingSources {
                        ContentUnavailableView(
                            normalizedSearch.isEmpty ? "No Module Sources" : "No Matching Modules",
                            systemImage: "square.stack.3d.up",
                            description: Text(normalizedSearch.isEmpty
                                ? "Add a module repository to get started."
                                : "Try searching for another module or repository.")
                        )
                        .frame(minHeight: 125)
                    }

                    ForEach(store.repositories) { repository in
                        let sources = visibleSources(in: repository)
                        if !sources.isEmpty {
                            repositorySection(repository, sources: sources)
                        } else if normalizedSearch.isEmpty, let error = repository.refreshError {
                            repositoryError(repository, error: error)
                        }
                    }

                    localLibrarySection
                }
                .padding(.horizontal, 19)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(KinetiqPalette.accent)
    }

    private var introduction: some View {
        HStack(spacing: 13) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(KinetiqPalette.accent)
                .frame(width: 52, height: 52)
                .background(KinetiqPalette.accent.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Your media, your sources")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(store.availableSources.count) modules across \(store.repositories.count) repositories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find a module or repository", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear source search")
            }
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 15))
    }

    private var manageModulesRow: some View {
        Button(action: onManageModules) {
            HStack(spacing: 13) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KinetiqPalette.accent)
                    .frame(width: 42, height: 42)
                    .background(KinetiqPalette.accent.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Manage Modules")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Install, trust and refresh sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(11)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func repositorySection(
        _ repository: ModuleRepositoryRecord,
        sources: [ModuleSourceOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(repository.name.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                Spacer()
                Text("\(sources.count) MODULES")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 3)

            VStack(spacing: 1) {
                ForEach(sources) { source in
                    sourceRow(source)
                    if source.id != sources.last?.id {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18))

            if let error = repository.refreshError {
                Text("Cached catalogue · \(error)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceRow(_ source: ModuleSourceOption) -> some View {
        let selected = store.isSelected(source.id)
        return Button {
            store.selectSource(source.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                KinetiqModuleIcon(source: source, size: 45)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(source.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(KinetiqPalette.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? KinetiqPalette.accent.opacity(0.065) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.title), \(source.subtitle)\(selected ? ", selected" : "")")
    }

    private func repositoryError(_ repository: ModuleRepositoryRecord, error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(repository.name).font(.headline)
            Text(error).font(.caption).foregroundStyle(.secondary)
            Button("Retry Refresh") { Task { await store.refreshAll() } }
                .disabled(store.isRefreshing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var localLibrarySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ON THIS IPHONE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)

            Button {
                store.selectLocalLibrary()
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    KinetiqModuleIcon(source: nil, size: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local Library")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Your imported files and personal media")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isLocalLibrarySelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(KinetiqPalette.accent)
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
    }
}