import Foundation
import Combine
import Security
import UIKit

// Batch 06L — isolated, opt-in, *unofficial* personal-account Gateway experiment.
// Discord does not support automating a normal user account. The Gateway can
// reject these payloads or terminate the account. No authentication data is
// bundled with Kinetiq, stored in UserDefaults, or written to diagnostics.

struct KinetiqPresencePlayback {
    let animeTitle: String
    let episodeNumber: String
    let episodeTitle: String?
    let language: String
    let posterURL: URL?
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let isPictureInPicture: Bool
}

/// A seek can temporarily put AVPlayer in `.paused` or `.waitingToPlayAtSpecifiedRate`
/// even though the viewer never pressed Pause. Discord should describe the
/// viewer's playback intent, once the stream has actually started, instead of
/// treating these short-lived AVPlayer status changes as deliberate pauses.
enum KinetiqPresencePlaybackIntent {
    static func isPlaying(
        requestedPlayback: Bool,
        hasStartedCurrentItem: Bool,
        playerReportsPlaying: Bool
    ) -> Bool {
        requestedPlayback && (hasStartedCurrentItem || playerReportsPlaying)
    }
}

/// The six Discord Gateway activity types supported by the Presence Lab UI.
/// Streaming requires a real Twitch/YouTube URL. Custom Status has a different
/// presentation from Rich Presence (no artwork or episode progress bar).
enum KinetiqDiscordActivityType: Int, CaseIterable, Identifiable {
    case playing = 0
    case streaming = 1
    case listening = 2
    case watching = 3
    case custom = 4
    case competing = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .playing: return "Playing"
        case .streaming: return "Streaming"
        case .listening: return "Listening"
        case .watching: return "Watching"
        case .custom: return "Custom Status"
        case .competing: return "Competing"
        }
    }

    var explanation: String {
        switch self {
        case .playing: return "Playing an anime. Discord may show elapsed time instead of a progress bar."
        case .streaming: return "Streaming is only accepted with a genuine Twitch or YouTube stream URL. Without one, Kinetiq sends Watching."
        case .listening: return "Listening to an anime. Discord supports an elapsed/total progress bar."
        case .watching: return "Watching an anime. Recommended for accurate episode playback progress."
        case .custom: return "A short 🍿 status showing the anime and episode. Discord does not display the normal Rich Presence poster or progress card."
        case .competing: return "Competing in an anime. The display may be less suitable for media playback."
        }
    }
}

/// The activity type supplies Discord's verb (Watching, Listening, etc.).
/// The name supplies the remaining words displayed in the profile heading.
enum KinetiqDiscordNameStyle: String, CaseIterable, Identifiable {
    case kinetiq = "Kinetiq"
    case onKinetiq = "on Kinetiq"
    case viaKinetiq = "via Kinetiq"
    case withKinetiq = "with Kinetiq"
    case inKinetiq = "in Kinetiq"
    case fromKinetiq = "from Kinetiq"

    var id: String { rawValue }
}

/// Discord displays the large artwork in a square. These styles affect the
/// image's contents, never the Discord profile layout or playback metadata.
enum KinetiqDiscordArtworkStyle: String, CaseIterable, Identifiable {
    case smartSquare = "Smart Square"
    case fullPoster = "Full Poster"
    case original = "Original HD"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .smartSquare:
            return "A crisp, square anime image with an attention-aware crop. Recommended for Discord."
        case .fullPoster:
            return "Preserves the entire vertical cover with a dark background at the sides."
        case .original:
            return "Sends the original high-resolution cover without external image processing."
        }
    }
}

/// Optional public-image-only transformer. The image service receives an
/// already-public, credential-free cover URL and returns a cached square JPEG.
/// No video URLs, session headers or Discord credentials are sent to it.
enum KinetiqDiscordArtworkRenderer {
    private static let endpoint = "https://wsrv.nl/"

    static func renderedURL(for original: URL, style: KinetiqDiscordArtworkStyle) -> URL? {
        guard let source = KinetiqDiscordActivity.publicArtwork(for: original) else { return nil }
        guard style != .original else { return original }
        var components = URLComponents(string: endpoint)
        var items = [
            URLQueryItem(name: "url", value: source),
            URLQueryItem(name: "w", value: "1024"),
            URLQueryItem(name: "h", value: "1024")
        ]
        switch style {
        case .smartSquare:
            items.append(contentsOf: [
                URLQueryItem(name: "fit", value: "cover"),
                URLQueryItem(name: "a", value: "attention"),
                URLQueryItem(name: "sharp", value: "0.8")
            ])
        case .fullPoster:
            items.append(contentsOf: [
                URLQueryItem(name: "fit", value: "contain"),
                URLQueryItem(name: "cbg", value: "171717")
            ])
        case .original:
            break
        }
        items.append(contentsOf: [
            URLQueryItem(name: "output", value: "jpg"),
            URLQueryItem(name: "q", value: "94")
        ])
        components?.queryItems = items
        guard let rendered = components?.url,
              rendered.absoluteString.utf8.count <= 1_000 else { return nil }
        return rendered
    }

    /// Accept only URLs that our own generator could have produced. Never
    /// permit arbitrary image-proxy query strings or signed source URLs.
    static func isGeneratedURL(_ candidate: URL) -> Bool {
        guard let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "wsrv.nl", parts.path == "/",
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let source = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let original = URL(string: source) else { return false }
        return [KinetiqDiscordArtworkStyle.smartSquare, .fullPoster].contains {
            renderedURL(for: original, style: $0) == candidate
        }
    }
}

