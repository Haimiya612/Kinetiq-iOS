import SwiftUI
import UIKit
import Combine

// MARK: - Tab Navigation

private enum KinetiqTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case favorites = "Favorites"
    case downloads = "Downloads"
    case settings = "Settings"

    var id: String { rawValue }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .favorites: "heart.fill"
        case .downloads: "arrow.down.circle.fill"
        case .settings: "gearshape.fill"
        }
    }
}

private enum TabNavigationDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        self == .forward ? .trailing : .leading
    }

    var removalEdge: Edge {
        self == .forward ? .leading : .trailing
    }
}

// MARK: - Home Sheets

private enum HomeSheet: String, Identifiable {
    case discover
    case modules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .modules: "Module Sources"
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    let tagline: String

    @AppStorage("kinetiq.appearance.liquidGlassButtons")
    private var useLiquidGlassDock = false

    @AppStorage(AppStorageKey.accentColor)
    private var accentColorRawValue = AppAccentColor.kinetiq.rawValue

    @State private var selectedTab: KinetiqTab = .home
    @State private var navigationDirection: TabNavigationDirection = .forward

    @State private var requestedMediaID: String?
    @State private var showingLibrary = false
    @State private var activeSheet: HomeSheet?

    @State private var draggedTabPosition: CGFloat?
    @State private var dragStartPosition: CGFloat?

