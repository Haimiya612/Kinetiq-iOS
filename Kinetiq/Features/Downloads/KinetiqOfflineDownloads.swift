import SwiftUI
import AVFoundation
import AVKit
import Foundation
import CryptoKit
import Combine
import UserNotifications
import UIKit

// MARK: - Offline contract (Batch 06K.10B)

enum KinetiqOfflineFormat: String, Codable {
    case file
    case hls
}

enum KinetiqOfflineState: String, Codable {
    case queued, downloading, paused, ready, failed
}

enum KinetiqOfflineQuality: String, Codable, CaseIterable, Identifiable {
    case original = "Original"
    case high = "High"
    case balanced = "Balanced"
    case saver = "Storage Saver"
    case custom = "Custom"

    var id: String { rawValue }
}

struct KinetiqSavedSubtitleTrack: Codable {
    let label: String
    let language: String?
    let format: String?
    let localPath: String
    let bytes: Int64
}

struct KinetiqOfflineEntry: Identifiable, Codable {
    let id: String
    let sourceID: String
    let sourceName: String
    let animeID: String
    let animeTitle: String
    let episodeID: String
    let episodeNumber: String
    var episodeTitle: String? = nil
    let language: String
    let artworkURL: String?
    let format: KinetiqOfflineFormat
    let quality: String
    let createdAt: Date
    var state: KinetiqOfflineState
    var progress: Double
    var localPath: String?
    var bytes: Int64
    var resumeSeconds: Double
    var error: String?
    var subtitleTracks: [KinetiqSavedSubtitleTrack] = []