/// Pure presentation mapping, usable without contacting Discord.
enum KinetiqDiscordActivity {
    static let applicationID = "1571558800387874819"

    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let whole = Int(min(seconds, 359_999))
        if whole >= 3_600 {
            return String(format: "%d:%02d:%02d", whole / 3_600, (whole / 60) % 60, whole % 60)
        }
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    static func description(for playback: KinetiqPresencePlayback) -> String {
        let title = playback.animeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Anime" : String(title.prefix(128))
    }

    static func state(for playback: KinetiqPresencePlayback) -> String {
        let number = playback.episodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = number.isEmpty ? "Episode" : "Episode \(number)"
        let language = playback.language.lowercased() == "dub" ? "DUB" : "SUB"
        let suffix = playback.isPlaying ? "" : " · Paused"
        // Use a descriptive episode title only when the source actually knows
        // one. Generic names like "Episode 3" would just repeat the number.
        let episodeTitle = KinetiqEpisodeMetadataMatching.displayTitle(
            playback.episodeTitle, episodeNumber: number
        )
        let trailing = " · \(language)\(suffix)"
        let available = max(0, 128 - trailing.count)
        let detail = episodeTitle.map { "\(label): \($0)" } ?? label
        return String(detail.prefix(available)) + trailing
    }

    /// Only plain HTTPS artwork URLs. Never send signed query URLs, private
    /// source headers, cookies, file URLs, or credentials to Discord.
    static func publicArtwork(for playback: KinetiqPresencePlayback) -> String? {
        publicArtwork(for: playback.posterURL)
    }

    static func publicArtwork(for url: URL?) -> String? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host != "localhost", !host.hasSuffix(".local"),
              host != "127.0.0.1", host != "::1",
              host.contains("."), !host.hasSuffix(".localhost"),
              !host.hasSuffix(".internal"), !host.hasSuffix(".lan"),
              !host.hasSuffix(".invalid"), !host.hasSuffix(".test"),
              host.rangeOfCharacter(from: .letters) != nil,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.absoluteString.count <= 400 else { return nil }
        return url.absoluteString
    }

    /// Streaming activities accept only public Twitch/YouTube URLs. Do not
    /// invent a link or use the anime's private streaming-source URL here.
    static func validStreamingURL(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              ["twitch.tv", "www.twitch.tv", "youtube.com", "www.youtube.com"].contains(host),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.absoluteString.count <= 500 else { return nil }
        return url
    }

    /// Developer Portal Rich Presence asset names must not be confused with
    /// external URLs. A known uploaded asset can be used to test whether the
    /// Gateway renders an image at all, independently of the anime cover URL.
    static func registeredAssetKey(_ input: String) -> String? {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (1...64).contains(key.count), key.utf8.allSatisfy({ byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        }) else { return nil }
        return key
    }

    /// An external image is not an uploaded Developer Portal asset. The
    /// unofficial Gateway path requires the media-proxy identifier returned
    /// by Discord's external-assets endpoint; an ordinary HTTPS URL often
    /// leaves the activity text visible while rendering no image.
    static func mediaProxyAsset(_ input: String?) -> String? {
        guard let input,
              input.hasPrefix("mp:external/"),
              (13...300).contains(input.utf8.count),
              !input.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
        else { return nil }
        return input
    }

    static func payload(
        for playback: KinetiqPresencePlayback,
        now: Date = Date(),
        posterOverride: URL? = nil,
        activityType: KinetiqDiscordActivityType = .watching,
        streamingURL: URL? = nil,
        nameStyle: KinetiqDiscordNameStyle = .kinetiq,
        registeredPosterKey: String? = nil,
        mediaProxyPoster: String? = nil
    ) -> [String: Any] {
        let validStream = streamingURL.flatMap { validStreamingURL($0.absoluteString) }
        let effectiveType: KinetiqDiscordActivityType =
            activityType == .streaming && validStream == nil ? .watching : activityType

        if effectiveType == .custom {
            let state = String("\(description(for: playback)) · \(state(for: playback))".prefix(128))
            let customActivity: [String: Any] = [
                "name": "Custom Status",
                "type": KinetiqDiscordActivityType.custom.rawValue,
                "state": state,
                "emoji": ["name": "🍿"]
            ]
            let body: [String: Any] = [
                "since": 0,
                "activities": [customActivity],
                "status": "online",
                "afk": false
            ]
            return ["op": 3, "d": body]
        }

        var activity: [String: Any] = [
            // Keep the application in the heading, not the anime title.
            // Discord may still override this with its registered app name.
            "name": nameStyle.rawValue,
            "type": effectiveType.rawValue,
            "application_id": applicationID,
            "details": description(for: playback),
            "state": state(for: playback)
        ]

        if effectiveType == .streaming, let validStream {
            activity["url"] = validStream.absoluteString
        }

        if let registered = registeredPosterKey.flatMap(registeredAssetKey) {
            activity["assets"] = [
                "large_image": registered,
                "large_text": description(for: playback)
            ]
        } else if let proxy = mediaProxyAsset(mediaProxyPoster) {
            activity["assets"] = [
                "large_image": proxy,
                "large_text": description(for: playback)
            ]
        } else if let artwork = publicArtwork(for: posterOverride) ?? publicArtwork(for: playback) {
            activity["assets"] = [
                "large_image": artwork,
                "large_text": description(for: playback)
            ]
        }
        if playback.isPlaying, playback.position.isFinite, playback.position >= 0 {
            // Discord activity timestamps use Unix *milliseconds*, not seconds.
            // Seconds made its progress bar appear as 00:01 / 00:01 on iPhone.
            let start = (now.timeIntervalSince1970 - playback.position) * 1_000
            var timestamps: [String: Int] = ["start": Int(start)]
            if playback.duration.isFinite, playback.duration > 0 {
                timestamps["end"] = Int(start + playback.duration * 1_000)
            }
            activity["timestamps"] = timestamps
        }
        return ["op": 3, "d": [
            "since": 0,
            "activities": [activity],
            "status": "online",
            "afk": false
        ]]
    }

    static let clearPayload: [String: Any] = [
        "op": 3,
        "d": ["since": 0, "activities": [], "status": "online", "afk": false]
    ]
}

