import SwiftUI
import Foundation

// MARK: - Kinetiq Compass

/// A transparent, local-first query planner. This is not a generative model:
/// unrecognised phrases remain ordinary catalog searches, and no file names,
/// watch history or module credentials are sent to AniList.
struct KinetiqDiscoveryIntent: Equatable {
    let original: String
    let catalogSearch: String?
    let genre: String?
    let finishedOnly: Bool
    let maximumEpisodes: Int?
    let asksForLocal: Bool

    static func interpret(_ input: String) -> KinetiqDiscoveryIntent {
        let original = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let normalized = original.lowercased()
        let genres = ["romance": "Romance", "comedy": "Comedy", "drama": "Drama",
                      "action": "Action", "fantasy": "Fantasy", "mystery": "Mystery",
                      "slice of life": "Slice of Life", "sports": "Sports", "sci-fi": "Sci-Fi"]
        let genre = genres.keys.sorted { $0.count > $1.count }.first {
            normalized.range(of: $0) != nil
        }.flatMap { genres[$0] }
        let finished = ["finished", "completed", "complete", "ended"].contains {
            normalized.contains($0)
        }
        let local = ["my files", "my storage", "local", "on my iphone", "haven't watched",
                     "not watched", "unwatched", "downloaded"].contains {
            normalized.contains($0)
        }
        let numberPattern = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*(?:episodes?|eps?)\b"#)
        let number = numberPattern?.firstMatch(in: normalized,
            range: NSRange(normalized.startIndex..., in: normalized))
            .flatMap { Range($0.range(at: 1), in: normalized) }
            .flatMap { Int(normalized[$0]) }
        let maximumEpisodes = number.flatMap { (1...150).contains($0) ? $0 : nil }
        var residual = normalized
        let removable = ["find", "me", "show", "anime", "series", "shows", "with", "that",
                         "have", "has", "some", "under", "at", "most", "short", "only", "my",
                         "on", "iphone", "storage", "local", "files", "unwatched", "not",
                         "watched", "haven't", "finished", "completed", "complete", "ended",
                         "episodes", "episode", "eps", "downloaded", "what", "which", "i",
                         "in", "the", "yet"]
        for word in removable {
            residual = residual.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b",
                with: " ", options: .regularExpression)
        }
        if let genre {
            residual = residual.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: genre.lowercased()),
                with: " ", options: .regularExpression)
        }
        residual = residual.replacingOccurrences(of: #"\b\d{1,3}\b"#, with: " ", options: .regularExpression)
        residual = residual.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Preserve the words in ordinary title searches ("Attack on Titan"
        // must not lose "on"). Only strip an explicit *leading* search verb.
        // The old fallback kept "Find Roshidere" verbatim, causing a live
        // Compass regression while the filter path correctly cleaned phrases.
        let directSearch = normalized.replacingOccurrences(
            of: #"^(?:please\s+)?(?:find(?:\s+me)?|search(?:\s+for)?|show\s+me|look\s+up)\s+"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = genre == nil && !finished && maximumEpisodes == nil && !local
            ? directSearch : residual
        return KinetiqDiscoveryIntent(original: original,
            catalogSearch: fallback.isEmpty ? nil : fallback,
            genre: genre, finishedOnly: finished,
            maximumEpisodes: maximumEpisodes, asksForLocal: local)
    }
}

struct KinetiqCatalogSuggestion: Identifiable, Decodable {
    let id: Int
    let title: Title
    let coverImage: Cover?
    let episodes: Int?
    let status: String?
    let genres: [String]?

    struct Title: Decodable {
        let english: String?
        let romaji: String?
        let userPreferred: String?
    }
    struct Cover: Decodable { let large: String? }

    var displayTitle: String {
        title.english ?? title.userPreferred ?? title.romaji ?? "Unknown title"
    }
    var coverURL: URL? {
        guard let raw = coverImage?.large, let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
    var anilistURL: URL? { URL(string: "https://anilist.co/anime/\(id)") }
}

actor KinetiqPublicAnimeSearch {
    static let shared = KinetiqPublicAnimeSearch()
    struct PageResult {
        let titles: [KinetiqCatalogSuggestion]
        let hasMore: Bool
    }
    private var nextAvailable = Date.distantPast
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        return URLSession(configuration: configuration)
    }()

    private struct Envelope: Decodable {
        let data: Payload?
        struct Payload: Decodable {
            let page: Page?
            enum CodingKeys: String, CodingKey { case page = "Page" }
        }
        struct Page: Decodable {
            let pageInfo: PageInfo?
            let media: [KinetiqCatalogSuggestion]?
        }
        struct PageInfo: Decodable { let hasNextPage: Bool }
    }

    func search(_ intent: KinetiqDiscoveryIntent, page: Int = 1) async throws -> PageResult {
        guard !intent.original.isEmpty, intent.original.count <= 160,
              let endpoint = URL(string: "https://graphql.anilist.co"),
              (1...40).contains(page) else { return PageResult(titles: [], hasMore: false) }
        // Reserve one slot per actor call so multiple open sheets do not burst.
        let now = Date()
        let reserved = max(now, nextAvailable)
        nextAvailable = reserved.addingTimeInterval(2.1)
        let delay = reserved.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        let query = """
        query ($page: Int!, $search: String, $genre: String, $status: MediaStatus, $maxEpisodes: Int) {
          Page(page: $page, perPage: 50) {
            pageInfo { hasNextPage }
            media(search: $search, genre: $genre, status: $status,
                  episodes_lesser: $maxEpisodes, type: ANIME, sort: [POPULARITY_DESC]) {
              id title { english romaji userPreferred }
              coverImage { large } episodes status genres
            }
          }
        }
        """
        var variables: [String: Any] = ["page": page]
        if let term = intent.catalogSearch { variables["search"] = term }
        if let genre = intent.genre { variables["genre"] = genre }
        if intent.finishedOnly { variables["status"] = "FINISHED" }
        if let episodes = intent.maximumEpisodes { variables["maxEpisodes"] = episodes + 1 }
        let payload: [String: Any] = ["query": query, "variables": variables]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let code = (response as? HTTPURLResponse)?.statusCode, code == 200,
              data.count <= 600_000 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Envelope.self, from: data).data?.page
        return PageResult(titles: decoded?.media ?? [],
            hasMore: decoded?.pageInfo?.hasNextPage == true && page < 40)
    }
}