    @StateObject private var playbackHistory = PlaybackHistoryStore.shared
    @StateObject private var moduleSourceStore = ModuleSourceStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        mainLayout
    }

    // MARK: Main Layout

    private var mainLayout: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:
                    homeDestination

                case .favorites:
                    ModuleGlobalFavoritesView()

                case .downloads:
                    KinetiqPlaceholderView(
                        title: "Downloads",
                        subtitle: "Keep your media available offline with Kinetiq's download manager.",
                        symbol: "arrow.down.circle.fill",
                        accent: KinetiqPalette.accent
                    )

                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selectedTab)
            .transition(contentTransition)

            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .tint(
            AppAccentColor(rawValue: accentColorRawValue)?.accent
                ?? KinetiqPalette.accent
        )
        .sheet(item: $activeSheet) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .discover:
                        DiscoverView()

                    case .modules:
                        ModuleSourcesView()
                    }
                }
                .navigationTitle(destination.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            activeSheet = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Home Destination

    @ViewBuilder
    private var homeDestination: some View {
        if showingLibrary {
            LibraryView(
                requestedMediaID: $requestedMediaID
            )
            .overlay(alignment: .topLeading) {
                Button(action: closeLibrary) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.primary.opacity(0.08),
                                    lineWidth: 0.7
                                )
                        }
                }
                .accessibilityLabel("Back to Home")
                .padding(.leading, 17)
                .padding(.top, 6)
            }
        } else {
            HomeView(
                tagline: tagline,
                continueWatching: playbackHistory.continueWatching,
                onDiscover: {
                    activeSheet = .discover
                },
                onModules: {
                    activeSheet = .modules
                },
                onContinueWatching: openContinueWatching,
                onOpenLibrary: openLibrary
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Keep remote progress visible in local Home without
                // covering the module browser and its search controls.
                if moduleSourceStore.isLocalLibrarySelected {
                    ModuleRemoteContinueWatchingShelf()
                }
            }
        }
    }

    // MARK: Library Navigation

    private func openLibrary() {
        requestedMediaID = nil

        withAnimation(selectionAnimation) {
            showingLibrary = true
        }
    }

    private func openContinueWatching(
        _ entry: PlaybackHistoryEntry
    ) {
        requestedMediaID = entry.id

        withAnimation(selectionAnimation) {
            showingLibrary = true
        }
    }

    private func closeLibrary() {
        withAnimation(selectionAnimation) {
            showingLibrary = false
            requestedMediaID = nil
        }
    }

    // MARK: Content Transition

    private var contentTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        return .asymmetric(
            insertion: .move(edge: navigationDirection.insertionEdge)
                .combined(with: .opacity),
            removal: .move(edge: navigationDirection.removalEdge)
                .combined(with: .opacity)
        )
    }

    // MARK: Bottom Navigation

    private var bottomBar: some View {
        dockContent
            .background(
                .regularMaterial,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        Color.primary.opacity(0.08),
                        lineWidth: 0.7
                    )
            }
            .shadow(
                color: Color.black.opacity(0.07),
                radius: 14,
                x: 0,
                y: 5
            )
            .padding(.horizontal, 17)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    private var dockContent: some View {
        GeometryReader { geometry in
            let tabSpacing: CGFloat = 3
            let horizontalInset: CGFloat = 6

            let availableWidth = max(
                0,
                geometry.size.width - horizontalInset * 2
            )

            let tabCount = KinetiqTab.allCases.count
            let tabCountValue = CGFloat(tabCount)

            let tabWidth = max(
                0,
                (
                    availableWidth
                    - tabSpacing * CGFloat(tabCount - 1)
                ) / tabCountValue
            )

            let displayedPosition = draggedTabPosition
                ?? CGFloat(selectedTab.index)

            let displayedTabIndex = min(
                max(Int(displayedPosition.rounded()), 0),
                tabCount - 1
            )

            let indicatorOffset = displayedPosition
                * (tabWidth + tabSpacing)

            ZStack(alignment: .leading) {

                // MARK: Moving Liquid Glass Indicator

                selectedTabIndicator
                    .frame(
                        width: tabWidth,
                        height: 55
                    )
                    .offset(x: indicatorOffset)
                    .allowsHitTesting(false)

                // MARK: Tab Buttons

                HStack(spacing: tabSpacing) {
                    ForEach(KinetiqTab.allCases) { tab in
                        Button {
                            select(tab)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.symbol)
                                    .font(
                                        .system(
                                            size: 18,
                                            weight: .semibold
                                        )
                                    )
                                    .symbolEffect(
                                        .bounce,
                                        value: selectedTab == tab
                                    )

                                Text(tab.rawValue)
                                    .font(
                                        .system(
                                            size: 10,
                                            weight: .semibold
                                        )
                                    )
                            }
                            .foregroundStyle(
                                displayedTabIndex == tab.index
                                    ? KinetiqPalette.accent
                                    : Color.secondary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(tab.rawValue)
                        .accessibilityAddTraits(
                            selectedTab == tab ? .isSelected : []
                        )
                    }
                }
                .frame(
                    width: availableWidth,
                    height: 55
                )

                // MARK: Draggable Indicator Handle

                Capsule()
                    .fill(Color.clear)
                    .frame(
                        width: tabWidth,
                        height: 55
                    )
                    .contentShape(Capsule())
                    .offset(x: indicatorOffset)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.width)
                                        > abs(value.translation.height)
                                else {
                                    return
                                }

                                if dragStartPosition == nil {
                                    dragStartPosition = CGFloat(
                                        selectedTab.index
                                    )
                                }

                                let startingPosition =
                                    dragStartPosition
                                    ?? CGFloat(selectedTab.index)

                                let dragStep = max(
                                    tabWidth + tabSpacing,
                                    1
                                )

                                let proposedPosition =
                                    startingPosition
                                    + value.translation.width / dragStep

                                draggedTabPosition = min(
                                    max(proposedPosition, 0),
                                    CGFloat(tabCount - 1)
                                )
                            }
                            .onEnded { _ in
                                let finalPosition =
                                    draggedTabPosition
                                    ?? CGFloat(selectedTab.index)

                                finishIndicatorDrag(
                                    at: finalPosition,
                                    tabCount: tabCount
                                )
                            }
                    )
                    .zIndex(1)
                    .accessibilityHidden(true)
            }
            .frame(
                width: availableWidth,
                height: 55
            )
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 6)
        }
        .frame(height: 67)
    }

    // MARK: Indicator Appearance

    @ViewBuilder
    private var selectedTabIndicator: some View {
        if #available(iOS 26.0, *), useLiquidGlassDock {
            Capsule()
                .fill(.clear)
                .glassEffect(
                    .regular.interactive(),
                    in: Capsule()
                )
        } else {
            Capsule()
                .fill(
                    KinetiqPalette.accent.opacity(0.15)
                )
        }
    }

    // MARK: Indicator Drag Completion

    private func finishIndicatorDrag(
        at position: CGFloat,
        tabCount: Int
    ) {
        let targetIndex = min(
            max(Int(position.rounded()), 0),
            tabCount - 1
        )

        let targetTab = KinetiqTab.allCases[targetIndex]

        draggedTabPosition = nil
        dragStartPosition = nil

        select(targetTab)
    }

    // MARK: Selection

    private var selectionAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(
                response: 0.42,
                dampingFraction: 0.82
            )
    }

    private func select(_ tab: KinetiqTab) {
        withAnimation(selectionAnimation) {
            if tab == .home, selectedTab == .home {
                if showingLibrary {
                    showingLibrary = false
                    requestedMediaID = nil
                }

                return
            }

            if tab != .home {
                showingLibrary = false
                requestedMediaID = nil
            }

            updateSelection(tab)
        }
    }

    private func updateSelection(_ tab: KinetiqTab) {
        guard selectedTab != tab else {
            return
        }

        navigationDirection = tab.index > selectedTab.index
            ? .forward
            : .backward

        selectedTab = tab
    }
}

