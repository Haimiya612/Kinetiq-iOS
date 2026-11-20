import Foundation
import Network

// MARK: - Native Picture-in-Picture Subtitle Bridge (experimental)

/// Builds an HLS presentation with a separate WebVTT rendition. The video
/// remains on its original HTTPS server; only three temporary manifests/text
/// resources are served from an app-private loopback HTTP listener.
///
/// This is deliberately opt-in: iOS/AVFoundation must still prove that the
/// synthetic rendition appears in media selection and system PiP on device.
/// Never use it for DRM, live HLS, browser embeds or non-HLS video.
enum NativeHLSSubtitleBridgeError: LocalizedError {
    case unsupportedStream
    case unsafeManifest
    case nonVOD
    case invalidSubtitle
    case listenerUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedStream: "Native PiP subtitles currently require an HTTPS HLS video stream."
        case .unsafeManifest: "The source playlist could not be safely interpreted."
        case .nonVOD: "Native PiP subtitles currently support on-demand HLS episodes, not live streams."
        case .invalidSubtitle: "No usable subtitle cues were provided."
        case .listenerUnavailable: "The private local subtitle service was unavailable."
        }
    }
}

struct NativeHLSSubtitleManifest {
    let master: String
    let mediaURL: URL
    let duration: Double

    static let trackName = "Kinetiq External"

    static func create(
        source: String, sourceURL: URL,
        subtitleURL: URL, language: String
    ) throws -> Self {
        guard source.utf8.count <= 524_288,
              source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U"),
              sourceURL.scheme?.lowercased() == "https" else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }

        let lines = source.components(separatedBy: .newlines)
        guard !lines.contains(where: { $0.hasPrefix("#EXT-X-SESSION-KEY:") }) else {
            throw NativeHLSSubtitleBridgeError.unsupportedStream
        }
        let isMaster = lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:") }
        guard isMaster else {
            // A media playlist can be wrapped with a new multivariant playlist.
            let duration = try mediaDuration(source)
            let media = mediaTag(group: "kinetiq-external", subtitleURL: subtitleURL,
                                 language: language)
            let master = [
                "#EXTM3U", "#EXT-X-VERSION:3", media,
                "#EXT-X-STREAM-INF:BANDWIDTH=8000000,SUBTITLES=\"kinetiq-external\"",
                sourceURL.absoluteString
            ].joined(separator: "\n") + "\n"
            return Self(master: master, mediaURL: sourceURL, duration: duration)
        }

