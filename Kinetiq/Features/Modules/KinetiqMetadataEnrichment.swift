import SwiftUI
import Foundation
import Security

// MARK: - Supplemental display data (never a replacement source identity)

struct KinetiqEpisodeSupplement: Sendable {
    let title: String?
    let imageURL: URL?
    let synopsis: String?
    let durationMinutes: Int?
    let airDate: String?
}

struct KinetiqSeriesSupplement: Sendable {
    let provider: String
    let coverURL: URL?
    let bannerURL: URL?
    let alternativeTitles: [String]
    let episodeDetails: [Int: KinetiqEpisodeSupplement]
}

enum KinetiqEpisodeMetadataMatching {
    /// Do not turn an episode's descriptive title into its playback number.
    static func leadingEpisodeNumber(in raw: String?) -> String? {
        guard let raw,
              let expression = try? NSRegularExpression(
                pattern: #"(?i)^\s*(?:episode|ep\.?)[\s#]*(\d{1,4})(?:\b|\s*[:\-–—])"#),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[range])
    }

    static func displayTitle(_ raw: String?, episodeNumber: String) -> String? {
        guard let raw else { return nil }
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { return nil }
        if title == episodeNumber { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: episodeNumber)
        if let pattern = try? NSRegularExpression(
            pattern: "(?i)^\\s*(?:episode|ep\\.?)\\s*#?\\s*\(escaped)\\s*[:\\-–—]\\s*"),
           let match = pattern.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let range = Range(match.range, in: title) {
            title.removeSubrange(range)
        }
        let bare = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bare.isEmpty else { return nil }
        if let remaining = leadingEpisodeNumber(in: bare), remaining == episodeNumber,
           bare.range(of: #"(?i)^\s*(?:episode|ep\.?)\s*#?\s*\d+\s*$"#,
                      options: .regularExpression) != nil { return nil }
        return bare
    }

    /// Only a plain episode number is accepted for cross-provider alignment.
    /// OVA, specials, compound SxxExx and provider-specific IDs are not guessed.
    static func episodeIndex(_ raw: String) -> Int? {
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...10_000).contains(value) else { return nil }
        return value
    }

    static func normalized(_ raw: String) -> String {
        var value = raw.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                locale: Locale(identifier: "en_US_POSIX")).lowercased()
        value = value.replacingOccurrences(of: #"\b(\d+)(?:st|nd|rd|th)\s+season\b"#,
            with: "season $1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\bseason\s+(\d+)\b"#,
            with: "season $1", options: .regularExpression)
        return value.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#,
            with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func seasonAndBaseTitle(_ raw: String) -> (season: Int, baseTitle: String) {
        let patterns = [#"(?i)\s*[-:]*\s*season\s*(\d+)\s*$"#,
                        #"(?i)\s*[-:]*\s*(\d+)(?:st|nd|rd|th)\s+season\s*$"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  let valueRange = Range(match.range(at: 1), in: raw),
                  let season = Int(raw[valueRange]), (1...30).contains(season),
                  let allRange = Range(match.range, in: raw) else { continue }
            var base = raw
            base.removeSubrange(allRange)
            let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return (season, cleaned) }
        }
        return (1, raw)
    }
}