// MARK: - Placeholder Screens

private struct KinetiqPlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color

    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR MEDIA UNIVERSE")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .tracking(2)
                        .foregroundStyle(accent)

                    Text(title)
                        .font(
                            .system(
                                size: 37,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .tracking(-1.2)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                ZStack {
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.25),
                                accent.opacity(0.06),
                                Color(
                                    uiColor: .secondarySystemGroupedBackground
                                )
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 190, height: 190)
                        .blur(radius: 2)
                        .offset(x: 100, y: -55)

                    Image(systemName: symbol)
                        .font(.system(size: 65, weight: .light))
                        .foregroundStyle(accent)
                        .scaleEffect(appeared ? 1 : 0.85)
                }
                .frame(height: 220)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                )

                Text("A NEW CHAPTER IS TAKING SHAPE")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.65, dampingFraction: 0.86)
            ) {
                appeared = true
            }
        }
    }

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

            Text("KINETIQ")
                .font(
                    .system(
                        size: 15,
                        weight: .black,
                        design: .rounded
                    )
                )
                .tracking(2)

            Spacer()
        }
    }
}
// MARK: - Shared Remote Anime Collection (Batch 03B)
//
// This is intentionally outside ModuleRuntime.swift. The module runtime only
// resolves trusted content. MainTabView hosts the app-wide collection and UI.
// A dedicated project-registered storage file is planned for architecture
// cleanup; keeping these types here avoids unverified pbxproj identifiers.

struct ModuleAnimeCollectionEntry: Codable, Identifiable, Hashable {
    let sourceID: String
    let sourceName: String
    let animeID: String
    let title: String
    let href: String
    let artworkURL: String?
    var isFavorite: Bool
    var savedAt: Date
    var latestEpisodeID: String?
    var latestEpisodeNumber: String?
    var latestLanguage: String?
    var latestEpisodeDate: Date?

    // Optional for compatibility with Batch 03A's saved JSON. Values are
    // positions within an episode, never HTTP URLs, headers or tokens.
    var lastPlaybackPosition: Double?
    var lastPlaybackDuration: Double?
    var lastPlaybackDate: Date?

    var id: String {
        String(sourceID.utf8.count) + ":" + sourceID + animeID
    }

    var anime: ModuleAnimeItem {
        ModuleAnimeItem(
            id: animeID,
            title: title,
            href: href,
            imageURL: artworkURL.flatMap(URL.init(string:))
        )
    }

