import Foundation
import Combine

enum AppStorageKey {
    static let accentColor = "kinetiq.appearance.accentColor"
    static let lastLaunchTagline = "kinetiq.brand.lastLaunchTagline"
    static let playbackHistory = "kinetiq.playbackHistory.v1"
    static let playbackQueue = "kinetiq.playbackQueue.v1"
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
        guard seconds.isFinite, seconds >= 0 else { return "0 min" }

        let totalMinutes = Int(ceil(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
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

    var continueWatching: [PlaybackHistoryEntry] {
        entries
            .filter { $0.progress < completionThreshold }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    func entry(for mediaID: String) -> PlaybackHistoryEntry? {
        entries.first { $0.id == mediaID }
    }

    func resumePosition(for mediaID: String) -> Double {
        guard let entry = entry(for: mediaID),
              entry.progress < completionThreshold else {
            return 0
        }

        return entry.position
    }

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

        if safePosition / duration >= completionThreshold {
            remove(mediaID: mediaID)
            return
        }

        guard safePosition >= minimumSavedPosition else { return }

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

    func remove(mediaID: String) {
        let previousCount = entries.count
        entries.removeAll { $0.id == mediaID }
        guard entries.count != previousCount else { return }
        persist()
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            entries = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([PlaybackHistoryEntry].self, from: data)
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
                .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
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

// MARK: - Playback Queue Entry

struct PlaybackQueueEntry: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var fileURL: URL

    init(id: String, title: String, fileURL: URL) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
    }
}

// MARK: - Repeat Mode

enum PlaybackRepeatMode: String, Codable, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    var symbol: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var next: PlaybackRepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

// MARK: - Playback Queue Store

@MainActor
final class PlaybackQueueStore: ObservableObject {
    static let shared = PlaybackQueueStore()

    @Published private(set) var entries: [PlaybackQueueEntry] = []
    @Published private(set) var currentIndex: Int = 0

    // These remain externally settable for the existing UI/tests. Direct changes
    // are persisted too, fixing the old repeat-mode restore failure.
    @Published var isShuffled = false {
        didSet {
            if !isRestoring { persist() }
        }
    }

    @Published var repeatMode: PlaybackRepeatMode = .off {
        didSet {
            if !isRestoring { persist() }
        }
    }

    private let defaults: UserDefaults
    private let storageKey = AppStorageKey.playbackQueue
    private var isRestoring = false

    private struct QueueSnapshot: Codable {
        var entries: [PlaybackQueueEntry]
        var currentMediaID: String?
        var isShuffled: Bool
        var repeatMode: PlaybackRepeatMode
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    // MARK: Current Playback

    var currentEntry: PlaybackQueueEntry? {
        guard entries.indices.contains(currentIndex) else { return nil }
        return entries[currentIndex]
    }

    var nextEntry: PlaybackQueueEntry? {
        guard !entries.isEmpty else { return nil }
        if repeatMode == .one { return currentEntry }

        let nextIndex = currentIndex + 1
        if entries.indices.contains(nextIndex) { return entries[nextIndex] }
        return repeatMode == .all ? entries.first : nil
    }

    var previousEntry: PlaybackQueueEntry? {
        guard !entries.isEmpty else { return nil }
        if currentIndex > 0 { return entries[currentIndex - 1] }
        return repeatMode == .all ? entries.last : nil
    }

    var upcomingEntries: [PlaybackQueueEntry] {
        guard !entries.isEmpty, entries.indices.contains(currentIndex) else { return [] }
        return Array(entries.dropFirst(currentIndex + 1))
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: Queue Setup

    func replaceQueue(with newEntries: [PlaybackQueueEntry], startingAt mediaID: String) {
        var uniqueEntries: [PlaybackQueueEntry] = []
        var seenIDs = Set<String>()

        for entry in newEntries where seenIDs.insert(entry.id).inserted {
            uniqueEntries.append(entry)
        }

        entries = uniqueEntries
        currentIndex = entries.firstIndex(where: { $0.id == mediaID }) ?? 0
        persist()
    }

    func setCurrent(mediaID: String) {
        guard let index = entries.firstIndex(where: { $0.id == mediaID }) else { return }
        currentIndex = index
        persist()
    }

    // MARK: Add Items

    func enqueue(_ entry: PlaybackQueueEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        if entries.count == 1 { currentIndex = 0 }
        persist()
    }

    func enqueue(_ newEntries: [PlaybackQueueEntry]) {
        for entry in newEntries where !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
        }
        persist()
    }

    func playNext(_ entry: PlaybackQueueEntry) {
        // Moving the currently playing item next to itself would interrupt the
        // queue's identity, so treat it as an intentional no-op.
        if currentEntry?.id == entry.id {
            persist()
            return
        }

        let activeID = currentEntry?.id
        entries.removeAll { $0.id == entry.id }

        if let activeID,
           let activeIndex = entries.firstIndex(where: { $0.id == activeID }) {
            entries.insert(entry, at: min(activeIndex + 1, entries.count))
            currentIndex = activeIndex
        } else {
            entries.insert(entry, at: 0)
            currentIndex = 0
        }

        persist()
    }

    // MARK: Remove and Reorder

    func remove(mediaID: String) {
        guard let removedIndex = entries.firstIndex(where: { $0.id == mediaID }) else { return }
        entries.remove(at: removedIndex)

        if entries.isEmpty {
            currentIndex = 0
        } else if removedIndex < currentIndex {
            currentIndex -= 1
        } else if removedIndex == currentIndex {
            currentIndex = min(currentIndex, entries.count - 1)
        }

        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty, !entries.isEmpty else { return }

        // Preserve the playing item's identity before changing the array.
        let activeID = currentEntry?.id
        let validOffsets = source.filter { entries.indices.contains($0) }
        guard !validOffsets.isEmpty else { return }

        let movingOffsets = Set(validOffsets)
        let movingEntries = validOffsets.sorted().map { entries[$0] }
        let remainingEntries = entries.enumerated()
            .filter { !movingOffsets.contains($0.offset) }
            .map(\.element)

        // SwiftUI's move API treats the destination as an insertion offset
        // in the original collection. Adjust it for removed elements.
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(destination - removedBeforeDestination, 0),
            remainingEntries.count
        )

        var reorderedEntries = remainingEntries
        reorderedEntries.insert(contentsOf: movingEntries, at: insertionIndex)
        entries = reorderedEntries

        if let activeID,
           let updatedIndex = entries.firstIndex(where: { $0.id == activeID }) {
            currentIndex = updatedIndex
        } else if entries.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, entries.count - 1)
        }

        persist()
    }

    func clear() {
        entries.removeAll()
        currentIndex = 0
        persist()
    }

    // MARK: Navigation

    @discardableResult
    func advance(repeatingCurrent: Bool = true) -> PlaybackQueueEntry? {
        guard !entries.isEmpty else { return nil }

        // Repeat One applies to natural end-of-item transitions, not to a
        // user's explicit Next action or recovery from a missing file.
        if repeatMode == .one, repeatingCurrent {
            return currentEntry
        }

        if currentIndex + 1 < entries.count {
            currentIndex += 1
            persist()
            return currentEntry
        }

        guard repeatMode != .off else { return nil }
        currentIndex = 0
        persist()
        return currentEntry
    }

    @discardableResult
    func goToPrevious() -> PlaybackQueueEntry? {
        guard !entries.isEmpty else { return nil }

        if currentIndex > 0 {
            currentIndex -= 1
            persist()
            return currentEntry
        }

        guard repeatMode == .all else { return nil }
        currentIndex = entries.count - 1
        persist()
        return currentEntry
    }

    func play(mediaID: String) -> PlaybackQueueEntry? {
        guard let index = entries.firstIndex(where: { $0.id == mediaID }) else { return nil }
        currentIndex = index
        persist()
        return currentEntry
    }

    // MARK: Shuffle and Repeat

    func toggleShuffle() {
        isShuffled.toggle()

        guard entries.count > 2, let current = currentEntry else {
            persist()
            return
        }

        let currentID = current.id
        var remaining = entries.filter { $0.id != currentID }
        remaining.shuffle()
        entries = [current] + remaining
        currentIndex = 0
        persist()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        persist()
    }

    // MARK: Persistence

    private func restore() {
        isRestoring = true
        defer { isRestoring = false }

        guard let data = defaults.data(forKey: storageKey) else { return }

        do {
            let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: data)
            entries = snapshot.entries
            isShuffled = snapshot.isShuffled
            repeatMode = snapshot.repeatMode

            if let currentMediaID = snapshot.currentMediaID,
               let index = entries.firstIndex(where: { $0.id == currentMediaID }) {
                currentIndex = index
            } else {
                currentIndex = 0
            }
        } catch {
            entries = []
            currentIndex = 0
            isShuffled = false
            repeatMode = .off
        }
    }

    private func persist() {
        let snapshot = QueueSnapshot(
            entries: entries,
            currentMediaID: currentEntry?.id,
            isShuffled: isShuffled,
            repeatMode: repeatMode
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Queue persistence must never interrupt playback.
        }
    }
}