private enum KinetiqMetadataURL {
    static func image(_ string: String?) -> URL? {
        guard let string, string.count < 2_048,
              let url = URL(string: string), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

// MARK: - AniList GraphQL (public metadata, no media or playback requests)

actor KinetiqAniListMetadataService {
    static let shared = KinetiqAniListMetadataService()

    private struct CacheItem {
        let expiresAt: Date
        let result: KinetiqSeriesSupplement?
    }
    private var cache: [String: CacheItem] = [:]
    private var nextRequestAt = Date.distantPast
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private struct Envelope: Decodable {
        let data: Payload?
        struct Payload: Decodable {
            let page: Page?
            enum CodingKeys: String, CodingKey { case page = "Page" }
        }
        struct Page: Decodable { let media: [Media]? }
        struct Media: Decodable {
            let id: Int
            let title: Titles
            let synonyms: [String]?
            let coverImage: Cover?
            let bannerImage: String?
            let streamingEpisodes: [Streaming]?
        }
        struct Titles: Decodable {
            let romaji: String?
            let english: String?
            let native: String?
            let userPreferred: String?
            var all: [String] {
                [english, romaji, native, userPreferred].compactMap { $0 }
            }
        }
        struct Cover: Decodable { let extraLarge: String?; let large: String? }
        struct Streaming: Decodable {
            let title: String?
            let thumbnail: String?
        }
    }

    func lookup(title: String) async -> KinetiqSeriesSupplement? {
        let key = KinetiqEpisodeMetadataMatching.normalized(title)
        guard !key.isEmpty, key.count <= 160 else { return nil }
        if let cached = cache[key], cached.expiresAt > .now { return cached.result }

        // The public API can be temporarily limited to 30/minute. Reserve a
        // request slot before suspending, so concurrent screens cannot burst.
        let now = Date()
        let reserved = max(now, nextRequestAt)
        nextRequestAt = reserved.addingTimeInterval(2.2)
        let delay = reserved.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if Task.isCancelled { return nil }

        let result = await performLookup(title: title, exactKey: key)
        cache[key] = CacheItem(expiresAt: Date().addingTimeInterval(result == nil ? 600 : 86_400),
                               result: result)
        if cache.count > 200 { cache.removeAll(keepingCapacity: true) }
        return result
    }

    private func performLookup(title: String, exactKey: String) async -> KinetiqSeriesSupplement? {
        guard let endpoint = URL(string: "https://graphql.anilist.co") else { return nil }
        let query = """
        query ($search: String) {
          Page(page: 1, perPage: 8) {
            media(search: $search, type: ANIME) {
              id title { romaji english native userPreferred }
              synonyms coverImage { extraLarge large } bannerImage
              streamingEpisodes { title thumbnail }
            }
          }
        }
        """
        let payload: [String: Any] = ["query": query, "variables": ["search": title]]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              result.0.count < 800_000,
              let matches = (try? JSONDecoder().decode(Envelope.self, from: result.0))?.data?.page?.media
        else { return nil }

        let candidates = matches.filter { media in
            (media.title.all + (media.synonyms ?? [])).contains {
                KinetiqEpisodeMetadataMatching.normalized($0) == exactKey
            }
        }
        // Wrong-season artwork is worse than a graceful fallback.
        guard candidates.count == 1, let media = candidates.first else { return nil }
        var episodeDetails: [Int: KinetiqEpisodeSupplement] = [:]
        for entry in (media.streamingEpisodes ?? []).prefix(160) {
            guard let number = KinetiqEpisodeMetadataMatching.leadingEpisodeNumber(in: entry.title),
                  let index = Int(number), episodeDetails[index] == nil else { continue }
            let title = KinetiqEpisodeMetadataMatching.displayTitle(entry.title, episodeNumber: number)
            let image = KinetiqMetadataURL.image(entry.thumbnail)
            if title != nil || image != nil {
                episodeDetails[index] = KinetiqEpisodeSupplement(
                    title: title, imageURL: image, synopsis: nil,
                    durationMinutes: nil, airDate: nil)
            }
        }
        return KinetiqSeriesSupplement(
            provider: "AniList", coverURL: KinetiqMetadataURL.image(
                media.coverImage?.extraLarge ?? media.coverImage?.large),
            bannerURL: KinetiqMetadataURL.image(media.bannerImage),
            alternativeTitles: media.title.all + (media.synonyms ?? []),
            episodeDetails: episodeDetails)
    }
}

// MARK: - Optional TMDB episode details (key stays in iOS Keychain)

enum KinetiqTMDBCredentials {
    private static let service = "com.kinetiq.metadata.tmdb"
    private static let account = "tmdbReadAccessToken"

    static func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String?) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var record = query
        record[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(record as CFDictionary, nil) == errSecSuccess
    }
}

actor KinetiqTMDBEpisodeService {
    static let shared = KinetiqTMDBEpisodeService()
    private struct CacheItem {
        let expiresAt: Date
        let episodes: [Int: KinetiqEpisodeSupplement]
    }
    private var cache: [String: CacheItem] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    private struct SearchResponse: Decodable {
        let results: [Show]
        struct Show: Decodable {
            let id: Int
            let name: String
            let original_name: String?
        }
    }
    private struct SeasonResponse: Decodable {
        let episodes: [Episode]
        struct Episode: Decodable {
            let episode_number: Int
            let name: String?
            let overview: String?
            let still_path: String?
            let runtime: Int?
            let air_date: String?
        }
    }

    func lookup(title: String, alternativeTitles: [String]) async -> [Int: KinetiqEpisodeSupplement] {
        guard let token = KinetiqTMDBCredentials.token(), !token.isEmpty else { return [:] }
        let source = KinetiqEpisodeMetadataMatching.seasonAndBaseTitle(title)
        let key = KinetiqEpisodeMetadataMatching.normalized(source.baseTitle) + "|\(source.season)"
        if let cached = cache[key], cached.expiresAt > .now { return cached.episodes }

        var components = URLComponents(string: "https://api.themoviedb.org/3/search/tv")
        components?.queryItems = [URLQueryItem(name: "query", value: source.baseTitle),
                                  URLQueryItem(name: "language", value: "en-US")]
        guard let url = components?.url,
              let data = await get(url: url, token: token),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [:] }
        let known = Set(([source.baseTitle] + alternativeTitles).map {
            KinetiqEpisodeMetadataMatching.normalized(
                KinetiqEpisodeMetadataMatching.seasonAndBaseTitle($0).baseTitle)
        })
        let matches = response.results.prefix(20).filter { item in
            known.contains(KinetiqEpisodeMetadataMatching.normalized(item.name)) ||
            known.contains(KinetiqEpisodeMetadataMatching.normalized(item.original_name ?? ""))
        }
        // Require a unique exact series match and an explicit season number.
        guard matches.count == 1, let show = matches.first,
              let seasonURL = URL(string: "https://api.themoviedb.org/3/tv/\(show.id)/season/\(source.season)"),
              let seasonData = await get(url: seasonURL, token: token),
              let season = try? JSONDecoder().decode(SeasonResponse.self, from: seasonData)
        else { return [:] }
        var result: [Int: KinetiqEpisodeSupplement] = [:]
        for episode in season.episodes.prefix(150) where (1...10_000).contains(episode.episode_number) {
            let image = episode.still_path.flatMap { path -> URL? in
                guard path.hasPrefix("/"), !path.contains("..") else { return nil }
                return KinetiqMetadataURL.image("https://image.tmdb.org/t/p/w500\(path)")
            }
            let title = KinetiqEpisodeMetadataMatching.displayTitle(
                episode.name, episodeNumber: String(episode.episode_number))
            result[episode.episode_number] = KinetiqEpisodeSupplement(
                title: title, imageURL: image,
                synopsis: episode.overview.map { String($0.prefix(500)) },
                durationMinutes: episode.runtime, airDate: episode.air_date)
        }
        cache[key] = CacheItem(expiresAt: Date().addingTimeInterval(86_400), episodes: result)
        if cache.count > 100 { cache.removeAll(keepingCapacity: true) }
        return result
    }

