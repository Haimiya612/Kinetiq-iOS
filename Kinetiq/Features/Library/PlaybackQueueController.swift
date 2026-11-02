import AVFoundation
import Combine
import Foundation

// MARK: - Playback Queue Controller

/// Coordinates queue navigation with a single AVPlayer instance.
///
/// The controller deliberately reuses the same AVPlayer when switching
/// tracks. This avoids rebuilding the player surface for every queue item.
@MainActor
final class PlaybackQueueController: ObservableObject {

    // MARK: Published State

    @Published private(set) var currentEntry: PlaybackQueueEntry?
    @Published private(set) var isActive = false

    // MARK: Dependencies

    let player: AVPlayer
    let queue: PlaybackQueueStore

    // MARK: Private State

    private var endObserver: NSObjectProtocol?
    private var currentItemObserver: NSKeyValueObservation?
    private var isStopped = false

    // MARK: Initialization

    init(
        player: AVPlayer,
        queue: PlaybackQueueStore = .shared
    ) {
        self.player = player
        self.queue = queue

        configurePlayer()
        observePlaybackCompletion()

        currentEntry = queue.currentEntry
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: Configuration

    private func configurePlayer() {
        player.automaticallyWaitsToMinimizeStalling = true
    }

    private func observePlaybackCompletion() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in

            Task { @MainActor [weak self] in
                guard let self,
                      let finishedItem = notification.object as? AVPlayerItem,
                      finishedItem === self.player.currentItem else {
                    return
                }

                self.advanceAutomatically()
            }
        }
    }

    // MARK: Queue Initialization

    func startQueue(
        entries: [PlaybackQueueEntry],
        startingAt mediaID: String
    ) {
        guard !entries.isEmpty else {
            return
        }

        queue.replaceQueue(
            with: entries,
            startingAt: mediaID
        )

        guard let entry = queue.currentEntry else {
            return
        }

        load(entry, autoplay: true)
    }

    // MARK: Track Loading

    func load(
        _ entry: PlaybackQueueEntry,
        autoplay: Bool = true
    ) {
        guard FileManager.default.fileExists(
            atPath: entry.fileURL.path
        ) else {
            return
        }

        isStopped = false

        player.pause()

        let item = AVPlayerItem(url: entry.fileURL)

        player.replaceCurrentItem(with: item)

        currentEntry = entry
        isActive = true

        if autoplay {
            player.play()
        }
    }

    // MARK: Next

    @discardableResult
    func next() -> PlaybackQueueEntry? {
        guard let entry = queue.advance() else {
            player.pause()
            isActive = false
            return nil
        }

        load(entry)

        return entry
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

        load(entry)

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

        load(entry)

        return entry
    }

    // MARK: Automatic Advancement

    private func advanceAutomatically() {
        guard !isStopped else {
            return
        }

        _ = next()
    }

    // MARK: Playback Controls

    func play() {
        guard !isStopped else {
            return
        }

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

    func enqueueNext(_ entry: PlaybackQueueEntry) {
        queue.playNext(entry)
    }

    func remove(mediaID: String) {
        queue.remove(mediaID: mediaID)
    }

    // MARK: Cleanup

    func stop() {
        guard !isStopped else {
            return
        }

        isStopped = true

        player.pause()
        player.replaceCurrentItem(with: nil)

        currentItemObserver?.invalidate()
        currentItemObserver = nil

        isActive = false
        currentEntry = nil
    }
}