    static func identity(sourceID: String, animeID: String,
                         episodeID: String, language: String) -> String {
        let text = [sourceID, animeID, episodeID, language.lowercased()]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct KinetiqOfflineRequest {
    let sourceID: String
    let sourceName: String
    let anime: ModuleAnimeItem
    let episode: ModuleAnimeEpisode
    let language: String
    let stream: ModuleResolvedStream
    let quality: KinetiqOfflineQuality
    let variant: ModuleVideoQualityOption?
    let wifiOnly: Bool
}

enum KinetiqOfflineEligibility {
    /// No special module manifest flag is required. If the installed module
    /// resolves a native playable file or HLS VOD, offer the download action.
    /// A web embed still needs a source-native direct stream before AVFoundation
    /// can persist it.
    static func format(for stream: ModuleResolvedStream) -> KinetiqOfflineFormat? {
        guard stream.url.scheme?.lowercased() == "https",
              stream.url.user == nil, stream.url.password == nil,
              stream.url.host != nil, !stream.isWebEmbed else { return nil }
        // Source adapters may label a direct stream using a MIME type with
        // parameters (for example, video/mp4; codecs=...). Treat the actual
        // container as authoritative without requiring manifest opt-in.
        let declared = (stream.streamType.components(separatedBy: ";").first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ext = stream.url.pathExtension.lowercased()
        if ext == "m3u8" || ["hls", "m3u8", "application/vnd.apple.mpegurl", "application/x-mpegurl"].contains(declared) {
            return .hls
        }
        if ["mp4", "mov", "m4v"].contains(ext) ||
            ["mp4", "video/mp4", "mov", "m4v", "video/quicktime", "video/x-m4v"].contains(declared) {
            return .file
        }
        return nil
    }

    /// AVFoundation can use some source-provided request context when opening
    /// HLS, although iOS does not guarantee that custom headers reach every
    /// segment or alternate rendition. Normal player behavior is unchanged.
    static func hlsAsset(for stream: ModuleResolvedStream) -> AVURLAsset {
        var options: [String: Any] = [:]
        if !stream.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
        }
        if let userAgent = stream.headers.first(where: {
            $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame
        })?.value {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        if !stream.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }) {
            let cookies = stream.cookies.compactMap { cookie in
                HTTPCookie(properties: [
                    .name: cookie.name, .value: cookie.value,
                    .domain: cookie.domain, .path: cookie.path,
                    .secure: cookie.isSecure ? "TRUE" : "FALSE"
                ])
            }
            if !cookies.isEmpty { options[AVURLAssetHTTPCookiesKey] = cookies }
        }
        return AVURLAsset(url: stream.url, options: options.isEmpty ? nil : options)
    }

    static func selectedVariant(_ options: [ModuleVideoQualityOption],
                                quality: KinetiqOfflineQuality,
                                customID: String?) -> ModuleVideoQualityOption? {
        guard !options.isEmpty else { return nil }
        let sorted = options.sorted { $0.width * $0.height < $1.width * $1.height }
        switch quality {
        case .original: return nil
        case .high: return sorted.last
        case .balanced: return sorted[sorted.count / 2]
        case .saver: return sorted.first
        case .custom: return sorted.first(where: { $0.id == customID })
        }
    }
}

/// Uses only source-declared episode duration and HLS peak bitrate.
/// MP4 and missing metadata intentionally report unknown rather than invent
/// a precise download size. Actual HLS/package size varies by selected tracks.
enum KinetiqOfflineSizeEstimate {
    static func approximateBytes(minutes: Int?, peakBitRate: Double?) -> Int64? {
        guard let minutes, (1...600).contains(minutes), let peakBitRate,
              peakBitRate.isFinite, peakBitRate >= 10_000,
              peakBitRate <= 1_000_000_000 else { return nil }
        let bytes = Double(minutes) * 60 * peakBitRate / 8
        guard bytes > 0, bytes < Double(Int64.max) else { return nil }
        return Int64(bytes)
    }
}

/// A finished transfer must have a real local video and every caption that was
/// promised at enqueue time. Never silently hide missing sidecar tracks.
enum KinetiqOfflineFileAudit {
    static func failureReason(for entry: KinetiqOfflineEntry,
                              files: FileManager = .default) -> String? {
        guard let path = entry.localPath, !path.isEmpty else {
            return "The saved video is no longer on this device. Reopen the episode to download it again."
        }
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "The saved video is no longer on this device. Reopen the episode to download it again."
        }
        switch entry.format {
        case .file:
            guard !isDirectory.boolValue,
                  let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
                return "The saved video file cannot be opened. Reopen the episode to download it again."
            }
            let prefix = (try? handle.read(upToCount: 8)) ?? Data()
            try? handle.close()
            guard prefix.count == 8,
                  ["ftyp", "moov", "free", "wide", "mdat"]
                      .contains(String(decoding: prefix[4..<8], as: UTF8.self)) else {
                return "The saved video is incomplete or damaged. Reopen the episode to download it again."
            }
        case .hls:
            guard isDirectory.boolValue,
                  let enumerator = files.enumerator(at: URL(fileURLWithPath: path),
                       includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return "The downloaded HLS package is missing. Reopen the episode to download it again."
            }
            var containsContent = false
            for case let child as URL in enumerator {
                guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
                if values.isRegularFile == true, (values.fileSize ?? 0) > 0 {
                    containsContent = true
                    break
                }
            }
            guard containsContent else {
                return "The downloaded HLS package is empty. Reopen the episode to download it again."
            }
        }
        for subtitle in entry.subtitleTracks {
            guard let attrs = try? files.attributesOfItem(atPath: subtitle.localPath),
                  (attrs[.type] as? FileAttributeType) == .typeRegular,
                  (attrs[.size] as? NSNumber)?.int64Value == subtitle.bytes,
                  subtitle.bytes > 0 else {
                return "A saved subtitle track is missing or incomplete. Reopen the episode to download the complete version."
            }
        }
        return nil
    }
}

/// Queue ordering is persisted in the existing downloads index. Only waiting
/// transfers can be rearranged; active native background tasks are untouched.
enum KinetiqOfflineQueueOrder {
    static func moved(_ source: [KinetiqOfflineEntry], id: String,
                      towardFront: Bool) -> [KinetiqOfflineEntry] {
        let waiting = source.indices.filter { source[$0].state == .queued }
        guard let current = waiting.firstIndex(where: { source[$0].id == id }) else { return source }
        let destination = towardFront ? current - 1 : current + 1
        guard waiting.indices.contains(destination) else { return source }
        var entries = source
        entries.swapAt(waiting[current], waiting[destination])
        return entries
    }
}

