import AVFoundation
import Combine
import Foundation

// MARK: - Playback Queue Controller

/// Drives queue navigation through the same AVPlayer used by the player UI.
/// Queue entries remain local files in Phase 2; remote streams are a later roadmap item.
@MainActor
final class PlaybackQueueController: ObservableObject {
    @Published private(set) var currentEntry: PlaybackQueueEntry?
    @Published private(set) var isActive = false
    @Published private(set) var playbackError: String?

    let player: AVPlayer
    let queue: PlaybackQueueStore

    /// Called immediately before an item finishes and the queue advances.
    var onItemFinished: (() -> Void)?

    private var endObserver: NSObjectProtocol?
    private var isStopped = false

    init(
        player: AVPlayer,
        queue: PlaybackQueueStore = .shared
    ) {
        self.player = player
        self.queue = queue
        player.automaticallyWaitsToMinimizeStalling = true
        currentEntry = queue.currentEntry
        observePlaybackCompletion()
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: Queue Setup

    func startQueue(
        entries: [PlaybackQueueEntry],
        startingAt mediaID: String,
        autoplay: Bool = false
    ) {
        guard !entries.isEmpty else {
            playbackError = "There are no videos to play."
            return
        }

        queue.replaceQueue(with: entries, startingAt: mediaID)

        guard let entry = queue.currentEntry else {
            playbackError = "The selected video could not be found."
            return
        }

        if !load(entry, autoplay: autoplay) {
            _ = advanceToAvailableEntry(autoplay: autoplay, repeatingCurrent: false)
        }
    }

    // MARK: Loading

    @discardableResult
    func load(
        _ entry: PlaybackQueueEntry,
        autoplay: Bool = true
    ) -> Bool {
        guard entry.fileURL.isFileURL,
              FileManager.default.fileExists(atPath: entry.fileURL.path) else {
            playbackError = "This file is no longer available."
            isActive = false
            return false
        }

        if queue.currentEntry?.id != entry.id {
            _ = queue.play(mediaID: entry.id)
        }

        isStopped = false
        playbackError = nil
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: entry.fileURL))

        currentEntry = entry
        isActive = true

        if autoplay {
            player.play()
        }

        return true
    }

    // MARK: Next / Previous

    @discardableResult
    func next() -> PlaybackQueueEntry? {
        // A manual Next skips the current item even while Repeat One is on.
        advanceToAvailableEntry(autoplay: true, repeatingCurrent: false)
    }

    @discardableResult
    private func advanceToAvailableEntry(
        autoplay: Bool,
        repeatingCurrent: Bool = false
    ) -> PlaybackQueueEntry? {
        guard !queue.entries.isEmpty else {
            player.pause()
            isActive = false
            return nil
        }

        // One pass prevents an invalid item from trapping repeat-all/repeat-one.
        for _ in 0..<queue.entries.count {
            guard let entry = queue.advance(repeatingCurrent: repeatingCurrent) else {
                player.pause()
                isActive = false
                return nil
            }

            if load(entry, autoplay: autoplay) {
                return entry
            }
        }

        player.pause()
        isActive = false
        playbackError = "None of the queue items are available anymore."
        return nil
    }

    @discardableResult
    func previous(
        currentTime: Double,
        restartThreshold: Double = 3
    ) -> PlaybackQueueEntry? {
        if currentTime > restartThreshold {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            return currentEntry
        }

        guard !queue.entries.isEmpty else {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            return currentEntry
        }

        for _ in 0..<queue.entries.count {
            guard let entry = queue.goToPrevious() else {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                return currentEntry
            }

            if load(entry) {
                return entry
            }
        }

        player.pause()
        isActive = false
        playbackError = "None of the previous queue items are available."
        return nil
    }

    @discardableResult
    func select(mediaID: String) -> PlaybackQueueEntry? {
        guard let entry = queue.play(mediaID: mediaID) else {
            return nil
        }

        return load(entry) ? entry : nil
    }

    // MARK: Completion Observation

    private func observePlaybackCompletion() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let finishedItem = notification.object as? AVPlayerItem else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      finishedItem === self.player.currentItem else {
                    return
                }

                self.onItemFinished?()
                _ = self.advanceToAvailableEntry(autoplay: true, repeatingCurrent: true)
            }
        }
    }

    // MARK: Playback Controls

    func play() {
        guard !isStopped, player.currentItem != nil else { return }
        playbackError = nil
        player.play()
        isActive = true
    }

    func pause() {
        player.pause()
        isActive = false
    }

    func togglePlayback() {
        player.rate > 0 ? pause() : play()
    }

    // MARK: Queue Editing

    func enqueue(_ entry: PlaybackQueueEntry) {
        queue.enqueue(entry)
    }

    func enqueue(_ entries: [PlaybackQueueEntry]) {
        queue.enqueue(entries)
    }

    func enqueueNext(_ entry: PlaybackQueueEntry) {
        queue.playNext(entry)
    }

    func remove(mediaID: String) {
        let removingCurrent = currentEntry?.id == mediaID
        queue.remove(mediaID: mediaID)

        guard removingCurrent else { return }

        guard let replacement = queue.currentEntry else {
            stop()
            return
        }

        if !load(replacement) {
            _ = advanceToAvailableEntry(autoplay: true, repeatingCurrent: false)
        }
    }

    func clear() {
        queue.clear()
        stop()
    }

    func toggleShuffle() {
        queue.toggleShuffle()
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
    }

    // MARK: Cleanup

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        player.pause()
        player.replaceCurrentItem(with: nil)
        isActive = false
        currentEntry = nil
        playbackError = nil
        onItemFinished = nil
    }
}