        var rewritten: [String] = []
        var groups = Set<String>()
        var nextIsVariant = false
        var firstVariant: URL?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                nextIsVariant = true
                let attr = #"SUBTITLES="([^"]+)""#
                if let range = line.range(of: attr, options: .regularExpression) {
                    let matched = line[range]
                    if let begin = matched.firstIndex(of: "\""),
                       let end = matched.lastIndex(of: "\""), begin < end {
                        groups.insert(String(matched[matched.index(after: begin)..<end]))
                    }
                    rewritten.append(line)
                } else {
                    groups.insert("kinetiq-external")
                    rewritten.append(line + ",SUBTITLES=\"kinetiq-external\"")
                }
                continue
            }
            if line.hasPrefix("#") {
                rewritten.append(rewriteAttributeURIs(in: line, relativeTo: sourceURL))
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let absolute = safeAbsolute(line, relativeTo: sourceURL) else {
                    throw NativeHLSSubtitleBridgeError.unsafeManifest
                }
                if nextIsVariant && firstVariant == nil { firstVariant = absolute }
                nextIsVariant = false
                rewritten.append(absolute.absoluteString)
            } else {
                rewritten.append(line)
            }
        }
        guard let mediaURL = firstVariant, !groups.isEmpty else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }
        // The duration is obtained separately from the first media variant.
        let mediaTags = groups.sorted().map {
            mediaTag(group: $0, subtitleURL: subtitleURL, language: language)
        }
        if let index = rewritten.firstIndex(where: { $0 == "#EXTM3U" }) {
            rewritten.insert(contentsOf: mediaTags, at: index + 1)
        } else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }
        return Self(master: rewritten.joined(separator: "\n"), mediaURL: mediaURL, duration: 0)
    }

    static func mediaDuration(_ text: String) throws -> Double {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.contains(where: { $0.hasPrefix("#EXT-X-KEY:") }) else {
            throw NativeHLSSubtitleBridgeError.unsupportedStream
        }
        guard lines.contains("#EXT-X-ENDLIST"),
              lines.contains(where: { $0.hasPrefix("#EXTINF:") }),
              !lines.contains(where: { $0.hasPrefix("#EXT-X-PLAYLIST-TYPE:EVENT") }) else {
            throw NativeHLSSubtitleBridgeError.nonVOD
        }
        var seconds = 0.0
        for line in lines where line.hasPrefix("#EXTINF:") {
            let raw = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first
            guard let raw, let value = Double(raw), value.isFinite, value > 0 else {
                throw NativeHLSSubtitleBridgeError.unsafeManifest
            }
            seconds += value
        }
        guard seconds > 1, seconds < 24 * 60 * 60 else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }
        return seconds
    }

    private static func mediaTag(group: String, subtitleURL: URL, language: String) -> String {
        // The name identifies Kinetiq's temporary track in AVMediaSelection.
        "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(group)\",NAME=\"\(trackName)\",LANGUAGE=\"\(language)\",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,URI=\"\(subtitleURL.absoluteString)\""
    }

    private static func safeAbsolute(_ text: String, relativeTo base: URL) -> URL? {
        guard let result = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines),
                               relativeTo: base)?.absoluteURL,
              result.scheme?.lowercased() == "https",
              result.host != nil, result.user == nil, result.password == nil else {
            return nil
        }
        return result
    }

    private static func rewriteAttributeURIs(in line: String, relativeTo base: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"URI="([^"]+)""#) else { return line }
        var updated = line
        for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
            guard let range = Range(match.range(at: 1), in: updated),
                  let resolved = safeAbsolute(String(updated[range]), relativeTo: base) else {
                continue
            }
            updated.replaceSubrange(range, with: resolved.absoluteString)
        }
        return updated
    }

    static func subtitlePlaylist(url: URL, duration: Double) -> String {
        let rounded = max(1, Int(ceil(duration)))
        return [
            "#EXTM3U", "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(rounded)",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXTINF:\(String(format: "%.3f", duration)),",
            url.absoluteString,
            "#EXT-X-ENDLIST", ""
        ].joined(separator: "\n")
    }

    static func webVTT(cues: [ExternalSubtitleCue], offset: Double, duration: Double) throws -> String {
        guard !cues.isEmpty, duration > 0 else { throw NativeHLSSubtitleBridgeError.invalidSubtitle }
        var result = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0\n\n"
        var accepted = 0
        for cue in cues.prefix(20_000) {
            let start = max(0, cue.startTime - offset)
            let end = min(duration, cue.endTime - offset)
            guard start < end, start.isFinite, end.isFinite else { continue }
            let safeText = String(cue.text.prefix(2_000))
                .replacingOccurrences(of: "-->", with: "→")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n\n", with: "\n")
            guard !safeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result += "\(timestamp(start)) --> \(timestamp(end))\n\(safeText)\n\n"
            accepted += 1
        }
        guard accepted > 0, result.utf8.count <= 2_500_000 else {
            throw NativeHLSSubtitleBridgeError.invalidSubtitle
        }
        return result
    }

    private static func timestamp(_ seconds: Double) -> String {
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        return String(format: "%02d:%02d:%02d.%03d",
                      milliseconds / 3_600_000,
                      (milliseconds / 60_000) % 60,
                      (milliseconds / 1_000) % 60,
                      milliseconds % 1_000)
    }
}

private final class NativeHLSBridgeRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let originTrack: ModuleRemoteSubtitleTrack
    init(originTrack: ModuleRemoteSubtitleTrack) { self.originTrack = originTrack }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              var safe = try? ModuleSubtitleRequestPolicy.request(for: originTrack, destination: url)
        else { completionHandler(nil); return }
        safe.setValue("application/vnd.apple.mpegurl, application/x-mpegURL", forHTTPHeaderField: "Accept")
        completionHandler(safe)
    }
}