/// Per-title retention budget is keyed by hashed source/title identifiers.
/// This stores no streaming URLs, request headers or authentication secrets.
enum KinetiqOfflineSeriesBudget {
    private static let storageKey = "kinetiq.offline.seriesBudget.v1"
    static let options = [0, 1, 2, 5, 10, 20]
    static func key(sourceID: String, animeID: String) -> String {
        let text = "\(sourceID.utf8.count):\(sourceID)|\(animeID.utf8.count):\(animeID)"
        return SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    static func limit(sourceID: String, animeID: String,
                      defaults: UserDefaults = .standard) -> Int {
        let values = defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        let value = values[key(sourceID: sourceID, animeID: animeID)] ?? 0
        return options.contains(value) ? value : 0
    }
    static func setLimit(_ gb: Int, sourceID: String, animeID: String,
                         defaults: UserDefaults = .standard) {
        guard options.contains(gb) else { return }
        var values = defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        let name = key(sourceID: sourceID, animeID: animeID)
        if gb == 0 { values.removeValue(forKey: name) }
        else { values[name] = gb }
        defaults.set(values, forKey: storageKey)
    }
}

// MARK: - Persistent background-download coordinator

/// Only non-secret identifiers, metadata and local filesystem paths are
/// persisted. Stream URLs, tokens, headers and cookies remain memory-only.
@MainActor
final class KinetiqOfflineDownloadStore: NSObject, ObservableObject {
    static let shared = KinetiqOfflineDownloadStore()

    @Published private(set) var entries: [KinetiqOfflineEntry] = []

    @AppStorage("kinetiq.offline.wifiOnly") var wifiOnly = true
    @AppStorage("kinetiq.offline.concurrent") var maximumActive = 2
    @AppStorage("kinetiq.offline.storageLimitGB") var storageLimitGB = 20
    @AppStorage("kinetiq.offline.notifyCompletion") var notifyCompletion = true
    @AppStorage("kinetiq.offline.chargingOnly") var chargingOnly = false
    @AppStorage("kinetiq.offline.nightOnly") var nightOnly = false

    private let directWiFiID = "com.kinetiq.offline.direct.wifi.v1"
    private let directCellID = "com.kinetiq.offline.direct.cell.v1"
    private let hlsWiFiID = "com.kinetiq.offline.hls.wifi.v1"
    private let hlsCellID = "com.kinetiq.offline.hls.cell.v1"