    private func get(url: URL, token: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              result.0.count < 1_000_000 else { return nil }
        return result.0
    }
}

// MARK: - Reusable, artwork-role-aware anime hero

struct KinetiqDetailArtworkHero: View {
    let posterURL: URL?
    let bannerURL: URL?
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let bannerURL {
                    ModuleAnimeArtworkView(url: bannerURL)
                } else if let posterURL {
                    ModuleAnimeArtworkView(url: posterURL)
                        .blur(radius: 22)
                        .overlay(Color.black.opacity(0.28))
                    ModuleAnimeArtworkView(url: posterURL, contentMode: .fit)
                        .frame(width: min(geometry.size.width * 0.55, 220),
                               height: geometry.size.height - 32)
                        .padding(.bottom, 22)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                } else {
                    LinearGradient(colors: [.indigo.opacity(0.35), .black.opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Optional metadata settings

struct KinetiqMetadataSettingsView: View {
    @AppStorage("kinetiq.metadata.anilistEnabled") private var anilistEnabled = true
    @AppStorage("kinetiq.metadata.tmdbEnabled") private var tmdbEnabled = false
    @State private var keyInput = ""
    @State private var hasTMDBKey = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Anime metadata") {
                Toggle("AniList artwork and episode information", isOn: $anilistEnabled)
                Text("AniList can provide banners, posters and some episode thumbnails. If a title cannot be identified reliably, Kinetiq keeps its source artwork and episode numbers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Optional TMDB episode information") {
                Toggle("Use TMDB when configured", isOn: $tmdbEnabled)
                SecureField("TMDB API read access token", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save API token") {
                    let value = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if KinetiqTMDBCredentials.save(value.isEmpty ? nil : value) {
                        hasTMDBKey = !value.isEmpty
                        keyInput = ""
                        message = hasTMDBKey ? "Token saved securely on this iPhone." : "Saved token removed."
                    } else {
                        message = "Unable to save to iOS Keychain."
                    }
                }
                if hasTMDBKey {
                    Button("Remove saved TMDB token", role: .destructive) {
                        if KinetiqTMDBCredentials.save(nil) {
                            hasTMDBKey = false
                            message = "Saved token removed."
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text("TMDB is optional and requires your own API read token. Only uniquely matched series and seasons receive episode metadata.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Metadata credits") {
                Link("AniList", destination: URL(string: "https://anilist.co")!)
                Link("The Movie Database (TMDB)", destination: URL(string: "https://www.themoviedb.org")!)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Episode Metadata")
        .task { hasTMDBKey = KinetiqTMDBCredentials.token() != nil }
    }
}