/// Unofficial endpoint used by other community Rich Presence clients. The
/// registration response is an opaque identifier; do not attempt to guess its
/// hash or construct `mp:external/` from an original URL.
enum KinetiqDiscordExternalArtwork {
    enum Failure: Error {
        case httpStatus(Int)
        case malformedResponse
        case imageUnavailable
    }

    static func proxyIdentifier(from response: Data) -> String? {
        guard let entries = try? JSONSerialization.jsonObject(with: response) as? [[String: Any]],
              let path = entries.first?["external_asset_path"] as? String else { return nil }
        return KinetiqDiscordActivity.mediaProxyAsset("mp:" + path)
    }

    static func register(publicURL: URL, credential: String) async throws -> String {
        guard let safe = KinetiqDiscordActivity.publicArtwork(for: publicURL)
                ?? (KinetiqDiscordArtworkRenderer.isGeneratedURL(publicURL)
                        ? publicURL.absoluteString : nil),
              let endpoint = URL(string: "https://discord.com/api/v9/applications/\(KinetiqDiscordActivity.applicationID)/external-assets")
        else { throw Failure.malformedResponse }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["urls": [safe]])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // Validate generated artwork before asking Discord to proxy it. The
        // free processor may reject a particular source or be unavailable;
        // callers then register the original cover automatically.
        if KinetiqDiscordArtworkRenderer.isGeneratedURL(publicURL) {
            var imageRequest = URLRequest(url: publicURL)
            imageRequest.timeoutInterval = 15
            let (imageData, imageResponse) = try await session.data(for: imageRequest)
            guard let imageHTTP = imageResponse as? HTTPURLResponse,
                  imageHTTP.statusCode == 200,
                  imageHTTP.mimeType?.lowercased().hasPrefix("image/") == true,
                  (1...4_000_000).contains(imageData.count),
                  let image = UIImage(data: imageData),
                  image.size.width >= 512, image.size.height >= 512
            else { throw Failure.imageUnavailable }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformedResponse }
        guard http.statusCode == 200 else { throw Failure.httpStatus(http.statusCode) }
        guard data.count <= 64 * 1024, let image = proxyIdentifier(from: data) else {
            throw Failure.malformedResponse
        }
        return image
    }
}

private enum KinetiqDiscordCredentialStore {
    private static let service = "com.kinetiq.player.ios.discord-presence-lab"
    private static let account = "discord-personal-session"