struct KinetiqImportedVideo: Identifiable {
    let url: URL
    let bytes: Int64
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

enum KinetiqPrivateLibraryScanner {
    static func importedVideos() -> [KinetiqImportedVideo] {
        let folder = FileManager.default.urls(for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent("KinetiqMedia", isDirectory: true)
        let extensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg"]
        // This is strictly the application's imported folder. Never traverse
        // Photos, iCloud Drive, arbitrary user folders or other apps' data.
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        return files.filter {
            extensions.contains($0.pathExtension.lowercased()) &&
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.prefix(2_000).map { file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return KinetiqImportedVideo(url: file, bytes: Int64(max(0, size)))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

@MainActor
struct KinetiqSmartDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var history = PlaybackHistoryStore.shared
    @StateObject private var favorites = ModuleAnimeCollectionStore.shared
    @State private var question = ""
    @FocusState private var queryFieldFocused: Bool
    @State private var intent: KinetiqDiscoveryIntent?
    @State private var suggestions: [KinetiqCatalogSuggestion] = []
    @State private var imported: [KinetiqImportedVideo] = []
    @State private var searching = false
    @State private var currentPage = 0
    @State private var morePublicPages = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var requestedMediaID: String?
    @State private var showingLibrary = false
    @State private var showOnlyUnplayed = false
    @State private var showingSavedBacklog = false

    private var possibleUnplayed: [KinetiqImportedVideo] {
        imported.filter { item in
            history.entry(for: item.id) == nil && !history.hasCompleted(mediaID: item.id)
        }
    }
    private var shownImported: [KinetiqImportedVideo] {
        showOnlyUnplayed ? possibleUnplayed : imported
    }
    private var untouchedFavorites: [ModuleAnimeCollectionEntry] {
        favorites.favorites.filter { record in
            record.lastPlaybackDate == nil && record.latestEpisodeID == nil &&
            (record.episodeProgress ?? []).isEmpty
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 21) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("KINETIQ COMPASS", systemImage: "sparkles")
                            .font(.caption.weight(.heavy)).foregroundStyle(KinetiqPalette.accent)
                        Text("Ask what to watch next")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("Search public anime metadata, continue in any trusted module, or check the imported videos you haven't started. Your library stays on this iPhone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    searchBox
                    if intent != nil { results }
                    savedBacklog
                    localInventory
                }
                .padding(19)
            }
            .background(KinetiqExperienceBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Compass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { refreshLocalFiles() }
        .onDisappear { searchTask?.cancel() }
        .sheet(isPresented: $showingLibrary) {
            NavigationStack {
                LibraryView(requestedMediaID: $requestedMediaID)
            }
        }
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(KinetiqPalette.accent)
                TextField("Try 'completed romance under 12 episodes'", text: $question,
                          axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($queryFieldFocused)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
            }
            .padding(13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
            Button(action: runSearch) {
                HStack {
                    Label("Search", systemImage: "magnifyingglass")
                    Spacer()
                    if searching { ProgressView() }
                    else { Image(systemName: "arrow.right") }
                }
                .font(.headline).padding(12)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinetiqPalette.accent)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    example("Completed romance under 12 episodes")
                    example("Find Roshidere")
                    example("What haven't I watched in my storage?")
                }
            }
            Text("Smart query rules, not a generative AI model. Public catalog requests go to AniList; private file names and history are never sent with them.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func example(_ value: String) -> some View {
        Button(value) { question = value; runSearch() }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).frame(minHeight: 42)
            .background(.thinMaterial, in: Capsule())
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var results: some View {
        if let intent {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your search").font(.title3.bold())
                HStack(spacing: 7) {
                    if let genre = intent.genre { tag(genre) }
                    if intent.finishedOnly { tag("Completed") }
                    if let count = intent.maximumEpisodes { tag("Up to \(count) episodes") }
                    if intent.asksForLocal { tag("Private library") }
                }
                if let title = intent.catalogSearch, !title.isEmpty {
                    NavigationLink {
                        DiscoverView(initialQuery: title,
                                     searchesAllSourcesOnOpen: true)
                    } label: {
                        Label("Find every result from my modules", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else if !intent.asksForLocal {
                    Text("The public catalog supports genre and length filters. Pick an anime below to search all modules by its actual title.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if suggestions.isEmpty && !searching && errorMessage == nil {
                    Text(intent.asksForLocal ? "Your private inventory appears below." : "No public catalog matches returned. Try a title or different filters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(suggestions) { item in
                    HStack(spacing: 12) {
                        ModuleAnimeArtworkView(url: item.coverURL)
                            .frame(width: 65, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.displayTitle).font(.subheadline.weight(.semibold))
                            Text("\(item.episodes.map { String($0) } ?? "?") eps · \(item.status == "FINISHED" ? "Completed" : "Catalogued")")
                                .font(.caption2).foregroundStyle(.secondary)
                            if favorites.entries.contains(where: {
                                KinetiqEpisodeMetadataMatching.normalized($0.title) ==
                                KinetiqEpisodeMetadataMatching.normalized(item.displayTitle)
                            }) {
                                Text("Similar saved title · confirmation needed")
                                    .font(.caption2).foregroundStyle(KinetiqPalette.accent)
                            }
                            NavigationLink("Search modules") {
                                DiscoverView(initialQuery: item.displayTitle,
                                             searchesAllSourcesOnOpen: true)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if morePublicPages {
                    Button {
                        fetchPage(intent, page: currentPage + 1, replacing: false)
                    } label: {
                        HStack {
                            Label("Load more public anime", systemImage: "arrow.down.circle")
                            Spacer()
                            if searching { ProgressView() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(searching)
                }
            }
        }
    }

    private func tag(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(KinetiqPalette.accent.opacity(0.15), in: Capsule())
    }

    private var savedBacklog: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showingSavedBacklog) {
                if untouchedFavorites.isEmpty {
                    Text("All saved favorites have some recorded playback, or your list is empty.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(untouchedFavorites) { record in
                        NavigationLink {
                            DiscoverView(initialQuery: record.title,
                                searchesAllSourcesOnOpen: true)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title).font(.subheadline.weight(.medium))
                                    Text("Saved on \(record.sourceName) · no recorded start")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "magnifyingglass").foregroundStyle(KinetiqPalette.accent)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved for later · \(untouchedFavorites.count)")
                        .font(.title3.bold())
                    Text("Favorites with no recorded playback, searchable across every module")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var localInventory: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("My imported library").font(.title3.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refreshLocalFiles() }
                    .font(.caption)
            }
            Text("\(imported.count) videos · \(possibleUnplayed.count) without saved progress or a watched mark")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Only show possible unwatched videos", isOn: $showOnlyUnplayed)
            if shownImported.isEmpty {
                ContentUnavailableView("No matching imported videos", systemImage: "film",
                    description: Text("Import media in Local Library, or switch off the unwatched filter."))
            } else {
                ForEach(shownImported) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .foregroundStyle(KinetiqPalette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(history.hasCompleted(mediaID: item.id) ? "Marked watched" :
                                 history.entry(for: item.id) != nil ? "In progress" : "No recorded progress")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Open") {
                            requestedMediaID = item.id
                            showingLibrary = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            if history.hasCompleted(mediaID: item.id) {
                                history.unmarkWatched(mediaID: item.id)
                            } else {
                                history.markWatched(mediaID: item.id)
                            }
                        } label: {
                            Image(systemName: history.hasCompleted(mediaID: item.id) ?
                                  "arrow.uturn.backward.circle" : "checkmark.circle")
                        }
                        .accessibilityLabel(history.hasCompleted(mediaID: item.id) ?
                            "Mark \(item.title) as not watched" : "Mark \(item.title) watched")
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
                }
            }
            Text("A missing progress record does not prove you never watched a video. You can correct the watched mark. Kinetiq cannot scan other apps' private storage.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func refreshLocalFiles() { imported = KinetiqPrivateLibraryScanner.importedVideos() }

    private func runSearch() {
        queryFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        let parsed = KinetiqDiscoveryIntent.interpret(question)
        guard !parsed.original.isEmpty else { return }
        searchTask?.cancel()
        intent = parsed
        suggestions = []
        currentPage = 0
        morePublicPages = false
        errorMessage = nil
        refreshLocalFiles()
        if parsed.asksForLocal { showOnlyUnplayed = true }
        let localOnly = parsed.asksForLocal && parsed.catalogSearch == nil &&
            parsed.genre == nil && !parsed.finishedOnly && parsed.maximumEpisodes == nil
        guard !localOnly else { searching = false; return }
        fetchPage(parsed, page: 1, replacing: true)
    }

    private func fetchPage(_ parsed: KinetiqDiscoveryIntent, page: Int, replacing: Bool) {
        searchTask?.cancel()
        searching = true
        searchTask = Task {
            do {
                let result = try await KinetiqPublicAnimeSearch.shared.search(parsed, page: page)
                guard !Task.isCancelled, intent == parsed else { return }
                if replacing { suggestions = result.titles }
                else { suggestions.append(contentsOf: result.titles) }
                currentPage = page
                morePublicPages = result.hasMore
            } catch {
                guard !Task.isCancelled, intent == parsed else { return }
                errorMessage = "The public anime catalog isn't available right now. Module and local searches still work."
            }
            if intent == parsed { searching = false }
        }
    }
}
