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
        VStack(spacing: 13) {
            sourcePicker
            mediaModeSwitcher

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 27) {
                    header

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
                .padding(.horizontal, 21)
                .padding(.top, theme == .nocturne ? 4 : 12)
                .padding(.bottom, 30)
            }
        }
        .padding(.top, 10)
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
            NavigationStack {
                ModuleBrowserView(source: source, startInSearch: browseSourceInSearch)
                    .navigationTitle(source.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedSourceToBrowse = nil }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .tint(KinetiqPalette.accent)
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

    // All search entry points open one real, source-aware Discover experience.
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

// MARK: - Batch 06K.2 · Source-backed Streaming Home
// This is the actual Home surface, not the module browser or the Search sheet.
// Provider content always comes from discoveryHome/discoveryFeed; saved rows
// always come from the existing per-source collection. Nothing is fabricated.

@MainActor
private struct KinetiqStreamingHome: View {
    let source: ModuleSourceOption
    let onBrowse: () -> Void
    let onSearch: () -> Void

    private enum HomeLane: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case explore = "Explore"
        case saved = "My List"
        case recent = "Recent"
        var id: String { rawValue }
    }

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

    @State private var activeLane: HomeLane = .forYou
    @State private var runtime: SynthetiqModuleRuntime?
    @State private var shelves: [ModuleDiscoveryShelf] = []
    @State private var status: CatalogStatus = .idle
    @State private var failureSummary: String?
    @State private var currentRequest: UUID?
    @State private var chosenTitle: ModuleAnimeItem?
    @State private var chosenFeed: ModuleDiscoveryFeedSelection?

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
        collection.continueWatching.filter {
            $0.sourceID == source.id && !$0.isCompleted
        }
    }
    private var favorites: [ModuleAnimeCollectionEntry] {
        collection.favorites(for: source.id)
    }
    private var recent: [ModuleAnimeCollectionEntry] {
        collection.entries.filter {
            $0.sourceID == source.id && ($0.latestEpisodeDate != nil || $0.lastPlaybackDate != nil)
        }.sorted {
            ($0.lastPlaybackDate ?? $0.latestEpisodeDate ?? .distantPast) >
                ($1.lastPlaybackDate ?? $1.latestEpisodeDate ?? .distantPast)
        }
    }

    private var featured: ModuleAnimeItem? {
        let card = shelves.lazy.compactMap { $0.cards.first?.anime }.first
        return card ?? continues.first?.anime ?? favorites.first?.anime ?? recent.first?.anime
    }

    private var compact: Bool { theme.prefersCompactThumbnails }
    private var editorial: Bool { theme.isEditorial }
    private var cardWidth: CGFloat { compact ? 109 : theme == .cinema ? 141 : 128 }
    private var cardHeight: CGFloat { compact ? 150 : theme == .cinema ? 197 : 176 }
    private var sectionSpacing: CGFloat { compact ? 19 : 27 }
    private var corner: CGFloat { theme == .nocturne ? 9 : theme.cardCornerRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            quickLanes
            switch activeLane {
            case .forYou:
                personalizedHome
            case .explore:
                liveCatalog
            case .saved:
                savedLibrary
            case .recent:
                recentLibrary
            }
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
    }

    private var quickLanes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeLane.allCases) { lane in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.19)) {
                            activeLane = lane
                        }
                    } label: {
                        Text(lane.rawValue)
                            .font(.system(size: 12, weight: .semibold,
                                          design: editorial ? .serif : .rounded))
                            .foregroundStyle(activeLane == lane ? theme.backdrop : Color.primary)
                            .padding(.horizontal, 15)
                            .frame(height: 36)
                            .background(activeLane == lane ? theme.accent : theme.cardBackground,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activeLane == lane ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Home categories")
    }

    @ViewBuilder
    private var personalizedHome: some View {
        // A theme changes hierarchy and density, not just the accent color.
        if theme.prefersEpisodeOrganization {
            if !continues.isEmpty { savedShelf(continues, name: "Pick up where you left off", kind: "CONTINUE") }
            if !recent.isEmpty { savedShelf(recent, name: "Recently played", kind: "RECENT") }
            featuredHero
            liveShelves
            if !favorites.isEmpty { savedShelf(favorites, name: "Your watchlist", kind: "SAVED") }
        } else if theme == .anime || theme == .ember {
            featuredHero
            liveShelves
            if !continues.isEmpty { savedShelf(continues, name: "Keep watching", kind: "CONTINUE") }
            if !favorites.isEmpty { savedShelf(favorites, name: "My anime list", kind: "SAVED") }
            if !recent.isEmpty { savedShelf(recent, name: "Recently watched", kind: "RECENT") }
        } else if editorial {
            featuredHero
            if !favorites.isEmpty { savedShelf(favorites, name: "Your collection", kind: "SAVED") }
            liveShelves
            if !continues.isEmpty { savedShelf(continues, name: "Continue the story", kind: "CONTINUE") }
            if !recent.isEmpty { savedShelf(recent, name: "Recently viewed", kind: "RECENT") }
        } else {
            featuredHero
            if !continues.isEmpty { savedShelf(continues, name: "Continue watching", kind: "CONTINUE") }
            liveShelves
            if !favorites.isEmpty { savedShelf(favorites, name: "Saved for later", kind: "SAVED") }
            if !recent.isEmpty { savedShelf(recent, name: "Watch it again", kind: "RECENT") }
        }
        otherSources
    }

    private var featuredHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let featured {
                ModuleAnimeArtworkView(url: featured.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 255 : editorial ? 330 : 375)
                    .clipped()
                    .blur(radius: 3)
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.42), .black.opacity(0.97)],
                                       startPoint: .top, endPoint: .bottom)
                    }
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
                            .frame(height: 42)
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
                                .frame(height: 42)
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

    private var liveCatalog: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FROM YOUR MODULE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(theme.accent)
                    Text("Explore \(source.title)")
                        .font(.system(size: editorial ? 27 : 25, weight: .bold,
                                      design: editorial ? .serif : .rounded))
                }
                Spacer(minLength: 4)
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(theme.cardBackground, in: Circle())
                }
                .accessibilityLabel("Search catalogue")
            }
            liveShelves
            otherSources
        }
    }

    @ViewBuilder
    private var liveShelves: some View {
        if !shelves.isEmpty {
            ForEach(shelves) { shelf in
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
                               progress: kind == "CONTINUE" ? entry.playbackFraction : nil)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func poster(_ anime: ModuleAnimeItem,
                        badge: String?, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                openTitle(anime)
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
            HStack(alignment: .top, spacing: 3) {
                Text(anime.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    collection.toggleFavorite(sourceID: source.id,
                                              sourceName: source.title, anime: anime)
                } label: {
                    Image(systemName: collection.isFavorite(sourceID: source.id, animeID: anime.id)
                          ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                        .frame(width: 25, height: 29)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collection.isFavorite(sourceID: source.id, animeID: anime.id)
                    ? "Remove \(anime.title) from favorites" : "Save \(anime.title)")
            }
            .frame(width: cardWidth)
        }
        .frame(width: cardWidth)
    }

    private var savedLibrary: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text("My List").font(.system(size: 30, weight: .bold, design: editorial ? .serif : .rounded))
            if !continues.isEmpty { savedShelf(continues, name: "In progress", kind: "CONTINUE") }
            if !favorites.isEmpty { savedShelf(favorites, name: "Saved titles", kind: "SAVED") }
            if favorites.isEmpty && continues.isEmpty {
                emptyLane("Your list is waiting", system: "heart",
                          message: "Save titles directly from real Home catalogue posters.")
            }
        }
    }

    private var recentLibrary: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text("Recently watched").font(.system(size: 30, weight: .bold,
                                                     design: editorial ? .serif : .rounded))
            if !recent.isEmpty { savedShelf(recent, name: "Your watch activity", kind: "RECENT") }
            else { emptyLane("Nothing watched yet", system: "clock.arrow.circlepath",
                             message: "Episodes you play from this source show up here.") }
        }
    }

    private func emptyLane(_ name: String, system: String, message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: system)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.accent)
            Text(name).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Explore titles") { activeLane = .explore }
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: corner))
    }

    private var otherSources: some View {
        let alternatives = sources.availableSources.filter {
            $0.id != source.id && $0.module.contentType?.lowercased() == "video"
        }
        return VStack(alignment: .leading, spacing: 11) {
            if !alternatives.isEmpty {
                HStack {
                    Text("Explore another source")
                        .font(.system(size: editorial ? 20 : 18, weight: .bold,
                                      design: editorial ? .serif : .rounded))
                    Spacer(minLength: 8)
                    Text("CONNECTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(alternatives.prefix(15)) { item in
                            Button {
                                sources.selectSource(item.id)
                            } label: {
                                VStack(spacing: 7) {
                                    KinetiqModuleIcon(source: item, size: 48)
                                    Text(item.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 91)
                                }
                                .padding(11)
                                .frame(width: 110)
                                .background(theme.cardBackground,
                                            in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Switch Home to this source")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
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

@MainActor
struct DiscoverView: View {
    @StateObject private var sources = ModuleSourceStore.shared
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeID = KinetiqVisualTheme.signature.rawValue
    @State private var searchText = ""
    @State private var selectedSource: ModuleSourceOption?
    @State private var showingLocalLibrary = false
    @State private var requestedMediaID: String?

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeID) ?? .signature
    }
    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var videoSources: [ModuleSourceOption] {
        sources.availableSources
            .filter { $0.module.contentType?.lowercased() == "video" }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var matchingSources: [ModuleSourceOption] {
        guard !query.isEmpty else { return videoSources }
        let matches = videoSources.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.repositoryName.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
        // Search terms can be anime titles, not just provider names.
        // Every connected provider is still an available live search destination.
        return matches.isEmpty ? videoSources : matches
    }
    private var matchesInHistory: [ModuleAnimeCollectionEntry] {
        guard !query.isEmpty else { return [] }
        var ids = Set<String>()
        return (collection.favorites + collection.entries.sorted {
            ($0.lastPlaybackDate ?? $0.latestEpisodeDate ?? .distantPast) >
                ($1.lastPlaybackDate ?? $1.latestEpisodeDate ?? .distantPast)
        })
        .filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.sourceName.localizedCaseInsensitiveContains(query)
        }
        .filter { ids.insert($0.id).inserted }
        .prefix(12)
        .map { $0 }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 23) {
                searchIntro

                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Search a source", systemImage: "magnifyingglass")
                            .font(.headline)
                        Text("Choose a connected provider to search its real catalogue. Your full Explore, My List and Recent shelves now live on Home.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(theme.cardBackground,
                                in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
                }

                if !matchesInHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Matches from your activity",
                                     caption: "YOUR SAVED TITLES AND WATCH HISTORY")
                        ForEach(matchesInHistory) { entry in
                            historyHit(entry)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(query.isEmpty ? "Connected catalogues" : "Search in a catalogue",
                                 caption: "LIVE PROVIDER SEARCH")
                    if !query.isEmpty {
                        Text("Open a provider below to search for “\(query)”. Each module searches its own live catalogue; Kinetiq does not merge or invent results.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if sources.isRefreshing && videoSources.isEmpty {
                        ProgressView("Loading connected sources…")
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else if videoSources.isEmpty {
                        ContentUnavailableView("No sources connected", systemImage: "square.stack.3d.up",
                            description: Text("Connect and install video modules in Settings → Modules & Sources."))
                    } else {
                        ForEach(matchingSources) { source in
                            sourceSearchRow(source)
                        }
                    }
                }

                Button {
                    showingLocalLibrary = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3")
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                            .frame(width: 42, height: 42)
                            .background(theme.accent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Local Library").font(.subheadline.weight(.semibold))
                            Text("Find videos stored on your device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(13)
                    .background(theme.cardBackground,
                                in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(KinetiqExperienceBackground())
        .searchable(text: $searchText, prompt: "Anime, films, sources…")
        .task { await sources.loadSavedRepositoriesIfNeeded() }
        .sheet(item: $selectedSource) { source in
            NavigationStack {
                ModuleBrowserView(source: source, startInSearch: true)
                    .navigationTitle(source.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedSource = nil }
                        }
                    }
            }
            .tint(KinetiqPalette.accent)
        }
        .sheet(isPresented: $showingLocalLibrary) {
            NavigationStack {
                LibraryView(requestedMediaID: $requestedMediaID)
                    .navigationTitle("Local Library")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingLocalLibrary = false }
                        }
                    }
            }
        }
    }

    private var searchIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KINETIQ FIND")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(theme.accent)
            Text(theme.isEditorial ? "Find a story." : "Search")
                .font(.system(size: theme.isEditorial ? 39 : 37, weight: .bold,
                              design: theme.isEditorial ? .serif : .rounded))
            Text("A focused search. Your personalized streaming catalogue is now on Home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ name: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(theme.accent)
            Text(name)
                .font(.system(size: theme.isEditorial ? 23 : 20,
                              weight: .bold,
                              design: theme.isEditorial ? .serif : .rounded))
        }
    }

    private func sourceSearchRow(_ source: ModuleSourceOption) -> some View {
        Button { selectedSource = source } label: {
            HStack(spacing: 12) {
                KinetiqModuleIcon(source: source, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(source.repositoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Label("Search", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .labelStyle(.titleAndIcon)
            }
            .padding(13)
            .background(theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search \(source.title) catalogue")
    }

    private func historyHit(_ entry: ModuleAnimeCollectionEntry) -> some View {
        let source = videoSources.first { $0.id == entry.sourceID }
        return Button {
            selectedSource = source
        } label: {
            HStack(spacing: 11) {
                ModuleAnimeArtworkView(url: entry.anime.imageURL)
                    .frame(width: 56, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(entry.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(source == nil ? Color.secondary : theme.accent)
            }
            .padding(10)
            .background(theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .accessibilityHint(source == nil
            ? "Original source is not connected" : "Search the original provider for this title")
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