    static var exists: Bool {
        read() != nil
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        guard let data = token.data(using: .utf8) else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The personal Gateway activity path shares Discord's game-status update
/// budget. Use a conservative rolling window and coalesce seek bursts instead
/// of submitting one presence packet for every +10s tap or slider movement.
enum KinetiqPresenceSyncPolicy {
    static let seekSettleDelay: TimeInterval = 1.25
    static let minimumUpdateSpacing: TimeInterval = 5
    static let rollingWindow: TimeInterval = 20
    static let maximumUpdatesPerWindow = 4

    static func nextAllowedDate(after now: Date, attempts: [Date]) -> Date {
        let recent = attempts.filter {
            now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < rollingWindow
        }.sorted()
        var allowed = now
        if let last = attempts.max() {
            allowed = max(allowed, last.addingTimeInterval(minimumUpdateSpacing))
        }
        if recent.count >= maximumUpdatesPerWindow {
            allowed = max(allowed, recent[recent.count - maximumUpdatesPerWindow]
                .addingTimeInterval(rollingWindow + 0.1))
        }
        return allowed
    }

    static func isSeek(
        previous: TimeInterval, current: TimeInterval,
        elapsed: TimeInterval, wasPlaying: Bool
    ) -> Bool {
        guard previous.isFinite, current.isFinite else { return false }
        let predicted = previous + (wasPlaying ? max(0, elapsed) : 0)
        return abs(current - predicted) >= 3
    }
}

@MainActor
final class KinetiqDiscordPresenceManager: ObservableObject {
    static let shared = KinetiqDiscordPresenceManager()

    enum Connection: String {
        case off = "Off"
        case disconnected = "Disconnected"
        case connecting = "Connecting…"
        case connected = "Gateway connected (not externally verified)"
        case needsCredential = "Token missing or rejected"
        case interrupted = "Connection interrupted"
    }

    static let enabledKey = "kinetiq.discordPresenceLab.enabled"
    static let activityTypeKey = "kinetiq.discordPresenceLab.activityType"
    static let streamingURLKey = "kinetiq.discordPresenceLab.streamingURL"
    static let nameStyleKey = "kinetiq.discordPresenceLab.nameStyle"
    static let registeredPosterKey = "kinetiq.discordPresenceLab.registeredPosterKey"
    static let artworkStyleKey = "kinetiq.discordPresenceLab.artworkStyle"

    @Published private(set) var enabled: Bool
    @Published private(set) var hasCredential: Bool
    @Published private(set) var activityType: KinetiqDiscordActivityType
    @Published private(set) var nameStyle: KinetiqDiscordNameStyle
    @Published private(set) var artworkStyle: KinetiqDiscordArtworkStyle
    @Published private(set) var posterAssetKey: String?
    @Published private(set) var streamingURL: URL?
    @Published private(set) var connection: Connection = .off
    @Published private(set) var message = "No connection has been tested."
    @Published private(set) var connectionStage = "Not started"
    /// Only fixed labels and numeric system codes. Never include a server frame,
    /// token, HTTP header, request URL, or the original error description.
    @Published private(set) var safeDiagnostics = "No connection attempt recorded."
    @Published private(set) var lastPreview: KinetiqPresencePlayback?
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var publicPosterURL: URL?
    @Published private(set) var artworkResolutionStatus = "No poster submitted."
    @Published private(set) var playbackSyncStatus = "Waiting for playback."

    var artworkPreviewURL: URL? { selectedArtworkURL }

    /// Only the selected public artwork URL is handed to Discord. When image
    /// transformation is cooling down after an error, keep the original art.
    private var selectedArtworkURL: URL? {
        guard let publicPosterURL else { return nil }
        guard let enhanced = KinetiqDiscordArtworkRenderer.renderedURL(
            for: publicPosterURL, style: artworkStyle
        ), enhanced != publicPosterURL else { return publicPosterURL }
        if let retryAt = artworkRetryAfter[enhanced.absoluteString], retryAt > Date() {
            return publicPosterURL
        }
        return enhanced
    }

    private var socket: URLSessionWebSocketTask?
    private var listeningTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttemptCount = 0
    private var lastSequence: Int?
    private var generation = 0
    private var lastSignature: String?
    private var lastPublication = Date.distantPast
    private var lastPublishedPosition: TimeInterval?
    private var lastPreviewRecordedAt = Date.distantPast
    private var previousPlaybackSample: (key: String, position: TimeInterval,
                                         date: Date, playing: Bool)?
    private var lastSeekObservedAt: Date?
    private var presenceSendAttempts: [Date] = []
    private var presenceSendTask: Task<Void, Never>?
    private var scheduledPresenceTask: Task<Void, Never>?
    private var scheduledPresenceAt: Date?
    private var pendingForcedPublication = false
    private var forcedPublicationRevision = 0
    private var failedPublicationRetryAt = Date.distantPast
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var lastBackgroundAt: Date?
    private var artworkLookupTitle: String?
    private var artworkLookupTask: Task<Void, Never>?
    private var artworkRegistrationTask: Task<Void, Never>?
    private var artworkRegistrationURL: URL?
    private var registeredMediaProxy: String?
    private var artworkCache: [String: (identifier: String, expiresAt: Date)] = [:]
    private var artworkRetryAfter: [String: Date] = [:]
    private var startedAt: Date?
    private var lastGatewayOpcode: Int?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hasCredential = KinetiqDiscordCredentialStore.exists
        let savedType = UserDefaults.standard.object(forKey: Self.activityTypeKey) as? Int
        activityType = savedType.flatMap(KinetiqDiscordActivityType.init(rawValue:)) ?? .watching
        nameStyle = UserDefaults.standard.string(forKey: Self.nameStyleKey)
            .flatMap(KinetiqDiscordNameStyle.init(rawValue:)) ?? .kinetiq
        artworkStyle = UserDefaults.standard.string(forKey: Self.artworkStyleKey)
            .flatMap(KinetiqDiscordArtworkStyle.init(rawValue:)) ?? .smartSquare
        posterAssetKey = UserDefaults.standard.string(forKey: Self.registeredPosterKey)
            .flatMap(KinetiqDiscordActivity.registeredAssetKey)
        let savedStreamingURL = UserDefaults.standard.string(forKey: Self.streamingURLKey) ?? ""
        streamingURL = KinetiqDiscordActivity.validStreamingURL(savedStreamingURL)
        connection = enabled ? .disconnected : .off
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreForegroundConnection()
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastBackgroundAt = Date()
            }
        }
        if enabled && hasCredential {
            Task { @MainActor [weak self] in self?.connect() }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value { connect() }
        else {
            disconnect()
            connection = .off
            lastPreview = nil
            publicPosterURL = nil
            artworkLookupTitle = nil
            artworkLookupTask?.cancel()
            artworkLookupTask = nil
            artworkResolutionStatus = "Presence Lab disabled."
        }
    }

    func setActivityType(_ type: KinetiqDiscordActivityType) {
        guard activityType != type else { return }
        activityType = type
        UserDefaults.standard.set(type.rawValue, forKey: Self.activityTypeKey)
        publishIfNeeded(force: true)
    }