/// A single-playback loopback server: no listening on Wi-Fi, no persistent
/// disk files and an unguessable path token. Only fixed GET resources exist.
private final class NativeHLSLoopbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.kinetiq.native-subtitle-bridge")
    private var responses: [String: (String, Data)] = [:]
    let token = UUID().uuidString.lowercased()

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    deinit { listener.cancel() }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            let listener = self.listener
            listener.stateUpdateHandler = { [weak listener] state in
                guard !completed else { return }
                switch state {
                case .ready:
                    completed = true
                    if let port = listener?.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: NativeHLSSubtitleBridgeError.listenerUnavailable)
                    }
                case .failed:
                    completed = true
                    continuation.resume(throwing: NativeHLSSubtitleBridgeError.listenerUnavailable)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { [weak listener] in
                guard !completed else { return }
                completed = true
                listener?.cancel()
                continuation.resume(throwing: NativeHLSSubtitleBridgeError.listenerUnavailable)
            }
            listener.start(queue: queue)
        }
    }

    func install(master: String, subtitles: String, vtt: String) {
        let entries: [String: (String, Data)] = [
            "/\(token)/master.m3u8": ("application/vnd.apple.mpegurl", Data(master.utf8)),
            "/\(token)/subtitles.m3u8": ("application/vnd.apple.mpegurl", Data(subtitles.utf8)),
            "/\(token)/subtitle.vtt": ("text/vtt", Data(vtt.utf8))
        ]
        queue.sync { responses = entries }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let line = request.components(separatedBy: "\r\n").first else {
                connection.cancel()
                return
            }
            let parts = line.split(separator: " ")
            guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD" else {
                self.respond(connection, status: "405 Method Not Allowed", type: "text/plain", data: Data())
                return
            }
            let path = String(parts[1]).components(separatedBy: "?").first ?? ""
            if let (type, payload) = self.responses[path] {
                self.respond(connection, status: "200 OK", type: type, data: payload,
                             sendBody: parts[0] == "GET")
            } else {
                self.respond(connection, status: "404 Not Found", type: "text/plain", data: Data())
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, type: String,
                         data: Data, sendBody: Bool = true) {
        let header = [
            "HTTP/1.1 \(status)", "Content-Type: \(type)",
            "Content-Length: \(data.count)", "Cache-Control: no-store",
            "Connection: close", "", ""
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        if sendBody { payload.append(data) }
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }
}

final class NativeHLSSubtitleBridge {
    let playbackURL: URL
    let trackID: String
    let language: String
    private let server: NativeHLSLoopbackServer

    private init(playbackURL: URL, track: ModuleRemoteSubtitleTrack,
                 server: NativeHLSLoopbackServer) {
        self.playbackURL = playbackURL
        trackID = track.id
        language = KinetiqCaptionLanguage(tag: track.language, name: track.label).tag ?? "und"
        self.server = server
    }

    static func isEligible(_ stream: ModuleResolvedStream) -> Bool {
        !stream.isWebEmbed && stream.url.scheme?.lowercased() == "https" &&
        (stream.url.pathExtension.lowercased() == "m3u8" ||
         ["hls", "m3u8"].contains(stream.streamType.lowercased()))
    }

    static func prepare(
        stream: ModuleResolvedStream,
        track: ModuleRemoteSubtitleTrack,
        offset: Double
    ) async throws -> NativeHLSSubtitleBridge {
        guard isEligible(stream) else { throw NativeHLSSubtitleBridgeError.unsupportedStream }
        async let timeline = ModuleSubtitleLoader.load(track)
        let remoteText = try await fetchManifest(at: stream.url, stream: stream)

        let server = try NativeHLSLoopbackServer()
        let port = try await server.start()
        let base = URL(string: "http://127.0.0.1:\(port)/\(server.token)/")!
        let rendition = base.appendingPathComponent("subtitles.m3u8")
        let subtitleFile = base.appendingPathComponent("subtitle.vtt")
        let masterURL = base.appendingPathComponent("master.m3u8")
        let language = KinetiqCaptionLanguage(tag: track.language, name: track.label).tag ?? "und"
        let manifest = try NativeHLSSubtitleManifest.create(
            source: remoteText, sourceURL: stream.url,
            subtitleURL: rendition, language: language
        )
        let duration: Double
        if manifest.duration > 0 {
            duration = manifest.duration
        } else {
            let mediaText = try await fetchManifest(at: manifest.mediaURL, stream: stream)
            duration = try NativeHLSSubtitleManifest.mediaDuration(mediaText)
        }
        let loadedTimeline = try await timeline
        let cues = loadedTimeline.bridgeCues
        let vtt = try NativeHLSSubtitleManifest.webVTT(cues: cues, offset: offset, duration: duration)
        let playlist = NativeHLSSubtitleManifest.subtitlePlaylist(url: subtitleFile, duration: duration)
        server.install(master: manifest.master, subtitles: playlist, vtt: vtt)
        return NativeHLSSubtitleBridge(playbackURL: masterURL, track: track, server: server)
    }

    private static func fetchManifest(at url: URL, stream: ModuleResolvedStream) async throws -> String {
        let carrier = ModuleRemoteSubtitleTrack(
            url: stream.url, label: "HLS", language: nil, format: nil,
            headers: stream.headers, cookies: stream.cookies
        )
        var request = try ModuleSubtitleRequestPolicy.request(for: carrier, destination: url)
        request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = NativeHLSBridgeRedirectDelegate(originTrack: carrier)
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalURL = http.url, ModuleSubtitleRequestPolicy.isAllowed(finalURL),
              http.expectedContentLength <= 524_288 else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 524_288 else { throw NativeHLSSubtitleBridgeError.unsafeManifest }
            data.append(byte)
        }
        guard let result = String(data: data, encoding: .utf8) else {
            throw NativeHLSSubtitleBridgeError.unsafeManifest
        }
        return result
    }
}