    var playbackFraction: Double {
        guard let position = lastPlaybackPosition,
              let duration = lastPlaybackDuration,
              position.isFinite, duration.isFinite,
              position >= 0, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var isCompleted: Bool {
        playbackFraction >= 0.97
    }

    var playbackLabel: String {
        let episode = latestEpisodeNumber.map { "Episode \($0)" } ?? "Episode"
        let language = (latestLanguage ?? "sub").uppercased()
        return "\(episode) · \(language)"
    }
}

/// Bounded, local-only, source-specific metadata persistence. The storage key
/// matches Batch 03A, so existing favorites and recent episode selections
/// survive migration without reset or source-name changes.
@MainActor
final class ModuleAnimeCollectionStore: ObservableObject {
    static let shared = ModuleAnimeCollectionStore()

    @Published private(set) var entries: [ModuleAnimeCollectionEntry] = []

    private let storageKey = "kinetiq.modules.animeCollection.v1"
    private let maximumEntries = 400

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let restored = try? JSONDecoder().decode(
                [ModuleAnimeCollectionEntry].self,
                from: data
              ) else { return }

        var seen = Set<String>()
        entries = Array(restored.filter { record in
            guard Self.isSafe(record), seen.insert(record.id).inserted else {
                return false
            }
            return record.isFavorite || record.latestEpisodeID != nil
        }.prefix(maximumEntries))
    }

    var favorites: [ModuleAnimeCollectionEntry] {
        entries.filter(\.isFavorite)
            .sorted { $0.savedAt > $1.savedAt }
    }

    var continueWatching: [ModuleAnimeCollectionEntry] {
        entries.filter {
            $0.latestEpisodeID != nil &&
            ($0.lastPlaybackPosition ?? 0) >= 3 &&
            ($0.lastPlaybackDuration ?? 0) > 5 &&
            $0.playbackFraction > 0
        }
        .sorted {
            ($0.lastPlaybackDate ?? .distantPast) >
                ($1.lastPlaybackDate ?? .distantPast)
        }
    }

    func favorites(for sourceID: String) -> [ModuleAnimeCollectionEntry] {
        favorites.filter { $0.sourceID == sourceID }
    }

    func recentEpisodes(for sourceID: String) -> [ModuleAnimeCollectionEntry] {
        entries.filter {
            $0.sourceID == sourceID && $0.latestEpisodeDate != nil
        }
        .sorted {
            ($0.latestEpisodeDate ?? .distantPast) >
                ($1.latestEpisodeDate ?? .distantPast)
        }
    }

    func isFavorite(sourceID: String, animeID: String) -> Bool {
        entries.first {
            $0.sourceID == sourceID && $0.animeID == animeID
        }?.isFavorite ?? false
    }