    private var sessions: [String: URLSession] = [:]
    // Retain the concrete HLS session. Looking up an AVAssetDownloadURLSession
    // through the erased URLSession dictionary should never be needed when
    // starting an offline asset task.
    private var hlsSessions: [String: AVAssetDownloadURLSession] = [:]
    private var tasks: [String: URLSessionTask] = [:]
    private var activeRequests: [String: KinetiqOfflineRequest] = [:]
    private var backgroundCompletions: [String: () -> Void] = [:]
    private var pendingRecoverySessions = 0

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KinetiqOffline/v1", isDirectory: true)
    }
    private var indexURL: URL { supportDirectory.appendingPathComponent("downloads.json") }

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: supportDirectory,
                                                 withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = supportDirectory
        try? directory.setResourceValues(values)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([KinetiqOfflineEntry].self, from: data) {
            entries = saved.prefix(1_000).map { record in
                var entry = record
                if entry.state == .ready,
                   let failure = KinetiqOfflineFileAudit.failureReason(for: entry) {
                    entry.state = .failed
                    entry.error = failure
                }
                return entry
            }
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.startNextQueued() }
            }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.startNextQueued() }
            }
        configureSessions()
        reconnectTasks()
    }

    private func configureSessions() {
        for (identifier, cellular, hls) in [
            (directWiFiID, false, false), (directCellID, true, false),
            (hlsWiFiID, false, true), (hlsCellID, true, true)
        ] {
            let config = URLSessionConfiguration.background(withIdentifier: identifier)
            config.allowsCellularAccess = cellular
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.httpMaximumConnectionsPerHost = 3
            if hls {
                let session = AVAssetDownloadURLSession(
                    configuration: config, assetDownloadDelegate: self,
                    delegateQueue: .main
                )
                hlsSessions[identifier] = session
                sessions[identifier] = session
            } else {
                sessions[identifier] = URLSession(
                    configuration: config, delegate: self, delegateQueue: .main
                )
            }
        }
    }

    private func reconnectTasks() {
        let sessionsToCheck = Array(sessions.values)
        pendingRecoverySessions = sessionsToCheck.count
        for session in sessionsToCheck {
            session.getAllTasks { [weak self] recovered in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for task in recovered {
                        guard let id = task.taskDescription,
                              self.entries.contains(where: { $0.id == id }) else { continue }
                        self.tasks[id] = task
                    }
                    self.pendingRecoverySessions -= 1
                    if self.pendingRecoverySessions == 0 {
                        self.reconcileRecoveredTasks()
                    }
                }
            }
        }
    }

    private func reconcileRecoveredTasks() {
        for index in entries.indices {
            let entry = entries[index]
            if entry.state == .downloading || entry.state == .queued || entry.state == .paused {
                guard let task = tasks[entry.id] else {
                    // A completed MP4 can already be on disk when the OS has
                    // retired its background task but the completion callback
                    // was never delivered to the app process.
                    if entry.format == .file {
                        var candidate = entry
                        if candidate.localPath == nil {
                            let file = supportDirectory.appendingPathComponent("files")
                                .appendingPathComponent(entry.id).appendingPathExtension("mp4")
                            candidate.localPath = file.path
                        }
                        if KinetiqOfflineFileAudit.failureReason(for: candidate) == nil,
                           let path = candidate.localPath {
                            entries[index].localPath = path
                            let file = URL(fileURLWithPath: path)
                            let mediaBytes = Int64((try? file.resourceValues(
                                forKeys: [.fileSizeKey]).fileSize) ?? 0)
                            entries[index].bytes = mediaBytes + candidate.subtitleTracks.reduce(0) {
                                $0 + $1.bytes
                            }
                            entries[index].progress = 1
                            entries[index].state = .ready
                            entries[index].error = nil
                            continue
                        }
                    }
                    entries[index].state = .failed
                    entries[index].error = "Background transfer no longer exists. Reopen the episode to retry."
                    continue
                }
                if entry.state == .paused {
                    task.suspend()
                } else if task.state == .suspended {
                    entries[index].state = .queued
                }
            }
        }
        persist()
        startNextQueued()
    }

    func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard sessions[identifier] != nil else { completion(); return }
        backgroundCompletions[identifier] = completion
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Kinetiq offline index persistence: \(error.localizedDescription)")
            #endif
        }
    }

    private func update(_ id: String, _ edit: (inout KinetiqOfflineEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        edit(&entries[index])
        persist()
    }

    var totalBytes: Int64 {
        entries.filter { $0.state == .ready }.reduce(0) { $0 + max(0, $1.bytes) }
    }

    func entry(sourceID: String, animeID: String, episodeID: String,
               language: String) -> KinetiqOfflineEntry? {
        let id = KinetiqOfflineEntry.identity(sourceID: sourceID, animeID: animeID,
                                               episodeID: episodeID, language: language)
        return entries.first(where: { $0.id == id })
    }

    func isBackgroundSessionAvailable(format: KinetiqOfflineFormat,
                                      wifiOnly: Bool) -> Bool {
        switch format {
        case .file:
            return sessions[wifiOnly ? directWiFiID : directCellID] != nil
        case .hls:
            return hlsSessions[wifiOnly ? hlsWiFiID : hlsCellID] != nil
        }
    }

    func enqueue(_ request: KinetiqOfflineRequest) async throws {
        guard let format = KinetiqOfflineEligibility.format(for: request.stream) else {
            throw OfflineDownloadError.unsupportedStream
        }
        let id = KinetiqOfflineEntry.identity(sourceID: request.sourceID,
            animeID: request.anime.id, episodeID: request.episode.id,
            language: request.language)
        if let existing = entries.first(where: { $0.id == id }),
           existing.state != .failed { throw OfflineDownloadError.alreadyExists }

        let capacity = Int64(max(1, storageLimitGB)) * 1_000_000_000
        guard totalBytes < capacity else { throw OfflineDownloadError.storageLimit }
        let perTitle = KinetiqOfflineSeriesBudget.limit(
            sourceID: request.sourceID, animeID: request.anime.id)
        if perTitle > 0 {
            let used = entries.filter {
                $0.state == .ready && $0.sourceID == request.sourceID &&
                $0.animeID == request.anime.id
            }.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
            guard used < Int64(perTitle) * 1_000_000_000 else {
                throw OfflineDownloadError.storageLimit
            }
        }
        let available = try? supportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let available, available < 250_000_000 { throw OfflineDownloadError.lowSpace }

        let title = String(request.anime.title.prefix(200))
        let sessionID = format == .hls
            ? (request.wifiOnly ? hlsWiFiID : hlsCellID)
            : (request.wifiOnly ? directWiFiID : directCellID)
        // Validate before downloading subtitles or committing a failed entry.
        // A direct background session and an HLS asset session are different
        // services; only the latter can create AVAssetDownloadTasks.
        guard isBackgroundSessionAvailable(format: format, wifiOnly: request.wifiOnly) else {
            throw OfflineDownloadError.sessionUnavailable
        }
        // Capture every source-advertised external SRT/VTT track before
        // declaring this episode queued. An incomplete set is an error,
        // never a silently successful download.
        let captions = try await saveAllSubtitles(from: request, id: id)
        let record = KinetiqOfflineEntry(
            id: id, sourceID: String(request.sourceID.prefix(1200)),
            sourceName: String(request.sourceName.prefix(120)),
            animeID: String(request.anime.id.prefix(1500)), animeTitle: title,
            episodeID: String(request.episode.id.prefix(1500)),
            episodeNumber: String(request.episode.number.prefix(80)),
            episodeTitle: KinetiqEpisodeMetadataMatching.displayTitle(
                request.episode.title, episodeNumber: request.episode.number),
            language: request.language, artworkURL: request.anime.imageURL?.absoluteString,
            format: format,
            quality: request.variant.map { "\(request.quality.rawValue) · \($0.title)" } ?? "Original source",
            createdAt: .now, state: .queued, progress: 0,
            localPath: nil, bytes: 0, resumeSeconds: 0, error: nil,
            subtitleTracks: captions
        )
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index] = record
        } else {
            entries.append(record)
        }
        activeRequests[id] = request

        do {
            let task: URLSessionTask
            switch format {
            case .file:
                var urlRequest = URLRequest(url: request.stream.url)
                urlRequest.allowsCellularAccess = !request.wifiOnly
                for (name, value) in request.stream.headers where
                    !name.contains("\r") && !name.contains("\n") &&
                    !value.contains("\r") && !value.contains("\n") &&
                    name.count <= 100 && value.count <= 4_096 {
                    urlRequest.setValue(value, forHTTPHeaderField: name)
                }
                if !request.stream.cookies.isEmpty {
                    let host = request.stream.url.host?.lowercased() ?? ""
                    let safe = request.stream.cookies.filter { $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host }
                    if !safe.isEmpty {
                        urlRequest.setValue(safe.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                                            forHTTPHeaderField: "Cookie")
                    }
                }
                guard let session = sessions[sessionID] else {
                    throw OfflineDownloadError.sessionUnavailable
                }
                task = session.downloadTask(with: urlRequest)
            case .hls:
                guard let hls = hlsSessions[sessionID] else {
                    throw OfflineDownloadError.sessionUnavailable
                }
                let asset = KinetiqOfflineEligibility.hlsAsset(for: request.stream)
                let configuration = AVAssetDownloadConfiguration(
                    asset: asset,
                    title: "\(title) · Episode \(request.episode.number)"
                )
                // Download the advertised HLS audio/legible combinations,
                // not just the player's initially selected language.
                let mediaSelections = try await asset.load(.allMediaSelections)
                guard mediaSelections.count <= 100 else {
                    throw OfflineDownloadError.tooManyHLSSelections
                }
                if !mediaSelections.isEmpty {
                    configuration.primaryContentConfiguration.mediaSelections = mediaSelections
                }
                if let variant = request.variant, let rate = variant.peakBitRate,
                   rate > 0, rate.isFinite {
                    configuration.primaryContentConfiguration.variantQualifiers = [
                        AVAssetVariantQualifier(predicate: NSPredicate(format: "peakBitRate <= %f", rate))
                    ]
                }
                task = hls.makeAssetDownloadTask(downloadConfiguration: configuration)
            }
            task.taskDescription = id
            tasks[id] = task
            persist()
            startNextQueued()
        } catch {
            activeRequests.removeValue(forKey: id)
            discardSubtitles(id)
            update(id) { $0.state = .failed; $0.error = error.localizedDescription }
            throw error
        }
    }

    private func saveAllSubtitles(from request: KinetiqOfflineRequest,
                                  id: String) async throws -> [KinetiqSavedSubtitleTrack] {
        let tracks = request.stream.subtitles
        guard tracks.count <= 24 else { throw OfflineDownloadError.tooManySubtitles }
        guard !tracks.isEmpty else { return [] }
        let root = supportDirectory.appendingPathComponent("subtitles", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            var folder = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        var saved: [KinetiqSavedSubtitleTrack] = []
        do {
            for (index, track) in tracks.enumerated() {
                try Task.checkCancellation()
                guard ModuleSubtitleRequestPolicy.isAllowed(track.url) else {
                    throw OfflineDownloadError.invalidSubtitleURL
                }
                let urlRequest = try ModuleSubtitleRequestPolicy.request(for: track)
                // Follow normal HTTPS subtitle redirects, dropping credentials
                // if a CDN handoff crosses the original subtitle origin.
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.timeoutIntervalForResource = 45
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (stream, response) = try await session.bytes(for: urlRequest,
                    delegate: KinetiqOfflineCaptionRedirectDelegate(track: track))
                guard let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode),
                      response.expectedContentLength <= Int64(ModuleSubtitleLoader.maximumBytes) else {
                    throw OfflineDownloadError.invalidSubtitles
                }
                var bytes = Data()
                for try await byte in stream {
                    try Task.checkCancellation()
                    guard bytes.count < ModuleSubtitleLoader.maximumBytes else {
                        throw OfflineDownloadError.invalidSubtitles
                    }
                    bytes.append(byte)
                }
                _ = try ModuleSubtitleLoader.parse(data: bytes,
                    format: track.format, contentType: response.mimeType)
                let format = track.format ?? ExternalSubtitleFormat(
                    fileExtension: track.url.pathExtension)
                let ext = format == .srt ? "srt" : "vtt"
                let file = root.appendingPathComponent(String(format: "%02d", index))
                    .appendingPathExtension(ext)
                try bytes.write(to: file, options: .atomic)
                saved.append(KinetiqSavedSubtitleTrack(
                    label: String(track.label.prefix(120)),
                    language: track.language.map { String($0.prefix(50)) },
                    format: format?.rawValue,
                    localPath: file.path, bytes: Int64(bytes.count)))
            }
        } catch {
            discardSubtitles(id)
            throw error
        }
        return saved
    }

    private func discardSubtitles(_ id: String) {
        guard id.count == 64 else { return }
        let directory = supportDirectory.appendingPathComponent("subtitles")
            .appendingPathComponent(id)
        try? FileManager.default.removeItem(at: directory)
    }

    func subtitleTracks(for entry: KinetiqOfflineEntry) -> [ModuleRemoteSubtitleTrack] {
        entry.subtitleTracks.compactMap { saved in
            guard FileManager.default.fileExists(atPath: saved.localPath) else { return nil }
            return ModuleRemoteSubtitleTrack(url: URL(fileURLWithPath: saved.localPath),
                label: saved.label, language: saved.language,
                format: saved.format.flatMap(ExternalSubtitleFormat.init(rawValue:)),
                headers: [:])
        }
    }

    var queuedCount: Int { entries.filter { $0.state == .queued }.count }

    func canMoveQueued(_ id: String, towardFront: Bool) -> Bool {
        let waiting = entries.filter { $0.state == .queued }
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return false }
        return towardFront ? index > 0 : index < waiting.count - 1
    }

    func moveQueued(_ id: String, towardFront: Bool) {
        guard canMoveQueued(id, towardFront: towardFront) else { return }
        entries = KinetiqOfflineQueueOrder.moved(entries, id: id, towardFront: towardFront)
        persist()
    }

    var pendingPolicyExplanation: String? {
        if chargingOnly {
            let battery = UIDevice.current.batteryState
            if battery != .charging && battery != .full {
                return "Queued transfers will start when the iPhone is charging and Kinetiq is running. Active iOS background transfers are not interrupted."
            }
        }
        if nightOnly {
            let hour = Calendar.current.component(.hour, from: .now)
            if hour < 22 && hour >= 7 {
                return "New transfers wait until 22:00–07:00 while Kinetiq is running. iOS may not wake the app at the scheduled time."
            }
        }
        return nil
    }

    /// Re-evaluate policy after the user changes download settings.
    func refreshQueue() { startNextQueued() }

    private func startNextQueued() {
        if chargingOnly {
            let battery = UIDevice.current.batteryState
            guard battery == .charging || battery == .full else { return }
        }
        if nightOnly {
            let hour = Calendar.current.component(.hour, from: .now)
            guard hour >= 22 || hour < 7 else { return }
        }
        var active = entries.filter { $0.state == .downloading }.count
        let limit = max(1, min(4, maximumActive))
        for entry in entries where entry.state == .queued && active < limit {
            guard let task = tasks[entry.id] else { continue }
            task.resume()
            update(entry.id) { $0.state = .downloading }
            active += 1
        }
    }

    func pause(_ id: String) {
        guard let task = tasks[id],
              entries.first(where: { $0.id == id })?.state == .downloading else { return }
        task.suspend()
        update(id) { $0.state = .paused }
        startNextQueued()
    }

    func resume(_ id: String) {
        guard tasks[id] != nil,
              entries.first(where: { $0.id == id })?.state == .paused else { return }
        update(id) { $0.state = .queued }
        startNextQueued()
    }

    func canRetry(_ id: String) -> Bool { activeRequests[id] != nil }

    func retry(_ id: String) {
        guard let request = activeRequests[id],
              entries.first(where: { $0.id == id })?.state == .failed else { return }
        Task { try? await enqueue(request) }
    }

    func remove(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        activeRequests.removeValue(forKey: id)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries.remove(at: index)
            if let path = entry.localPath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
            discardSubtitles(id)
            persist()
        }
        startNextQueued()
    }

    func removeCompleted() {
        for id in entries.filter({ $0.state == .ready }).map(\.id) { remove(id) }
    }

    /// An on-device audit is useful after a Files-app cleanup or an interrupted
    /// iOS restore. It checks bytes on disk without contacting a source module.
    @discardableResult
    func validateSavedDownloads() -> Int {
        var invalidCount = 0
        for index in entries.indices where entries[index].state == .ready {
            if let failure = KinetiqOfflineFileAudit.failureReason(for: entries[index]) {
                entries[index].state = .failed
                entries[index].error = failure
                invalidCount += 1
            }
        }
        if invalidCount > 0 { persist() }
        return invalidCount
    }

    func playbackURL(for entry: KinetiqOfflineEntry) -> URL? {
        guard entry.state == .ready, let path = entry.localPath else { return nil }
        if let failure = KinetiqOfflineFileAudit.failureReason(for: entry) {
            update(entry.id) { $0.state = .failed; $0.error = failure }
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func savePlaybackPosition(_ seconds: Double, for id: String) {
        guard seconds.isFinite, seconds >= 0 else { return }
        update(id) { $0.resumeSeconds = seconds }
    }

    private func handleProgress(_ id: String, progress: Double) {
        guard progress.isFinite else { return }
        guard let existing = entries.first(where: { $0.id == id }),
              existing.state == .downloading,
              progress > existing.progress,
              progress - existing.progress >= 0.01 || progress >= 1 else { return }
        update(id) {
            guard $0.state == .downloading else { return }
            let fraction = min(1, max(0, progress))
            $0.progress = max($0.progress, fraction)
        }
    }

    private func handleFile(_ id: String, path: String, size: Int64) {
        update(id) { $0.localPath = path; $0.bytes = max(0, size) }
    }

    private func handleHLSLocation(_ id: String, url: URL) {
        update(id) { $0.localPath = url.path }
    }

    private func handleCompletion(_ id: String, error: Error?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var old = entries[index]
        // The synchronous file move and URLSession completion delegate can
        // schedule actor updates in either order. Resolve from the known,
        // opaque destination to avoid marking a saved file missing.
        if old.format == .file, old.localPath == nil {
            let candidate = supportDirectory.appendingPathComponent("files")
                .appendingPathComponent(id).appendingPathExtension("mp4")
            if FileManager.default.fileExists(atPath: candidate.path) {
                old.localPath = candidate.path
                old.bytes = Int64((try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                entries[index].localPath = old.localPath
                entries[index].bytes = old.bytes
            }
        }
        guard old.state != .ready else { return }
        tasks.removeValue(forKey: id)
        if let error {
            entries[index].state = .failed
            entries[index].error = (error as NSError).code == NSURLErrorCancelled
                ? "Download canceled."
                : "Download interrupted. Reopen the episode to retry if its link expired."
        } else if let path = old.localPath,
                  KinetiqOfflineFileAudit.failureReason(for: old) == nil {
            entries[index].state = .ready
            entries[index].progress = 1
            entries[index].error = nil
            if old.format == .hls {
                entries[index].bytes = directorySize(at: URL(fileURLWithPath: path))
            }
            entries[index].bytes += entries[index].subtitleTracks.reduce(0) { $0 + $1.bytes }
            if notifyCompletion { postCompletionNotification(for: entries[index]) }
        } else {
            entries[index].state = .failed
            entries[index].error = "The transfer finished without a saved playable file."
        }
        if entries[index].state == .ready { activeRequests.removeValue(forKey: id) }
        persist()
        startNextQueued()
    }

    private func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
            includingPropertiesForKeys: Array(keys)) else { return 0 }
        var size: Int64 = 0
        for case let child as URL in enumerator {
            if let info = try? child.resourceValues(forKeys: keys), info.isRegularFile == true {
                size += Int64(info.fileSize ?? 0)
            }
        }
        return size
    }

    private func postCompletionNotification(for entry: KinetiqOfflineEntry) {
        let content = UNMutableNotificationContent()
        content.title = "Available offline"
        content.body = "\(entry.animeTitle) · Episode \(entry.episodeNumber) is ready to watch."
        content.userInfo = ["animeTitle": entry.animeTitle,
                            "episodeNumber": entry.episodeNumber]
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "kinetiq.offline.\(entry.id)", content: content, trigger: nil
        ))
    }
}

