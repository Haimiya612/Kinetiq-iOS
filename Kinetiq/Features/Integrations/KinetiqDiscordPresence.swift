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

/// Pure presentation mapping, usable without contacting Discord.
enum KinetiqDiscordActivity {
    static let applicationID = "1571558800387874819"

    static func description(for playback: KinetiqPresencePlayback) -> String {
        let title = playback.animeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Watching anime" : String(title.prefix(128))
    }

    static func state(for playback: KinetiqPresencePlayback) -> String {
        let number = playback.episodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = number.isEmpty ? "Episode" : "Episode \(number)"
        let language = playback.language.lowercased() == "dub" ? "DUB" : "SUB"
        let suffix = playback.isPlaying ? "" : " · Paused"
        return String("\(label) · \(language)\(suffix)".prefix(128))
    }

    /// Only plain HTTPS artwork URLs. Never send signed query URLs, private
    /// source headers, cookies, file URLs, or credentials to Discord.
    static func publicArtwork(for playback: KinetiqPresencePlayback) -> String? {
        guard let url = playback.posterURL,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host != "localhost", !host.hasSuffix(".local"),
              host != "127.0.0.1", host != "::1",
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.absoluteString.count <= 400 else { return nil }
        return url.absoluteString
    }

    static func payload(for playback: KinetiqPresencePlayback, now: Date = Date()) -> [String: Any] {
        var activity: [String: Any] = [
            "name": "Kinetiq",
            "type": 3, // Watching
            "application_id": applicationID,
            "details": description(for: playback),
            "state": state(for: playback)
        ]

        if let artwork = publicArtwork(for: playback) {
            activity["assets"] = [
                "large_image": artwork,
                "large_text": description(for: playback)
            ]
        }
        if playback.isPlaying, playback.position.isFinite, playback.position >= 0 {
            let start = now.timeIntervalSince1970 - playback.position
            var timestamps: [String: Int] = ["start": Int(start)]
            if playback.duration.isFinite, playback.duration > playback.position {
                timestamps["end"] = Int(start + playback.duration)
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

    @Published private(set) var enabled: Bool
    @Published private(set) var hasCredential: Bool
    @Published private(set) var connection: Connection = .off
    @Published private(set) var message = "No connection has been tested."
    @Published private(set) var lastPreview: KinetiqPresencePlayback?
    @Published private(set) var lastSentAt: Date?

    private var socket: URLSessionWebSocketTask?
    private var listeningTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastSequence: Int?
    private var generation = 0
    private var lastSignature: String?
    private var lastPublication = Date.distantPast
    private var foregroundObserver: NSObjectProtocol?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hasCredential = KinetiqDiscordCredentialStore.exists
        connection = enabled ? .disconnected : .off
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.socket == nil,
                      self.connection == .interrupted else { return }
                self.connect()
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
        else { disconnect(); connection = .off; lastPreview = nil }
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
    }

    func connect() {
        guard enabled else { connection = .off; return }
        guard let token = KinetiqDiscordCredentialStore.read(), !token.isEmpty else {
            connection = .needsCredential
            message = "Enter a fresh token on this device."
            return
        }
        disconnect()
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        generation += 1
        let currentGeneration = generation
        socket = task
        connection = .connecting
        message = "Opening the experimental Gateway session…"
        task.resume()
        listeningTask = Task { @MainActor [weak self] in
            await self?.receiveLoop(on: task, generation: currentGeneration, token: token)
            session.invalidateAndCancel()
        }
    }

    func disconnect() {
        generation += 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listeningTask?.cancel()
        listeningTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        lastSequence = nil
        lastSignature = nil
        lastSentAt = nil
        connection = enabled ? .disconnected : .off
        message = "Disconnected from Discord."
    }

    func record(_ snapshot: KinetiqPresencePlayback) {
        guard enabled else { return }
        lastPreview = snapshot
        guard connection == .connected else { return }
        publishIfNeeded(force: false)
    }

    func playbackEnded() {
        guard enabled else { return }
        lastPreview = nil
        lastSignature = nil
        guard let socket, connection == .connected else { return }
        Task { try? await Self.send(KinetiqDiscordActivity.clearPayload, on: socket) }
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
        publishIfNeeded(force: true)
    }

    private func publishIfNeeded(force: Bool) {
        guard let socket, connection == .connected, let lastPreview else { return }
        let signature = "\(lastPreview.animeTitle)|\(lastPreview.episodeNumber)|\(lastPreview.language)|\(lastPreview.isPlaying)|\(lastPreview.isPictureInPicture)"
        if !force, signature == lastSignature,
           Date().timeIntervalSince(lastPublication) < 30 { return }
        lastSignature = signature
        lastPublication = Date()
        let payload = KinetiqDiscordActivity.payload(for: lastPreview)
        Task { @MainActor [weak self] in
            do {
                try await Self.send(payload, on: socket)
                self?.lastSentAt = Date()
                self?.message = "Activity submitted. Check visibility from another Discord account."
            } catch {
                self?.message = "Presence update could not be sent. Reconnect and retry."
            }
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
                if let sequence = packet["s"] as? Int { lastSequence = sequence }
                if op == 10 {
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
                } else if op == 0, packet["t"] as? String == "READY" {
                    connection = .connected
                    message = "Gateway READY. Rich Presence and artwork still need peer verification."
                    publishIfNeeded(force: true)
                } else if op == 9 {
                    connection = .needsCredential
                    message = "Discord rejected the session. Replace the token or turn this experiment off."
                    break
                } else if op == 7 {
                    message = "Discord requested a new session. Tap Reconnect."
                    break
                } else if op == 1 {
                    try await Self.send(["op": 1, "d": lastSequence as Any? ?? NSNull()], on: task)
                }
            }
        } catch {
            if generation == self.generation {
                let code = task.closeCode.rawValue
                if code == 4004 || code == 4003 {
                    connection = .needsCredential
                    message = "Discord refused authentication. Replace the saved token."
                } else {
                    connection = .interrupted
                    message = "Connection closed (code \(code)). iOS may suspend sockets during PiP."
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
        }
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
