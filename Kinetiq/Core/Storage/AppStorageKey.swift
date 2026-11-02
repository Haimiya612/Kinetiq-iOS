import Foundation
import Combine

enum AppStorageKey {
    static let appearance = "kinetiq.appearance"
    static let lastLaunchTagline = "kinetiq.brand.lastLaunchTagline"
    static let playbackHistory = "kinetiq.playbackHistory.v1"
}

// MARK: - Playback History Entry

struct PlaybackHistoryEntry: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var position: Double
    var duration: Double
    var lastPlayedAt: Date

    var progress: Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    var remainingSeconds: Double {
        max(duration - position, 0)
    }

    var remainingTimeText: String {
        Self.formatTime(remainingSeconds)
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0 min"
        }

        let totalMinutes = Int(ceil(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0
                ? "\(hours) hr"
                : "\(hours) hr \(minutes) min"
        }

        return "\(max(totalMinutes, 1)) min"
    }
}

// MARK: - Playback History Store

final class PlaybackHistoryStore: ObservableObject {
    static let shared = PlaybackHistoryStore()

    @Published private(set) var entries: [PlaybackHistoryEntry] = []

    private let defaults: UserDefaults
    private let storageKey = AppStorageKey.playbackHistory

    private let minimumSavedPosition: Double = 8
    private let completionThreshold: Double = 0.97
    private let maximumEntries = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Public Access

    var continueWatching: [PlaybackHistoryEntry] {
        entries
            .filter { $0.progress < completionThreshold }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    func entry(for mediaID: String) -> PlaybackHistoryEntry? {
        entries.first { $0.id == mediaID }
    }

    func resumePosition(for mediaID: String) -> Double {
        guard let entry = entry(for: mediaID) else {
            return 0
        }

        guard entry.progress < completionThreshold else {
            return 0
        }

        return entry.position
    }

    // MARK: Save Progress

    func save(
        mediaID: String,
        title: String,
        position: Double,
        duration: Double
    ) {
        guard !mediaID.isEmpty,
              !title.isEmpty,
              position.isFinite,
              duration.isFinite,
              position >= 0,
              duration > 0 else {
            return
        }

        let safePosition = min(position, duration)

        // A finished video should no longer appear in Continue Watching.
        if safePosition / duration >= completionThreshold {
            remove(mediaID: mediaID)
            return
        }

        // Do not replace a valid saved position with a very early position.
        // This can happen when a player is opened and closed immediately.
        guard safePosition >= minimumSavedPosition else {
            return
        }

        let newEntry = PlaybackHistoryEntry(
            id: mediaID,
            title: title,
            position: safePosition,
            duration: duration,
            lastPlayedAt: Date()
        )

        entries.removeAll { $0.id == mediaID }
        entries.insert(newEntry, at: 0)

        if entries.count > maximumEntries {
            entries = Array(entries.prefix(maximumEntries))
        }

        persist()
    }

    // MARK: Remove History

    func remove(mediaID: String) {
        let previousCount = entries.count
        entries.removeAll { $0.id == mediaID }

        guard entries.count != previousCount else {
            return
        }

        persist()
    }

    func clear() {
        guard !entries.isEmpty else {
            return
        }

        entries.removeAll()
        persist()
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            entries = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode(
                [PlaybackHistoryEntry].self,
                from: data
            )

            entries = decoded
                .filter {
                    !$0.id.isEmpty
                    && !$0.title.isEmpty
                    && $0.position.isFinite
                    && $0.duration.isFinite
                    && $0.position >= 0
                    && $0.duration > 0
                    && $0.progress < completionThreshold
                }
                .sorted {
                    $0.lastPlayedAt > $1.lastPlayedAt
                }
                .prefix(maximumEntries)
                .map { $0 }
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Playback must continue even if history persistence fails.
        }
    }
}