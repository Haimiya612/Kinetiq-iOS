import AVFoundation
import Combine
import Foundation

// MARK: - Playback Queue Controller

/// Coordinates queue navigation with one persistent AVPlayer instance.
///
/// The controller owns queue navigation and track transitions. It does not
/// create a new AVPlayer when moving between entries, so the player surface
/// can remain attached throughout playback.
@MainActor
final class PlaybackQueueController: ObservableObject {

    // MARK: Published State

    @Published private(set) var currentEntry: PlaybackQueueEntry?
    @Published private(set) var isActive = false
    @Published private(set) var playbackError: String?

    // MARK: Dependencies

    let player: AVPlayer
    let queue: PlaybackQueueStore

    // MARK: Private State

    private var endObserver: NSObjectProtocol?
    private var isStopped = false
    private var transitionID = UUID()

    // MARK: Initialization

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
        startingAt mediaID: String
    ) {
        guard !entries.isEmpty else {
            playbackError = "There are no videos to play."
            return
        }

        queue.replaceQueue(
            with: entries,
            startingAt: mediaID
        )

        guard let entry = queue.currentEntry else {
            playbackError = "The selected video could not be found."
            return
        }

        load(entry)
    }

    // MARK: Track Loading

    @discardableResult
    func load(
        _ entry: PlaybackQueueEntry,
        autoplay: Bool = true
    ) -> Bool {
        guard FileManager.default.fileExists(
            atPath: entry.fileURL.path
        ) else {
            playbackError = "This file is no longer available."
            isActive = false
            return false
        }

        transitionID = UUID()
        isStopped = false
        playbackError = nil

        player.pause()

        let item = AVPlayerItem(url: entry.fileURL)
        player.replaceCurrentItem(with: item)

        currentEntry = entry
        isActive = true

        if autoplay {
            player.play()
        }

        return true
    }

    // MARK: Next

    @discardableResult
    func next() -> PlaybackQueueEntry? {
        guard let entry = queue.advance() else {
            player.pause()
            isActive = false
            return nil
        }

        guard load(entry) else {
            return skipUnavailableEntries()
        }

        return entry
    }

    /// Skips unavailable entries without getting stuck on a broken file.
    private func skipUnavailableEntries() -> PlaybackQueueEntry? {
        let maximumAttempts = queue.entries.count
        var attempts = 0

        while attempts < maximumAttempts {
            attempts += 1

            guard let entry = queue.advance() else {
                player.pause()
                isActive = false
                return nil
            }

            if load(entry) {
                return entry
            }
        }

        player.pause()
        isActive = false
        playbackError = "None of the remaining queue items are available."

        return nil
    }

    // MARK: Previous

    @discardableResult
    func previous(
        currentTime: Double,
        restartThreshold: Double = 3
    ) -> PlaybackQueueEntry? {

        if currentTime > restartThreshold {
            player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )

            return currentEntry
        }

        guard let entry = queue.goToPrevious() else {
            player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )

            return currentEntry
        }

        guard load(entry) else {
            return nil
        }

        return entry
    }

    // MARK: Select Queue Entry

    @discardableResult
    func select(
        mediaID: String
    ) -> PlaybackQueueEntry? {

        guard let entry = queue.play(mediaID: mediaID) else {
            return nil
        }

        guard load(entry) else {
            return nil
        }

        return entry
    }

    // MARK: Playback Completion

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

                self.advanceAutomatically()
            }
        }
    }

    private func advanceAutomatically() {
        _ = next()
    }

    // MARK: Playback Controls

    func play() {
        guard !isStopped,
              player.currentItem != nil else {
            return
        }

        playbackError = nil
        player.play()
        isActive = true
    }

    func pause() {
        player.pause()
        isActive = false
    }

    func togglePlayback() {
        if player.rate > 0 {
            pause()
        } else {
            play()
        }
    }

    // MARK: Shuffle and Repeat

    func toggleShuffle() {
        queue.toggleShuffle()
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
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
        queue.remove(mediaID: mediaID)

        if currentEntry?.id == mediaID {
            currentEntry = queue.currentEntry
        }
    }

    // MARK: Cleanup

    func stop() {
        guard !isStopped else {
            return
        }

        isStopped = true
        transitionID = UUID()

        player.pause()
        player.replaceCurrentItem(with: nil)

        isActive = false
        currentEntry = nil
        playbackError = nil
    }
}