enum OfflineDownloadError: LocalizedError {
    case unsupportedStream, alreadyExists, lowSpace, storageLimit, sessionUnavailable
    case tooManySubtitles, invalidSubtitleURL, invalidSubtitles, tooManyHLSSelections

    var errorDescription: String? {
        switch self {
        case .unsupportedStream: "This episode has no directly downloadable MP4 or HLS stream. Try another server."
        case .alreadyExists: "This episode is already in Downloads."
        case .lowSpace: "Less than 250 MB is available. Free storage before downloading."
        case .storageLimit: "Your Kinetiq download storage limit has been reached."
        case .sessionUnavailable: "The background download service is unavailable."
        case .tooManySubtitles: "This episode has more than 24 external subtitle tracks; none were omitted."
        case .invalidSubtitleURL: "A subtitle URL is not a supported HTTPS source. No tracks were omitted."
        case .invalidSubtitles: "A source subtitle could not be safely downloaded or parsed."
        case .tooManyHLSSelections: "The HLS stream advertises too many media selections to save safely."
        }
    }
}

/// The remote subtitle controller uses this same-origin credential boundary.
private final class KinetiqOfflineCaptionRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let track: ModuleRemoteSubtitleTrack

    init(track: ModuleRemoteSubtitleTrack) { self.track = track }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url else { completionHandler(nil); return }
        completionHandler(try? ModuleSubtitleRequestPolicy.request(for: track, destination: url))
    }
}