    func setNameStyle(_ style: KinetiqDiscordNameStyle) {
        guard nameStyle != style else { return }
        nameStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.nameStyleKey)
        publishIfNeeded(force: true)
    }

    func setArtworkStyle(_ style: KinetiqDiscordArtworkStyle) {
        guard artworkStyle != style else { return }
        artworkStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.artworkStyleKey)
        // Switching style changes the artwork registration key, but not the
        // underlying public anime cover or playback state.
        publishIfNeeded(force: true)
    }

    @discardableResult
    func savePosterAssetKey(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            posterAssetKey = nil
            UserDefaults.standard.removeObject(forKey: Self.registeredPosterKey)
            artworkRegistrationURL = nil
            publishIfNeeded(force: true)
            return true
        }
        guard let key = KinetiqDiscordActivity.registeredAssetKey(trimmed) else { return false }
        posterAssetKey = key
        UserDefaults.standard.set(key, forKey: Self.registeredPosterKey)
        artworkRegistrationTask?.cancel()
        artworkRegistrationTask = nil
        artworkResolutionStatus = "Using selected Developer Portal asset."
        publishIfNeeded(force: true)
        return true
    }

    @discardableResult
    func saveStreamingURL(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            streamingURL = nil
            UserDefaults.standard.removeObject(forKey: Self.streamingURLKey)
            publishIfNeeded(force: true)
            return true
        }
        guard let url = KinetiqDiscordActivity.validStreamingURL(trimmed) else {
            message = "Streaming requires an HTTPS Twitch or YouTube URL. Nothing was changed."
            return false
        }
        streamingURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.streamingURLKey)
        publishIfNeeded(force: true)
        return true
    }

    /// Never return the stored token to a view or put it in an observable field.
    @discardableResult
    func saveCredential(_ entry: String) -> Bool {
        let token = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 40, !token.contains(where: { $0.isWhitespace }),
              KinetiqDiscordCredentialStore.save(token) else {
            message = "Could not save the token. Check its format or Keychain access."
            return false
        }
        hasCredential = true
        message = "Saved locally in iPhone Keychain. Not verified by Discord."
        if enabled { connect() }
        return true
    }

    func forgetCredential() {
        disconnect()
        KinetiqDiscordCredentialStore.delete()
        hasCredential = false
        connection = .needsCredential
        message = "Saved token removed from this iPhone."
        connectionStage = "Credential removed"
    }

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttemptCount = 0
        startConnection()
    }

    private func startConnection() {
        guard enabled else { connection = .off; return }
        guard let token = KinetiqDiscordCredentialStore.read(), !token.isEmpty else {
            connection = .needsCredential
            message = "Enter a fresh token on this device."
            return
        }
        closeTransport()
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        // A Gateway READY payload can exceed URLSession's default receive limit.
        // Allow a larger message while retaining a finite memory bound.
        task.maximumMessageSize = 16 * 1024 * 1024
        generation += 1
        let currentGeneration = generation
        socket = task
        connection = .connecting
        message = "Opening the experimental Gateway session…"
        connectionStage = "Opening WebSocket"
        safeDiagnostics = "Connection attempt in progress. No credential data is recorded."
        lastGatewayOpcode = nil
        startedAt = Date()
        task.resume()
        listeningTask = Task { @MainActor [weak self] in
            await self?.receiveLoop(on: task, generation: currentGeneration, token: token)
            session.invalidateAndCancel()
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttemptCount = 0
        closeTransport()
        connection = enabled ? .disconnected : .off
        message = "Disconnected from Discord."
        connectionStage = "Disconnected"
    }

    private func closeTransport() {
        generation += 1
        scheduledPresenceTask?.cancel()
        scheduledPresenceTask = nil
        scheduledPresenceAt = nil
        presenceSendTask?.cancel()
        presenceSendTask = nil
        presenceSendAttempts.removeAll()
        pendingForcedPublication = false
        failedPublicationRetryAt = .distantPast
        lastSeekObservedAt = nil
        previousPlaybackSample = nil
        playbackSyncStatus = "Waiting for Gateway connection."
        artworkRegistrationTask?.cancel()
        artworkRegistrationTask = nil
        artworkRegistrationURL = nil
        registeredMediaProxy = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listeningTask?.cancel()
        listeningTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        lastSequence = nil
        lastSignature = nil
        lastPublishedPosition = nil
        lastSentAt = nil
    }

    func record(_ snapshot: KinetiqPresencePlayback) {
        guard enabled else { return }
        let now = Date()
        let sampleKey = "\(snapshot.animeTitle)|\(snapshot.episodeNumber)|\(snapshot.language)"
        if let previous = previousPlaybackSample, previous.key == sampleKey,
           KinetiqPresenceSyncPolicy.isSeek(
               previous: previous.position, current: snapshot.position,
               elapsed: now.timeIntervalSince(previous.date), wasPlaying: previous.playing
           ) {
            lastSeekObservedAt = now
        } else if previousPlaybackSample?.key != sampleKey {
            lastSeekObservedAt = nil
        }
        previousPlaybackSample = (sampleKey, snapshot.position, now, snapshot.isPlaying)
        lastPreview = snapshot
        lastPreviewRecordedAt = now
        prepareArtwork(for: snapshot)
        guard connection == .connected else { return }
        publishIfNeeded(force: false)
    }

    func playbackEnded() {
        guard enabled else { return }
        scheduledPresenceTask?.cancel()
        scheduledPresenceTask = nil
        scheduledPresenceAt = nil
        pendingForcedPublication = false
        previousPlaybackSample = nil
        lastSeekObservedAt = nil
        playbackSyncStatus = "Playback ended."
        lastPreview = nil
        publicPosterURL = nil
        artworkRegistrationTask?.cancel()
        artworkRegistrationTask = nil
        artworkRegistrationURL = nil
        registeredMediaProxy = nil
        artworkResolutionStatus = "Playback ended."
        artworkLookupTitle = nil
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        lastSignature = nil
        guard let socket, connection == .connected else { return }
        let sendTask = presenceSendTask
        let connectionGeneration = generation
        Task { @MainActor [weak self] in
            // A clear packet must follow any already-running activity send.
            await sendTask?.value
            guard let self, self.generation == connectionGeneration,
                  self.lastPreview == nil, self.connection == .connected else { return }
            try? await Self.send(KinetiqDiscordActivity.clearPayload, on: socket)
        }
    }

    /// Manual preview publishing is useful to isolate Discord acceptance from
    /// player events. A READY event only proves a Gateway session, NOT that a
    /// second Discord account can see the rich presence or its image.
    func sendTestActivity() {
        guard enabled else { return }
        lastPreview = KinetiqPresencePlayback(
            animeTitle: "Kinetiq Presence Lab", episodeNumber: "1",
            episodeTitle: nil, language: "sub", posterURL: nil,
            position: 0, duration: 1200, isPlaying: true, isPictureInPicture: false
        )
        lastPreviewRecordedAt = Date()
        publicPosterURL = nil
        artworkLookupTitle = "Kinetiq Presence Lab"
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        publishIfNeeded(force: true)
    }

    /// A user-initiated refresh still obeys the same rolling update budget.
    /// It is useful after iOS resumes a long PiP or foreground session.
    func resyncCurrentPlayback() {
        guard enabled, connection == .connected, lastPreview != nil else { return }
        publishIfNeeded(force: true)
    }

    private func publishIfNeeded(force: Bool) {
        guard let socket, connection == .connected, let lastPreview else { return }
        if force {
            pendingForcedPublication = true
            forcedPublicationRevision += 1
        }
        ensureRegisteredPoster()
        let now = Date()
        let age = max(0, now.timeIntervalSince(lastPreviewRecordedAt))
        let basePosition = lastPreview.position.isFinite ? max(0, lastPreview.position) : 0
        let advancingPosition = basePosition + (lastPreview.isPlaying ? age : 0)
        let position = lastPreview.duration.isFinite && lastPreview.duration > 0
            ? min(advancingPosition, lastPreview.duration) : advancingPosition
        let adjusted = KinetiqPresencePlayback(
            animeTitle: lastPreview.animeTitle,
            episodeNumber: lastPreview.episodeNumber,
            episodeTitle: lastPreview.episodeTitle,
            language: lastPreview.language,
            posterURL: lastPreview.posterURL,
            position: position,
            duration: lastPreview.duration,
            isPlaying: lastPreview.isPlaying,
            isPictureInPicture: lastPreview.isPictureInPicture
        )
        let signature = "\(adjusted.animeTitle)|\(adjusted.episodeNumber)|\(adjusted.episodeTitle ?? "")|\(adjusted.language)|\(adjusted.isPlaying)|\(adjusted.isPictureInPicture)|\(publicPosterURL?.absoluteString ?? "")|\(registeredMediaProxy ?? "")|\(activityType.rawValue)|\(nameStyle.rawValue)|\(artworkStyle.rawValue)|\(posterAssetKey ?? "")|\(streamingURL?.absoluteString ?? "")"
        let elapsed = now.timeIntervalSince(lastPublication)
        let expectedUnclamped = (lastPublishedPosition ?? position) + (adjusted.isPlaying ? max(0, elapsed) : 0)
        let expectedPosition = adjusted.duration.isFinite && adjusted.duration > 0
            ? min(expectedUnclamped, adjusted.duration) : expectedUnclamped
        let seeked = lastPublishedPosition != nil && abs(position - expectedPosition) >= 4
        if !pendingForcedPublication, signature == lastSignature,
           elapsed < 30, !seeked {
            scheduledPresenceTask?.cancel()
            scheduledPresenceTask = nil
            scheduledPresenceAt = nil
            playbackSyncStatus = "Synchronized with the last submitted position."
            return
        }
        // Serialize activity packets. Otherwise a slow WebSocket send can
        // overtake a newer seek and leave Discord displaying a stale timer.
        guard presenceSendTask == nil else { return }

        var allowedAt = KinetiqPresenceSyncPolicy.nextAllowedDate(
            after: now, attempts: presenceSendAttempts
        )
        if seeked, let lastSeekObservedAt {
            allowedAt = max(allowedAt, lastSeekObservedAt.addingTimeInterval(
                KinetiqPresenceSyncPolicy.seekSettleDelay))
        }
        allowedAt = max(allowedAt, failedPublicationRetryAt)
        if allowedAt.timeIntervalSince(now) > 0.05 {
            schedulePresencePublish(at: allowedAt)
            playbackSyncStatus = seeked && lastSeekObservedAt.map({
                $0.addingTimeInterval(KinetiqPresenceSyncPolicy.seekSettleDelay) > now
            }) == true ? "Settling rapid seek changes…" : "Update queued within Discord's rate limit."
            return
        }
        scheduledPresenceTask?.cancel()
        scheduledPresenceTask = nil
        scheduledPresenceAt = nil
        let payload = KinetiqDiscordActivity.payload(
            for: adjusted, now: now, posterOverride: publicPosterURL,
            activityType: activityType, streamingURL: streamingURL,
            nameStyle: nameStyle, registeredPosterKey: posterAssetKey,
            mediaProxyPoster: artworkRegistrationURL == selectedArtworkURL ? registeredMediaProxy : nil
        )
        presenceSendAttempts.removeAll { now.timeIntervalSince($0) >= KinetiqPresenceSyncPolicy.rollingWindow }
        presenceSendAttempts.append(now)
        let connectionGeneration = generation
        let sentRevision = forcedPublicationRevision
        playbackSyncStatus = "Submitting latest playback position…"
        presenceSendTask = Task { @MainActor [weak self] in
            do {
                try await Self.send(payload, on: socket)
                guard let self, self.generation == connectionGeneration else { return }
                self.lastSignature = signature
                self.lastPublication = now
                self.lastPublishedPosition = position
                self.lastSentAt = Date()
                if self.forcedPublicationRevision == sentRevision {
                    self.pendingForcedPublication = false
                }
                self.failedPublicationRetryAt = .distantPast
                self.playbackSyncStatus = "Latest activity submitted."
                self.message = "Activity submitted. Check visibility from another Discord account."
            } catch {
                guard let self, self.generation == connectionGeneration else { return }
                self.failedPublicationRetryAt = Date().addingTimeInterval(10)
                self.playbackSyncStatus = "Submission failed; retry queued."
                self.message = "Presence update could not be sent. Will retry if connected."
            }
            guard let self, self.generation == connectionGeneration else { return }
            self.presenceSendTask = nil
            self.publishIfNeeded(force: false)
        }
    }

    private func schedulePresencePublish(at date: Date) {
        if let scheduledPresenceAt,
           abs(scheduledPresenceAt.timeIntervalSince(date)) < 0.15 { return }
        scheduledPresenceTask?.cancel()
        scheduledPresenceAt = date
        let connectionGeneration = generation
        scheduledPresenceTask = Task { @MainActor [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded(.up))))
            } catch { return }
            guard let self, !Task.isCancelled,
                  self.generation == connectionGeneration else { return }
            self.scheduledPresenceTask = nil
            self.scheduledPresenceAt = nil
            self.publishIfNeeded(force: false)
        }
    }

    /// Only an image returned by Discord's external-assets registration is
    /// advertised as an `mp:` media-proxy asset. One request is made per cover
    /// change; successful results are cached for four hours. Failed requests
    /// back off rather than retrying on every player's time observation.
    private func ensureRegisteredPoster() {
        guard posterAssetKey == nil, activityType != .custom else { return }
        guard let url = selectedArtworkURL,
              KinetiqDiscordActivity.publicArtwork(for: url) != nil
                || KinetiqDiscordArtworkRenderer.isGeneratedURL(url) else {
            artworkRegistrationTask?.cancel()
            artworkRegistrationTask = nil
            artworkRegistrationURL = nil
            registeredMediaProxy = nil
            artworkResolutionStatus = "No public anime poster URL available."
            return
        }

        if artworkRegistrationURL == url {
            if registeredMediaProxy != nil || artworkRegistrationTask != nil { return }
        } else {
            artworkRegistrationTask?.cancel()
            artworkRegistrationTask = nil
            artworkRegistrationURL = url
            registeredMediaProxy = nil
        }

        let key = url.absoluteString
        if let entry = artworkCache[key], entry.expiresAt > Date() {
            registeredMediaProxy = entry.identifier
            artworkResolutionStatus = "Discord media proxy resolved (cached). \(artworkStyle.rawValue)."
            return
        }
        if let retryAfter = artworkRetryAfter[key], retryAfter > Date() {
            artworkResolutionStatus = "Discord image registration failed. Retry later or change poster."
            return
        }
        guard let credential = KinetiqDiscordCredentialStore.read() else {
            artworkResolutionStatus = "Discord credential unavailable."
            return
        }
        artworkResolutionStatus = url == publicPosterURL
            ? "Registering original anime artwork…"
            : "Preparing 1024 × 1024 artwork and registering with Discord…"
        artworkRegistrationTask = Task { @MainActor [weak self] in
            do {
                let identifier = try await KinetiqDiscordExternalArtwork.register(
                    publicURL: url, credential: credential
                )
                guard let self, !Task.isCancelled,
                      self.artworkRegistrationURL == url,
                      self.connection == .connected,
                      self.posterAssetKey == nil else { return }
                self.artworkRegistrationTask = nil
                self.registeredMediaProxy = identifier
                self.artworkCache[key] = (identifier, Date().addingTimeInterval(4 * 60 * 60))
                self.artworkRetryAfter.removeValue(forKey: key)
                self.artworkResolutionStatus = "Discord media proxy resolved. Verify image from another account."
                self.publishIfNeeded(force: true)
            } catch {
                guard let self, !Task.isCancelled,
                      self.artworkRegistrationURL == url else { return }
                self.artworkRegistrationTask = nil
                self.artworkRetryAfter[key] = Date().addingTimeInterval(5 * 60)
                if KinetiqDiscordArtworkRenderer.isGeneratedURL(url) {
                    // A transformation failure must never remove artwork from
                    // an activity that already succeeded with the original.
                    self.artworkResolutionStatus = "Artwork enhancement unavailable. Using the original anime poster."
                    self.ensureRegisteredPoster()
                    self.publishIfNeeded(force: true)
                    return
                }
                if case let KinetiqDiscordExternalArtwork.Failure.httpStatus(code) = error {
                    self.artworkResolutionStatus = "Discord image registration returned HTTP \(code). Will retry later."
                } else {
                    self.artworkResolutionStatus = "Discord image registration failed. Will retry later."
                }
            }
        }
    }

    /// Prefer the verified public metadata cover when the provider's poster is
    /// missing or inaccessible. This reuses Kinetiq's existing AniList service;
    /// no player URL, cookies, or source credentials ever leave the device.
    private func prepareArtwork(for playback: KinetiqPresencePlayback) {
        let title = playback.animeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if artworkLookupTitle == title {
            if publicPosterURL == nil,
               let safe = KinetiqDiscordActivity.publicArtwork(for: playback) {
                publicPosterURL = URL(string: safe)
            }
            return
        }
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        artworkLookupTitle = title
        publicPosterURL = KinetiqDiscordActivity.publicArtwork(for: playback).flatMap(URL.init(string:))
        guard !title.isEmpty, title != "Kinetiq Presence Lab" else { return }
        artworkLookupTask = Task { @MainActor [weak self] in
            let supplement = await KinetiqAniListMetadataService.shared.lookup(title: title)
            guard let self, !Task.isCancelled,
                  self.artworkLookupTitle == title else { return }
            self.artworkLookupTask = nil
            // The exact-title metadata matcher rejects ambiguous or wrong-season covers.
            guard let safe = KinetiqDiscordActivity.publicArtwork(for: supplement?.coverURL),
                  let url = URL(string: safe), url != self.publicPosterURL else { return }
            self.publicPosterURL = url
            self.publishIfNeeded(force: true)
        }
    }

    /// PiP can keep media playback active, but iOS may suspend the WebSocket.
    /// Probe on foreground return; reconnect only when the socket failed.
    private func restoreForegroundConnection() {
        guard enabled, hasCredential else { return }
        guard lastBackgroundAt != nil else {
            if socket == nil && connection == .interrupted { connect() }
            return
        }
        lastBackgroundAt = nil
        if socket == nil && connection == .interrupted {
            connect()
        } else if let socket, connection == .connected {
            let connectionGeneration = generation
            socket.sendPing { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.enabled,
                          self.generation == connectionGeneration else { return }
                    if error == nil { self.publishIfNeeded(force: true) }
                    else { self.connect() }
                }
            }
        }
    }

    /// Retry transient failures while iOS gives the process execution time.
    /// Backoff and a finite attempt limit avoid hammering Discord's Gateway.
    /// When iOS suspends the app, the foreground probe remains the fallback.
    private func scheduleTransientReconnect() {
        guard enabled, hasCredential, reconnectTask == nil,
              reconnectAttemptCount < 5 else { return }
        let delays = [2, 4, 8, 16, 30]
        let delay = delays[reconnectAttemptCount]
        reconnectAttemptCount += 1
        message = "Connection interrupted. Retrying in \(delay) seconds if iOS permits."
        reconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard self.enabled, self.hasCredential,
                  self.connection == .interrupted else { return }
            if UIApplication.shared.applicationState == .background,
               self.lastPreview?.isPictureInPicture != true {
                return
            }
            self.startConnection()
        }
    }

    private func receiveLoop(
        on task: URLSessionWebSocketTask, generation: Int, token: String
    ) async {
        do {
            while !Task.isCancelled && generation == self.generation {
                let frame = try await task.receive()
                let data: Data
                switch frame {
                case .string(let string): data = Data(string.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let packet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let op = packet["op"] as? Int else { continue }
                lastGatewayOpcode = op
                if let sequence = packet["s"] as? Int { lastSequence = sequence }
                if op == 10 {
                    connectionStage = "Gateway HELLO received"
                    if let details = packet["d"] as? [String: Any],
                       let interval = details["heartbeat_interval"] as? Double {
                        beginHeartbeat(on: task, interval: interval, generation: generation)
                    }
                    let identify: [String: Any] = ["op": 2, "d": [
                        "token": token,
                        "properties": [
                            "os": "iOS", "browser": "Kinetiq Presence Lab", "device": "iPhone"
                        ],
                        "compress": false,
                        "large_threshold": 50
                    ]]
                    try await Self.send(identify, on: task)
                    connectionStage = "IDENTIFY sent; awaiting READY"
                } else if op == 0, packet["t"] as? String == "READY" {
                    connection = .connected
                    reconnectAttemptCount = 0
                    connectionStage = "Gateway READY received"
                    message = "Gateway READY. Rich Presence and artwork still need peer verification."
                    safeDiagnostics = "Gateway READY received. Rich Presence visibility has not been verified. No credential data is recorded."
                    publishIfNeeded(force: true)
                } else if op == 9 {
                    connection = .interrupted
                    connectionStage = "Gateway invalid session (opcode 9)"
                    message = "Discord reported an invalid Gateway session. This does not establish why it was rejected."
                    safeDiagnostics = diagnosticReport(for: task, error: nil)
                    break
                } else if op == 7 {
                    connection = .interrupted
                    connectionStage = "Gateway reconnect requested (opcode 7)"
                    message = "Discord requested a new session."
                    safeDiagnostics = diagnosticReport(for: task, error: nil)
                    break
                } else if op == 1 {
                    try await Self.send(["op": 1, "d": lastSequence as Any? ?? NSNull()], on: task)
                }
            }
        } catch {
            if generation == self.generation {
                safeDiagnostics = diagnosticReport(for: task, error: error)
                let code = task.closeCode
                if code.rawValue == 4004 || code.rawValue == 4003 {
                    connection = .needsCredential
                    message = "Discord closed the authentication session. See safe diagnostics."
                } else {
                    connection = .interrupted
                    message = "Connection interrupted before a usable session. See safe diagnostics; this is not necessarily a PiP issue."
                }
            }
        }
        guard generation == self.generation else { return }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket = nil
        if connection == .connected || connection == .connecting {
            connection = .interrupted
            message = "Gateway session ended. Tap Reconnect."
            safeDiagnostics = diagnosticReport(for: task, error: nil)
        }
        if connection == .interrupted { scheduleTransientReconnect() }
    }

    private func diagnosticReport(for task: URLSessionWebSocketTask, error: Error?) -> String {
        let closeCode = task.closeCode
        let closeText = closeCode == .invalid ? "Not provided" : String(closeCode.rawValue)
        let httpText = (task.response as? HTTPURLResponse).map { String($0.statusCode) } ?? "Not available"
        let opcodeText = lastGatewayOpcode.map { String($0) } ?? "None received"
        let duration = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        let errorText: String
        if let error {
            let nsError = error as NSError
            let category: String
            switch nsError.domain {
            case NSURLErrorDomain: category = "URLSession"
            case NSPOSIXErrorDomain: category = nsError.code == 40 ? "POSIX / message too long" : "POSIX"
            case NSCocoaErrorDomain: category = "Cocoa"
            default: category = "Other system error"
            }
            errorText = "\(category) (\(nsError.code))"
        } else {
            errorText = "No transport error was captured"
        }
        return """
        Kinetiq Presence Lab / safe diagnostic
        Stage: \(connectionStage)
        HTTP upgrade: \(httpText)
        Last Gateway opcode: \(opcodeText)
        WebSocket close code: \(closeText)
        Transport: \(errorText)
        Elapsed: \(duration) seconds
        Token, WebSocket payloads, headers, cookies, and server text excluded.
        """
    }

    private func beginHeartbeat(on task: URLSessionWebSocketTask, interval: Double, generation: Int) {
        heartbeatTask?.cancel()
        guard interval.isFinite, interval >= 1000 else { return }
        let milliseconds = Int64(min(interval, 300_000))
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(milliseconds)) }
                catch { return }
                guard let self, generation == self.generation else { return }
                do {
                    try await Self.send(
                        ["op": 1, "d": self.lastSequence as Any? ?? NSNull()], on: task
                    )
                } catch { return }
            }
        }
    }

    private static func send(_ payload: [String: Any], on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { return }
        // Never log either the payload or the resulting WebSocket frames.
        try await task.send(.string(text))
    }
}