    func toggleFavorite(
        sourceID: String,
        sourceName: String,
        anime: ModuleAnimeItem
    ) {
        guard Self.isSafe(sourceID: sourceID, anime: anime) else { return }
        let key = Self.identity(sourceID: sourceID, animeID: anime.id)

        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].isFavorite.toggle()
            if entries[index].isFavorite { entries[index].savedAt = Date() }
            if !entries[index].isFavorite && entries[index].latestEpisodeID == nil {
                entries.remove(at: index)
            }
        } else {
            entries.insert(
                makeEntry(
                    sourceID: sourceID,
                    sourceName: sourceName,
                    anime: anime,
                    favorite: true
                ), at: 0
            )
        }
        persist()
    }

    func recordEpisode(
        sourceID: String,
        sourceName: String,
        anime: ModuleAnimeItem,
        episode: ModuleAnimeEpisode,
        language: String
    ) {
        guard Self.isSafe(sourceID: sourceID, anime: anime),
              !episode.id.isEmpty, episode.id.count <= 1500 else { return }

        let key = Self.identity(sourceID: sourceID, animeID: anime.id)
        if let index = entries.firstIndex(where: { $0.id == key }) {
            if entries[index].latestEpisodeID != episode.id ||
               entries[index].latestLanguage != language.lowercased() {
                entries[index].lastPlaybackPosition = nil
                entries[index].lastPlaybackDuration = nil
                entries[index].lastPlaybackDate = nil
            }
            entries[index].latestEpisodeID = episode.id
            entries[index].latestEpisodeNumber = String(episode.number.prefix(100))
            entries[index].latestLanguage = String(language.lowercased().prefix(10))
            entries[index].latestEpisodeDate = Date()
        } else {
            var newEntry = makeEntry(
                sourceID: sourceID,
                sourceName: sourceName,
                anime: anime,
                favorite: false
            )
            newEntry.latestEpisodeID = episode.id
            newEntry.latestEpisodeNumber = String(episode.number.prefix(100))
            newEntry.latestLanguage = String(language.lowercased().prefix(10))
            newEntry.latestEpisodeDate = Date()
            entries.insert(newEntry, at: 0)
        }
        persist()
    }

    func recordPlayback(
        sourceID: String,
        sourceName: String,
        anime: ModuleAnimeItem,
        episode: ModuleAnimeEpisode,
        language: String,
        position: Double,
        duration: Double
    ) {
        guard position.isFinite, duration.isFinite,
              duration > 5, duration <= 10_000_000,
              position >= 3, position <= duration + 15,
              Self.isSafe(sourceID: sourceID, anime: anime),
              !episode.id.isEmpty, episode.id.count <= 1500 else { return }

        let key = Self.identity(sourceID: sourceID, animeID: anime.id)
        if !entries.contains(where: { $0.id == key }) {
            recordEpisode(
                sourceID: sourceID,
                sourceName: sourceName,
                anime: anime,
                episode: episode,
                language: language
            )
        }

        guard let index = entries.firstIndex(where: { $0.id == key }) else {
            return
        }

        let newLanguage = String(language.lowercased().prefix(10))
        if entries[index].latestEpisodeID != episode.id ||
           entries[index].latestLanguage != newLanguage {
            entries[index].latestEpisodeID = episode.id
            entries[index].latestEpisodeNumber = String(episode.number.prefix(100))
            entries[index].latestLanguage = newLanguage
            entries[index].latestEpisodeDate = Date()
        }
        entries[index].lastPlaybackPosition = min(position, duration)
        entries[index].lastPlaybackDuration = duration
        entries[index].lastPlaybackDate = Date()
        persist()
    }

    func resumePosition(
        sourceID: String,
        animeID: String,
        episodeID: String,
        language: String
    ) -> Double {
        guard let entry = entries.first(where: {
            $0.sourceID == sourceID && $0.animeID == animeID
        }),
        entry.latestEpisodeID == episodeID,
        entry.latestLanguage == language.lowercased(),
        let position = entry.lastPlaybackPosition,
        let duration = entry.lastPlaybackDuration,
        position.isFinite, duration.isFinite,
        duration > 5, position >= 3, position < max(3, duration - 8) else {
            return 0
        }
        return position
    }

    func removeRecent(sourceID: String, animeID: String) {
        guard let index = entries.firstIndex(where: {
            $0.sourceID == sourceID && $0.animeID == animeID
        }) else { return }

        entries[index].latestEpisodeID = nil
        entries[index].latestEpisodeNumber = nil
        entries[index].latestLanguage = nil
        entries[index].latestEpisodeDate = nil
        entries[index].lastPlaybackPosition = nil
        entries[index].lastPlaybackDuration = nil
        entries[index].lastPlaybackDate = nil
        if !entries[index].isFavorite { entries.remove(at: index) }
        persist()
    }

    private static func identity(sourceID: String, animeID: String) -> String {
        String(sourceID.utf8.count) + ":" + sourceID + animeID
    }

    private static func isSafe(sourceID: String, anime: ModuleAnimeItem) -> Bool {
        !sourceID.isEmpty && sourceID.count <= 1200 &&
        !anime.id.isEmpty && anime.id.count <= 1500 &&
        !anime.title.isEmpty && anime.title.count <= 400 &&
        anime.href.count <= 2500
    }

    private static func isSafe(_ record: ModuleAnimeCollectionEntry) -> Bool {
        !record.sourceID.isEmpty && record.sourceID.count <= 1200 &&
        !record.animeID.isEmpty && record.animeID.count <= 1500 &&
        !record.title.isEmpty && record.title.count <= 400 &&
        record.href.count <= 2500 &&
        (record.lastPlaybackPosition.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (record.lastPlaybackDuration.map { $0.isFinite && $0 >= 0 } ?? true)
    }

    private func makeEntry(
        sourceID: String,
        sourceName: String,
        anime: ModuleAnimeItem,
        favorite: Bool
    ) -> ModuleAnimeCollectionEntry {
        let artwork: String?
        if let url = anime.imageURL,
           url.scheme?.lowercased() == "https",
           url.absoluteString.count <= 3000 {
            artwork = url.absoluteString
        } else {
            artwork = nil
        }

        return ModuleAnimeCollectionEntry(
            sourceID: sourceID,
            sourceName: String(sourceName.prefix(180)),
            animeID: anime.id,
            title: anime.title,
            href: anime.href,
            artworkURL: artwork,
            isFavorite: favorite,
            savedAt: Date(),
            latestEpisodeID: nil,
            latestEpisodeNumber: nil,
            latestLanguage: nil,
            latestEpisodeDate: nil,
            lastPlaybackPosition: nil,
            lastPlaybackDuration: nil,
            lastPlaybackDate: nil
        )
    }

    private func persist() {
        if entries.count > maximumEntries {
            let saved = entries.filter(\.isFavorite)
                .sorted { $0.savedAt > $1.savedAt }
            let recent = entries.filter { !$0.isFavorite }
                .sorted {
                    ($0.lastPlaybackDate ?? $0.latestEpisodeDate ?? .distantPast) >
                    ($1.lastPlaybackDate ?? $1.latestEpisodeDate ?? .distantPast)
                }
            entries = Array((saved + recent).prefix(maximumEntries))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Shared Artwork

private struct ModuleAnimeSavedArtwork: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            KinetiqPalette.cyan.opacity(0.22),
                            KinetiqPalette.violet.opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(KinetiqPalette.accent)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Global Favorites Tab

@MainActor
struct ModuleGlobalFavoritesView: View {
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @StateObject private var sourceStore = ModuleSourceStore.shared

    @State private var search = ""
    @State private var selectedEntry: ModuleAnimeCollectionEntry?

    private var filtered: [ModuleAnimeCollectionEntry] {
        let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return collection.favorites }
        return collection.favorites.filter {
            $0.title.localizedCaseInsensitiveContains(value) ||
            $0.sourceName.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("YOUR COLLECTION")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(KinetiqPalette.accent)

                        Text("Favorites")
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        Text("Anime you saved from your module sources")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !collection.favorites.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search favorites", text: $search)
                                .textInputAutocapitalization(.never)
                        }
                        .padding(13)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 15))
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView(
                            collection.favorites.isEmpty ? "No Favorites Yet" : "No Matches",
                            systemImage: "heart",
                            description: Text(
                                collection.favorites.isEmpty
                                    ? "Save anime with the heart button in a module's search results or details."
                                    : "Try another title or source."
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 45)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { entry in
                                HStack(spacing: 12) {
                                    Button {
                                        selectedEntry = entry
                                    } label: {
                                        HStack(spacing: 13) {
                                            ModuleAnimeSavedArtwork(
                                                urlString: entry.artworkURL,
                                                width: 82, height: 110
                                            )

                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(entry.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)

                                                Text(entry.sourceName)
                                                    .font(.caption)
                                                    .foregroundStyle(KinetiqPalette.accent)

                                                if entry.latestEpisodeID != nil {
                                                    Text(entry.playbackLabel)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                if entry.playbackFraction > 0 {
                                                    ProgressView(value: entry.playbackFraction)
                                                        .tint(KinetiqPalette.accent)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        collection.toggleFavorite(
                                            sourceID: entry.sourceID,
                                            sourceName: entry.sourceName,
                                            anime: entry.anime
                                        )
                                    } label: {
                                        Image(systemName: "heart.slash")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 35, height: 46)
                                    }
                                    .accessibilityLabel("Remove \(entry.title) from favorites")
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 19))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
        }
        .task { await sourceStore.loadSavedRepositoriesIfNeeded() }
        .sheet(item: $selectedEntry) { entry in
            ModuleSavedAnimeDetailsHost(entry: entry)
        }
    }
}

// MARK: - Remote Continue Watching on Home

@MainActor
struct ModuleRemoteContinueWatchingShelf: View {
    @StateObject private var collection = ModuleAnimeCollectionStore.shared
    @State private var selectedEntry: ModuleAnimeCollectionEntry?

    var body: some View {
        if !collection.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(KinetiqPalette.accent)
                    Text("CONTINUE WATCHING · MODULES")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                    Spacer()
                    Text("\(collection.continueWatching.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 11) {
                        ForEach(Array(collection.continueWatching.prefix(12))) { entry in
                            HStack(spacing: 8) {
                                Button {
                                    selectedEntry = entry
                                } label: {
                                    HStack(spacing: 9) {
                                        ModuleAnimeSavedArtwork(
                                            urlString: entry.artworkURL,
                                            width: 53, height: 69
                                        )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.title)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(2)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                            Text(entry.playbackLabel)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                            ProgressView(value: entry.playbackFraction)
                                                .tint(KinetiqPalette.accent)
                                        }
                                        .frame(width: 129, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    collection.removeRecent(
                                        sourceID: entry.sourceID,
                                        animeID: entry.animeID
                                    )
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Remove \(entry.title) from Continue Watching")
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 17)
                }
            }
            .padding(.vertical, 11)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
            }
            .sheet(item: $selectedEntry) { entry in
                ModuleSavedAnimeDetailsHost(entry: entry)
            }
        }
    }
}

// MARK: - Resolve Saved Anime Through Its Original Trusted Module

@MainActor
private struct ModuleSavedAnimeDetailsHost: View {
    let entry: ModuleAnimeCollectionEntry

    @StateObject private var sourceStore = ModuleSourceStore.shared
    @StateObject private var packageStore = ModulePackageStore.shared
    @State private var runtime: SynthetiqModuleRuntime?
    @State private var loadingError: String?

    var body: some View {
        Group {
            if let runtime {
                ModuleAnimeDetailsView(
                    item: entry.anime,
                    runtime: runtime,
                    sourceID: entry.sourceID,
                    sourceName: entry.sourceName
                )
            } else if let loadingError {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Source Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadingError)
                    } actions: {
                        NavigationLink {
                            ModuleSourcesView()
                        } label: {
                            Label("Manage Modules", systemImage: "square.stack.3d.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .navigationTitle(entry.title)
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                ProgressView("Loading \(entry.sourceName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: entry.id) {
            await prepareRuntime()
        }
    }

    private func prepareRuntime() async {
        runtime = nil
        loadingError = nil
        await sourceStore.loadSavedRepositoriesIfNeeded()

        guard let source = sourceStore.availableSources.first(where: {
            $0.id == entry.sourceID
        }), let installed = packageStore.installedModule(for: source),
              packageStore.isInstalled(source) else {
            loadingError = "The original source is no longer installed or available. Reinstall its module to open this anime."
            return
        }

        guard ModuleRuntimeTrustStore.isTrusted(installed) else {
            loadingError = "The installed module is not trusted. Review it in Manage Modules before reopening this title."
            return
        }

        do {
            runtime = try SynthetiqModuleRuntime(record: installed)
        } catch {
            loadingError = error.localizedDescription
        }
    }
}