// MARK: - Background delegates

extension KinetiqOfflineDownloadStore: URLSessionDownloadDelegate, AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }
        Task { @MainActor in
            self.handleProgress(id, progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, id.count == 64,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return }
        // Temporary URLSession files are deleted when this callback returns.
        // The move must occur synchronously, before the MainActor handoff.
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              !(response.mimeType ?? "").lowercased().contains("text/html") else { return }
        do {
            let file = try FileHandle(forReadingFrom: location)
            let beginning = try file.read(upToCount: 16) ?? Data()
            try? file.close()
            guard beginning.count >= 8,
                  ["ftyp", "moov", "free", "wide", "mdat"]
                    .contains(String(decoding: beginning[4..<8], as: UTF8.self)) else { return }
            let root = FileManager.default.urls(for: .applicationSupportDirectory,
                 in: .userDomainMask)[0].appendingPathComponent("KinetiqOffline/v1/files", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            var folder = root
            try? folder.setResourceValues(attributes)
            let target = root.appendingPathComponent(id).appendingPathExtension("mp4")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: location, to: target)
            let length = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            Task { @MainActor in self.handleFile(id, path: target.path, size: length) }
        } catch {
            Task { @MainActor in
                self.handleCompletion(id, error: error)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                assetDownloadTask: AVAssetDownloadTask,
                                willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        Task { @MainActor in self.handleHLSLocation(id, url: location) }
    }

    nonisolated func urlSession(_ session: URLSession,
                                assetDownloadTask: AVAssetDownloadTask,
                                didLoad timeRange: CMTimeRange,
                                totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                                timeRangeExpectedToLoad expectedTimeRange: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let total = CMTimeGetSeconds(expectedTimeRange.duration)
        guard total.isFinite, total > 0 else { return }
        let seconds = loadedTimeRanges.reduce(0.0) {
            $0 + max(0, CMTimeGetSeconds($1.timeRangeValue.duration))
        }
        Task { @MainActor in self.handleProgress(id, progress: seconds / total) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor in self.handleCompletion(id, error: error) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        Task { @MainActor in
            let completion = self.backgroundCompletions.removeValue(forKey: identifier)
            completion?()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest,
                                completionHandler: @escaping (URLRequest?) -> Void) {
        // Accept HTTPS CDN redirects without an extra manifest allowlist.
        // Never forward source credentials to a different host.
        guard let original = task.originalRequest?.url,
              request.url?.scheme?.lowercased() == "https",
              let destination = request.url?.host?.lowercased(),
              request.url?.user == nil, request.url?.password == nil else {
            completionHandler(nil)
            return
        }
        var next = request
        if destination != original.host?.lowercased() {
            for header in ["Authorization", "Cookie", "Referer", "Origin", "X-Api-Key"] {
                next.setValue(nil, forHTTPHeaderField: header)
            }
        }
        completionHandler(next)
    }
}
