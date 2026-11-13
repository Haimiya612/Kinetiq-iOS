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
    @State private var showingSourceSearch = false
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
                            ModuleBrowserView(source: activeSource, embeddedInHome: true)
                                .id(activeSource.id) // Prevent state crossing between module identities.
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
        .sheet(isPresented: $showingSourceSearch) {
            if let source = moduleSourceStore.activeSource {
                NavigationStack {
                    ModuleBrowserView(source: source, startInSearch: true)
                        .navigationTitle("Search \(source.title)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingSourceSearch = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
                .tint(KinetiqPalette.accent)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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

    // Real source-aware search, never the empty Discover placeholder.
    private func openSourceSearch() {
        if selectedMode == .video, moduleSourceStore.activeSource != nil {
            showingSourceSearch = true
        } else if selectedMode == .video, moduleSourceStore.isLocalLibrarySelected {
            onOpenLibrary()
        } else {
            onDiscover()
        }
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
            case .studio, .prism, .atelier, .signal, .ember, .vault, .zen, .nebula:
                introduction.entrance(appeared, delay: 0.04)
                heroCard.entrance(appeared, delay: 0.10)
                if !continueWatching.isEmpty {
                    continueWatchingSection.entrance(appeared, delay: 0.16)
                }
                librarySection.entrance(appeared, delay: 0.22)
            }
        }
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

// MARK: - Discover Screen

struct DiscoverView: View {
    private let categories = [
        "All", "Movies", "Series", "Anime", "Manga"
    ]

    @State private var selectedCategory = "All"
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                header
                    .entrance(appeared, delay: 0.02)

                introduction
                    .entrance(appeared, delay: 0.08)

                categorySection
                    .entrance(appeared, delay: 0.14)

                discoveryPlaceholder
                    .entrance(appeared, delay: 0.20)
            }
            .padding(.horizontal, 21)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.72, dampingFraction: 0.88)
            ) {
                appeared = true
            }
        }
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

            VStack(alignment: .leading, spacing: 1) {
                Text("KINETIQ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(2.2)

                Text("SEARCH & DISCOVER")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: Introduction

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("FIND YOUR NEXT FAVOURITE.")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(KinetiqPalette.accent)

            Text("A universe to explore.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.25)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Movies, series, anime and manga. Choose what you feel like exploring."
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Explore your way")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(-0.35)

                Spacer(minLength: 8)

                Text("THE WHOLE UNIVERSE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation(
                                .spring(
                                    response: 0.32,
                                    dampingFraction: 0.78
                                )
                            ) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    selectedCategory == category
                                        ? .white
                                        : Color.primary.opacity(0.78)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    selectedCategory == category
                                        ? KinetiqPalette.accent
                                        : Color(
                                            uiColor: .secondarySystemGroupedBackground
                                        ),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedCategory == category ? .isSelected : []
                        )
                    }
                }
            }
        }
    }

    // MARK: Discovery Placeholder

    private var discoveryPlaceholder: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(KinetiqPalette.accent)
                .frame(width: 58, height: 58)
                .background(
                    KinetiqPalette.accent.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    selectedCategory == "All"
                        ? "Your next story starts here."
                        : "Explore \(selectedCategory.lowercased())."
                )
                .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(
                    "Your catalogue will appear here as Kinetiq connects to content sources."
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.045),
                    lineWidth: 0.7
                )
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