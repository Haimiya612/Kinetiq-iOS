import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import Combine

// MARK: - Local Media

private struct LocalMedia: Identifiable {
    let url: URL

    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}


// MARK: - Shared Local Thumbnail View

private struct MediaThumbnailView: View {
    let mediaID: String
    let url: URL

    @State private var image: UIImage?

    private var requestID: String {
        "\(mediaID)|\(url.standardizedFileURL.path)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            KinetiqPalette.cyan.opacity(0.23),
                            KinetiqPalette.violet.opacity(0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(KinetiqPalette.cyan)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .task(id: requestID) {
            image = nil

            let loadedImage = await LocalMediaThumbnailCache.shared.image(
                for: mediaID,
                url: url
            )

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                image = loadedImage
            }
        }
    }
}

// MARK: - Photo Transfer

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")

            try FileManager.default.copyItem(
                at: received.file,
                to: temporaryURL
            )

            return PickedMovie(url: temporaryURL)
        }
    }
}

// MARK: - Library View

struct LibraryView: View {
    @Binding var requestedMediaID: String?

    @State private var media: [LocalMedia] = []
    @State private var selectedMedia: LocalMedia?
    @State private var showingImporter = false
    @State private var showingSourcePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var appeared = false

    @StateObject private var playbackHistory = PlaybackHistoryStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(requestedMediaID: Binding<String?> = .constant(nil)) {
        self._requestedMediaID = requestedMediaID
    }

    private var mediaDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("KinetiqMedia", isDirectory: true)
    }

    private var playbackQueueEntries: [PlaybackQueueEntry] {
        media.map {
            PlaybackQueueEntry(
                id: $0.id,
                title: $0.title,
                fileURL: $0.url
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                if media.isEmpty {
                    emptyState
                } else {
                    mediaList
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSourcePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(
                                    colors: [
                                        KinetiqPalette.cyan,
                                        KinetiqPalette.violet
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Import media")
                }
            }
            .confirmationDialog(
                "Add to your library",
                isPresented: $showingSourcePicker,
                titleVisibility: .visible
            ) {
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label(
                        "Photo Library",
                        systemImage: "photo.on.rectangle"
                    )
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose where you want to import videos from.")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    .movie,
                    .video,
                    .mpeg4Movie,
                    .quickTimeMovie
                ],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 20,
                matching: .videos,
                preferredItemEncoding: .compatible
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await importPhotos(newItems)
                }
            }
            .onChange(of: requestedMediaID) { _, _ in
                openRequestedMediaIfAvailable()
            }
            .onChange(of: media.map(\.id)) { _, _ in
                openRequestedMediaIfAvailable()
            }
            .fullScreenCover(item: $selectedMedia) { item in
                LocalVideoPlayerView(
                    url: item.url,
                    queueEntries: playbackQueueEntries
                )
                .preferredColorScheme(.dark)
                .presentationBackground(.black)
                .ignoresSafeArea()
            }
            .alert(
                "Import Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .onAppear {
                loadMedia()
                openRequestedMediaIfAvailable()

                withAnimation(
                    reduceMotion
                        ? .easeInOut(duration: 0.2)
                        : .spring(response: 0.6, dampingFraction: 0.85)
                ) {
                    appeared = true
                }
            }
        }
    }

    // MARK: Requested Media

    private func openRequestedMediaIfAvailable() {
        guard let requestedMediaID else { return }

        if let item = media.first(where: { $0.id == requestedMediaID }) {
            self.requestedMediaID = nil
            selectedMedia = item
            return
        }

        if !media.isEmpty {
            playbackHistory.remove(mediaID: requestedMediaID)
            self.requestedMediaID = nil
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(KinetiqPalette.cyan.opacity(0.09))
                    .frame(width: 112, height: 112)

                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 43, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.cyan,
                                KinetiqPalette.violet
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Your library starts here.")
                    .font(.system(size: 23, weight: .bold, design: .rounded))

                Text(
                    "Bring your own media into Kinetiq.\nYour imported videos stay on your device."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            }

            Button {
                showingSourcePicker = true
            } label: {
                Label("Import videos", systemImage: "plus")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.cyan,
                                KinetiqPalette.blue,
                                KinetiqPalette.violet
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
        }
        .padding(30)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: Media List

    private var mediaList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR COLLECTION")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .tracking(2)
                            .foregroundStyle(KinetiqPalette.cyan)

                        Text("\(media.count) videos")
                            .font(
                                .system(
                                    size: 25,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                    }

                    Spacer()
                }
                .padding(.bottom, 8)

                ForEach(media) { item in
                    Button {
                        selectedMedia = item
                    } label: {
                        mediaCard(item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteMedia(item)
                        } label: {
                            Label(
                                "Remove from library",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    private func mediaCard(_ item: LocalMedia) -> some View {
        HStack(spacing: 15) {
            MediaThumbnailView(
    mediaID: item.id,
    url: item.url
)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(
                        .system(.subheadline, design: .rounded)
                            .weight(.bold)
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.url.pathExtension.uppercased())
                    .font(
                        .system(
                            size: 10,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(.secondary)

                if let entry = playbackHistory.entry(for: item.id) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            "Continue • \(entry.progressPercent)% watched",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KinetiqPalette.accent)

                        ProgressView(value: entry.progress)
                            .tint(KinetiqPalette.accent)
                    }
                } else {
                    Label(
                        "On this device",
                        systemImage: "iphone"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 29))
                .foregroundStyle(KinetiqPalette.cyan)
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
    }

    // MARK: File Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importFiles(urls)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true
            )

            for sourceURL in urls {
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()

                defer {
                    if hasAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let fileExtension = sourceURL.pathExtension.isEmpty
                    ? "mp4"
                    : sourceURL.pathExtension

                let filename = UUID().uuidString + "." + fileExtension
                let destinationURL = mediaDirectory
                    .appendingPathComponent(filename)

                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: destinationURL
                )
            }

            loadMedia()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Photo Library Import

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let movie = try await item.loadTransferable(
                    type: PickedMovie.self
                ) else {
                    continue
                }

                importFiles([movie.url])
                try? FileManager.default.removeItem(at: movie.url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        selectedPhotoItems = []
    }

    // MARK: Storage

    private func loadMedia() {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true
            )

            let files = try FileManager.default.contentsOfDirectory(
                at: mediaDirectory,
                includingPropertiesForKeys: nil
            )

            media = files
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare(
                        $1.lastPathComponent
                    ) == .orderedAscending
                }
                .map { LocalMedia(url: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMedia(_ item: LocalMedia) {
        do {
            try FileManager.default.removeItem(at: item.url)

            LocalMediaThumbnailCache.shared.invalidate(mediaID: item.id)
            playbackHistory.remove(mediaID: item.id)

            loadMedia()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Player Panel Types

private enum PlayerPanel: String, CaseIterable, Identifiable {
    case episodes = "Episodes"
    case servers = "Servers"
    case audio = "Audio"
    case playback = "Playback"
    case subtitles = "Subtitles"
    case queue = "Queue"
    case more = "More"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .episodes: "list.number"
        case .servers: "server.rack"
        case .audio: "waveform"
        case .playback: "slider.horizontal.3"
        case .subtitles: "captions.bubble"
        case .queue: "text.line.first.and.arrowtriangle.forward"
        case .more: "ellipsis.circle"
        }
    }
}

// MARK: - Playback Engine

@MainActor
private final class KinetiqPlaybackModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var currentURL: URL
    @Published var currentTitle: String

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var playbackError: String?

    @Published var audioOptions: [AVMediaSelectionOption] = []
    @Published var subtitleOptions: [AVMediaSelectionOption] = []

    @Published var selectedAudio: AVMediaSelectionOption?
    @Published var selectedSubtitle: AVMediaSelectionOption?
    @Published private(set) var captionChoice: KinetiqCaptionChoice = .settings

    @Published var hasAudioSelection = false
    @Published var hasSubtitleSelection = false

    @Published var playbackRate: Float = 1.0
    @Published var aspectFill = false
    @Published var sleepTimerMinutes: Int?

    @Published var resolutionText = "Analyzing…"
    @Published var fileSizeText = "Calculating…"

    let queueController: PlaybackQueueController

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var sleepTask: Task<Void, Never>?

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private weak var subtitleOptionsItem: AVPlayerItem?
    var requiresEmbeddedSubtitle: Bool { subtitleGroup?.allowsEmptySelection == false }

    private var queueEntryObservation: AnyCancellable?
    private var queueActivityObservation: AnyCancellable?
    private var queueErrorObservation: AnyCancellable?

    private var lastSavedPosition: Double = 0
    private var hasRestoredProgress = false

    init(url: URL, queueEntries: [PlaybackQueueEntry]) {
        let sharedPlayer = AVPlayer()
        let controller = PlaybackQueueController(player: sharedPlayer)

        self.player = sharedPlayer
        self.queueController = controller
        self.currentURL = url
        self.currentTitle = url.deletingPathExtension().lastPathComponent

        let entries = queueEntries.isEmpty
            ? [
                PlaybackQueueEntry(
                    id: url.lastPathComponent,
                    title: url.deletingPathExtension().lastPathComponent,
                    fileURL: url
                )
            ]
            : queueEntries

        controller.startQueue(
            entries: entries,
            startingAt: url.lastPathComponent,
            autoplay: false
        )

        if let entry = controller.currentEntry {
            currentURL = entry.fileURL
            currentTitle = entry.title
        }

        controller.onItemFinished = { [weak self] in
            guard let self else { return }
            PlaybackHistoryStore.shared.remove(
                mediaID: self.currentMediaID
            )
        }

        configurePlayer()
    }

    private var currentMediaID: String {
        queueController.currentEntry?.id
            ?? currentURL.lastPathComponent
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration)
    }

    // MARK: Observation

    private func configurePlayer() {
        player.automaticallyWaitsToMinimizeStalling = true
        observeCurrentItem(player.currentItem)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            ),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let seconds = time.seconds

                if seconds.isFinite {
                    self.currentTime = seconds

                    if self.duration > 0,
                       abs(seconds - self.lastSavedPosition) >= 5 {
                        self.saveProgress()
                    }
                }

                self.isPlaying = self.player.rate != 0
            }
        }

        queueEntryObservation = queueController.$currentEntry
            .dropFirst()
            .sink { [weak self] entry in
                Task { @MainActor [weak self] in
                    self?.handleQueueEntryChange(entry)
                }
            }

        queueActivityObservation = queueController.$isActive
            .sink { [weak self] active in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !active {
                        self.isPlaying = false
                    }
                }
            }

        queueErrorObservation = queueController.$playbackError
            .sink { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.playbackError = error
                }
            }
    }

    private func observeCurrentItem(_ item: AVPlayerItem?) {
        statusObservation?.invalidate()
        statusObservation = nil
        subtitleOptionsItem = nil

        guard let item else {
            isBuffering = false
            return
        }

        item.textStyleRules = KinetiqSubtitleSettings.shared.appearance.nativeRules
        statusObservation = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.player.currentItem === observedItem else {
                    return
                }

                switch observedItem.status {
                case .readyToPlay:
                    self.isBuffering = false

                    let loadedDuration = observedItem.duration.seconds
                    self.duration = loadedDuration.isFinite
                        ? loadedDuration
                        : 0

                    self.restorePlaybackProgressIfNeeded()

                    Task {
                        await self.loadMediaOptions(for: observedItem)
                    }

                    Task {
                        await self.loadTechnicalMetadata(for: observedItem)
                    }

                case .failed:
                    self.isBuffering = false
                    self.playbackError = observedItem.error?.localizedDescription
                        ?? "Unable to play this video."

                    self.queueController.pause()

                default:
                    self.isBuffering = true
                }
            }
        }
    }

    private func handleQueueEntryChange(_ entry: PlaybackQueueEntry?) {
        guard let entry else { return }

        currentURL = entry.fileURL
        currentTitle = entry.title

        currentTime = 0
        duration = 0

        isBuffering = true
        playbackError = nil

        resolutionText = "Analyzing…"
        fileSizeText = "Calculating…"

        audioOptions = []
        subtitleOptions = []

        selectedAudio = nil
        selectedSubtitle = nil

        hasAudioSelection = false
        hasSubtitleSelection = false

        audioGroup = nil
        subtitleGroup = nil

        lastSavedPosition = 0
        hasRestoredProgress = false

        observeCurrentItem(player.currentItem)
    }

    // MARK: Technical Metadata

    private func loadTechnicalMetadata(
        for item: AVPlayerItem
    ) async {
        // Capture the URL before awaiting asset metadata so a queue transition
        // can't make an older item's size lookup read the newer item's file.
        let metadataURL = currentURL

        do {
            let tracks = try await item.asset.load(.tracks)

            guard player.currentItem === item else { return }

            if let videoTrack = tracks.first(
                where: { $0.mediaType == .video }
            ) {
                let naturalSize = try await videoTrack.load(.naturalSize)
                guard player.currentItem === item else { return }

                let transform = try await videoTrack.load(.preferredTransform)
                guard player.currentItem === item else { return }

                let transformedSize = naturalSize.applying(transform)

                let width = Int(abs(transformedSize.width).rounded())
                let height = Int(abs(transformedSize.height).rounded())

                if width > 0, height > 0 {
                    resolutionText = "\(width) × \(height)"
                } else {
                    resolutionText = "Unavailable"
                }
            } else {
                resolutionText = "No video track"
            }

            let resourceValues = try? metadataURL.resourceValues(
                forKeys: [.fileSizeKey]
            )

            guard player.currentItem === item else { return }

            if let fileSize = resourceValues?.fileSize {
                fileSizeText = ByteCountFormatter.string(
                    fromByteCount: Int64(fileSize),
                    countStyle: .file
                )
            } else {
                fileSizeText = "Unavailable"
            }
        } catch {
            guard player.currentItem === item else { return }

            resolutionText = "Unavailable"
            fileSizeText = "Unavailable"
        }
    }

    // MARK: Resume and History

    private func restorePlaybackProgressIfNeeded() {
        guard !hasRestoredProgress else { return }

        hasRestoredProgress = true

        guard duration > 0 else { return }

        let savedPosition = PlaybackHistoryStore.shared
            .resumePosition(for: currentMediaID)

        guard savedPosition >= 8,
              savedPosition < duration * 0.97 else {
            return
        }

        currentTime = savedPosition
        lastSavedPosition = savedPosition

        player.seek(
            to: CMTime(
                seconds: savedPosition,
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func saveProgress() {
        guard duration.isFinite,
              duration > 0,
              currentTime.isFinite,
              currentTime >= 0 else {
            return
        }

        PlaybackHistoryStore.shared.save(
            mediaID: currentMediaID,
            title: currentTitle,
            position: currentTime,
            duration: duration
        )

        lastSavedPosition = currentTime
    }

    // MARK: Audio and Subtitle Tracks

    private func loadMediaOptions(
        for item: AVPlayerItem
    ) async {
        let audio = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        let subtitles = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        guard player.currentItem === item else { return }
        audioGroup = audio
        subtitleGroup = subtitles
        audioOptions = audio?.options ?? []
        subtitleOptions = subtitles?.options ?? []
        hasAudioSelection = audio != nil
        hasSubtitleSelection = subtitles?.allowsEmptySelection ?? false
        if let audio {
            selectedAudio = item.currentMediaSelection.selectedMediaOption(in: audio)
        }
        subtitleOptionsItem = item
        refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
    }

    func selectAudio(_ option: AVMediaSelectionOption?) {
        guard let group = audioGroup else { return }

        player.currentItem?.select(option, in: group)
        selectedAudio = option
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let item = subtitleOptionsItem, item === player.currentItem, let group = subtitleGroup else { return }
        if let option {
            guard group.options.contains(option) else { return }
            captionChoice = .embedded(KinetiqCaptionLanguage(option))
        } else {
            guard group.allowsEmptySelection else { return }
            captionChoice = .off
        }
        item.select(option, in: group)
        selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: group)
    }

    func useSubtitleDefault() {
        captionChoice = .settings
        refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
    }

    func refreshCaptions(preference: String) {
        guard let item = subtitleOptionsItem, item === player.currentItem else { return }
        let target = captionChoice.target(preference: preference, embedded: subtitleOptions.map(KinetiqCaptionLanguage.init))
        selectedSubtitle = target.apply(to: item, group: subtitleGroup)
    }

    func syncCaptionSelection(for item: AVPlayerItem?) {
        guard let item, item === subtitleOptionsItem, item === player.currentItem, let subtitleGroup else { return }
        let actual = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
        if actual != selectedSubtitle { selectedSubtitle = actual }
    }

    // MARK: Playback Controls

    func play() {
        if player.currentItem?.status == .failed {
            retryPlayback()
            return
        }

        playbackError = nil
        queueController.play()

        if playbackRate != 1 {
            player.rate = playbackRate
        }

        isPlaying = true
    }

    func pause() {
        queueController.pause()
        isPlaying = false
        saveProgress()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func retryPlayback() {
        playbackError = nil
        isBuffering = true

        guard queueController.retryCurrent() else {
            playbackError = queueController.playbackError
                ?? "Kinetiq could not restart this video."

            isPlaying = false
            isBuffering = false
            return
        }

        isPlaying = true
    }

    func seek(to seconds: Double) {
        let safeTime = min(
            max(seconds, 0),
            max(duration, 0)
        )

        player.seek(
            to: CMTime(
                seconds: safeTime,
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func next() {
        saveProgress()
        _ = queueController.next()
    }

    func previous() {
        if currentTime <= 3 {
            saveProgress()
        }

        _ = queueController.previous(currentTime: currentTime)
    }

    func selectQueueEntry(_ entry: PlaybackQueueEntry) {
        guard entry.id != currentMediaID else {
            seek(to: 0)
            play()
            return
        }

        saveProgress()
        _ = queueController.select(mediaID: entry.id)
    }

    func removeQueueEntry(_ entry: PlaybackQueueEntry) {
        queueController.remove(mediaID: entry.id)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate

        if isPlaying {
            player.rate = rate
        }
    }

    // MARK: Sleep Timer

    func setSleepTimer(_ minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil

        sleepTimerMinutes = minutes

        guard let minutes else { return }

        sleepTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(minutes * 60))

                guard !Task.isCancelled else { return }

                pause()
                sleepTimerMinutes = nil
            } catch {
                // A user action cancelled or replaced the timer.
            }
        }
    }

    // MARK: Stop

    func stop() {
        saveProgress()

        sleepTask?.cancel()
        sleepTask = nil

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        statusObservation?.invalidate()
        statusObservation = nil

        queueEntryObservation = nil
        queueActivityObservation = nil
        queueErrorObservation = nil
        subtitleOptionsItem = nil

        queueController.stop()
        isPlaying = false
    }

    // MARK: Time Formatting

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainingSeconds
            )
        }

        return String(
            format: "%02d:%02d",
            minutes,
            remainingSeconds
        )
    }
}

// MARK: - Picture in Picture

@MainActor
private final class KinetiqPictureInPictureController:
    NSObject,
    ObservableObject {

    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    private weak var attachedLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    func attach(to layer: AVPlayerLayer) {
        guard attachedLayer !== layer else { return }

        possibleObservation?.invalidate()
        possibleObservation = nil

        controller?.delegate = nil
        controller = nil

        attachedLayer = layer
        isPossible = false
        isActive = false

        // This is a type method, not a Boolean property.
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        // Apple's player-layer initializer is failable.
        guard let pictureInPictureController =
            AVPictureInPictureController(playerLayer: layer) else {
            return
        }

        pictureInPictureController.delegate = self
        pictureInPictureController
            .canStartPictureInPictureAutomaticallyFromInline = true

        // Keep a strong reference for the entire PiP lifecycle.
        controller = pictureInPictureController

        possibleObservation = pictureInPictureController.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let possible = change.newValue ?? false

            Task { @MainActor [weak self] in
                self?.isPossible = possible
            }
        }
    }

    func start() {
        guard let controller,
              controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive else {
            return
        }

        controller.startPictureInPicture()
    }

    func stop() {
        guard let controller,
              controller.isPictureInPictureActive else {
            return
        }

        controller.stopPictureInPicture()
    }
}

// AVKit delegate callbacks aren't assumed to arrive on the main actor.
// Each state update explicitly hops to MainActor before touching @Published.
extension KinetiqPictureInPictureController:
    @preconcurrency AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        // The full-screen player remains presented behind PiP. Confirm that
        // the existing player interface can be restored without recreating it.
        completionHandler(true)
    }
}

// MARK: - AirPlay Route Picker

private struct KinetiqAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemTeal
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(
        _ uiView: AVRoutePickerView,
        context: Context
    ) {}
}

// MARK: - AVPlayer Layer Surface

private final class KinetiqPlayerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct KinetiqPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let aspectFill: Bool
    let pictureInPicture: KinetiqPictureInPictureController

    func makeUIView(context: Context) -> KinetiqPlayerUIView {
        let view = KinetiqPlayerUIView()

        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = aspectFill
            ? .resizeAspectFill
            : .resizeAspect

        pictureInPicture.attach(to: view.playerLayer)

        return view
    }

    func updateUIView(
        _ uiView: KinetiqPlayerUIView,
        context: Context
    ) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = aspectFill
            ? .resizeAspectFill
            : .resizeAspect

        pictureInPicture.attach(to: uiView.playerLayer)
    }

    static func dismantleUIView(
        _ uiView: KinetiqPlayerUIView,
        coordinator: ()
    ) {
        uiView.playerLayer.player = nil
    }
}

// MARK: - Full-Screen Custom Player

private struct LocalVideoPlayerView: View {
    @ObservedObject private var subtitleSettings = KinetiqSubtitleSettings.shared
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasOrientationLease = false
    @StateObject private var model: KinetiqPlaybackModel
    @StateObject private var pictureInPicture =
        KinetiqPictureInPictureController()

    @State private var controlsVisible = true
    @State private var activePanel: PlayerPanel?

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    @State private var seekFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    @State private var autoHideTask: Task<Void, Never>?

    private let autoHideDelay: Duration = .seconds(3.4)

    init(
        url: URL,
        queueEntries: [PlaybackQueueEntry]
    ) {
        self.url = url

        _model = StateObject(
            wrappedValue: KinetiqPlaybackModel(
                url: url,
                queueEntries: queueEntries
            )
        )
    }

    private var displayedTime: Double {
        isSeeking ? seekPosition : model.currentTime
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                KinetiqPlayerSurface(
                    player: model.player,
                    aspectFill: model.aspectFill,
                    pictureInPicture: pictureInPicture
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .background(.black)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleControls)
                    .accessibilityLabel(
                        "Show or hide playback controls"
                    )

                if controlsVisible {
                    controlOverlay(
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

                if model.isBuffering && model.playbackError == nil {
                    ProgressView()
                        .tint(KinetiqPalette.cyan)
                        .scaleEffect(1.25)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(3)
                }

                if let seekFeedback {
                    Text(seekFeedback)
                        .font(
                            .system(
                                size: 15,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 11)
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(4)
                }

                if let error = model.playbackError {
                    playbackErrorOverlay(error)
                        .zIndex(5)
                }

                if let activePanel {
                    optionsOverlay(
                        for: activePanel,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                    .zIndex(6)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .background(.black)
            .clipped()
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard activePanel == nil else { return }

                        let isLeftSide =
                            value.location.x < geometry.size.width / 2

                        let amount: Double = isLeftSide ? -10 : 10

                        model.skip(by: amount)

                        showSeekFeedback(
                            isLeftSide
                                ? "−10 seconds"
                                : "+10 seconds"
                        )

                        revealControls()
                    }
            )
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .easeInOut(duration: 0.24),
                value: controlsVisible
            )
            .animation(
                .spring(response: 0.34, dampingFraction: 0.88),
                value: activePanel
            )
            .onAppear {
                if !hasOrientationLease {
                    KinetiqPlaybackPresentation.enterPlayer()
                    hasOrientationLease = true
                }
                KinetiqPlaybackPresentation.preparePlayer(model.player)
                model.play()
                revealControls()
            }
            .onDisappear {
                if hasOrientationLease {
                    KinetiqPlaybackPresentation.leavePlayer()
                    hasOrientationLease = false
                }
                autoHideTask?.cancel()
                autoHideTask = nil

                feedbackTask?.cancel()
                feedbackTask = nil

                model.stop()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                model.saveProgress()
                // AVKit, not an app-lifecycle callback, owns automatic PiP.
                // The playerLayer controller has automatic inline PiP enabled.
            }
            .onChange(of: subtitleSettings.appearance) { _, style in
                model.player.currentItem?.textStyleRules = style.nativeRules
            }
            .onChange(of: subtitleSettings.language) { _, language in
                if model.captionChoice == .settings { model.refreshCaptions(preference: language) }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.mediaSelectionDidChangeNotification).receive(on: DispatchQueue.main)) { event in
                model.syncCaptionSelection(for: event.object as? AVPlayerItem)
            }
            .onChange(of: model.isPlaying) { _, playing in
                if playing {
                    scheduleAutoHide()
                } else {
                    cancelAutoHide()

                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                }
            }
            .onChange(of: activePanel) { _, panel in
                if panel != nil {
                    cancelAutoHide()

                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                } else {
                    scheduleAutoHide()
                }
            }
            .onChange(of: pictureInPicture.isActive) { _, isActive in
                if isActive {
                    cancelAutoHide()
                    activePanel = nil

                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = false
                    }
                } else {
                    revealControls()
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(.black)
    }

    // MARK: Seek Feedback

    private func showSeekFeedback(_ message: String) {
        feedbackTask?.cancel()

        withAnimation(.easeInOut(duration: 0.15)) {
            seekFeedback = message
        }

        feedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(750))

                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.2)) {
                    seekFeedback = nil
                }
            } catch {
                // A newer seek interaction replaced this feedback.
            }
        }
    }

    // MARK: - Shared Player Chrome (Batch 05A)
    // Local Files/Photos and installed modules render the very same SwiftUI
    // controls. Each closure still forwards to its own playback engine.

    private func controlOverlay(safeAreaInsets: EdgeInsets) -> some View {
        KinetiqUnifiedPlayerChrome(
            safeAreaInsets: safeAreaInsets,
            title: model.currentTitle,
            playing: model.isPlaying,
            busy: false,
            aspectFill: model.aspectFill,
            pictureInPictureAvailable: pictureInPicture.isPossible,
            displayedTime: displayedTime,
            duration: model.duration,
            elapsedLabel: KinetiqPlaybackModel.formatTime(displayedTime),
            durationLabel: model.formattedDuration,
            panels: PlayerPanel.allCases.map { option in
                KinetiqUnifiedPlayerChrome.Panel(
                    id: option.rawValue,
                    symbol: option.symbol,
                    selected: activePanel == option
                )
            },
            airPlayControl: AnyView(KinetiqAirPlayPicker()),
            onClose: { dismiss() },
            onStartPictureInPicture: { pictureInPicture.start() },
            onToggleAspect: {
                model.aspectFill.toggle()
                scheduleAutoHide()
            },
            onPrevious: {
                model.previous()
                revealControls()
            },
            onRewind: {
                model.skip(by: -10)
                showSeekFeedback("−10 seconds")
                scheduleAutoHide()
            },
            onTogglePlay: {
                model.togglePlayback()
                if model.isPlaying {
                    scheduleAutoHide()
                } else {
                    cancelAutoHide()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                }
            },
            onForward: {
                model.skip(by: 10)
                showSeekFeedback("+10 seconds")
                scheduleAutoHide()
            },
            onNext: {
                model.next()
                revealControls()
            },
            onSeekChanged: { newValue in
                isSeeking = true
                seekPosition = newValue
            },
            onSeekEditingChanged: { editing in
                if editing {
                    cancelAutoHide()
                } else {
                    model.seek(to: seekPosition)
                    isSeeking = false
                    scheduleAutoHide()
                }
            },
            onPanelSelected: { name in
                guard let panel = PlayerPanel(rawValue: name) else { return }
                activePanel = activePanel == panel ? nil : panel
                controlsVisible = true
                cancelAutoHide()
            }
        )
    }

    // MARK: Options Overlay

    @ViewBuilder
    private func optionsOverlay(
        for panel: PlayerPanel,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    activePanel = nil
                }

            if panel == .queue {
                PlaybackQueuePanel(
                    queue: model.queueController.queue,
                    onSelect: { entry in
                        model.selectQueueEntry(entry)
                        activePanel = nil
                        revealControls()
                    },
                    onRemove: { entry in
                        model.removeQueueEntry(entry)
                    },
                    onClose: {
                        activePanel = nil
                    }
                )
                .padding(.horizontal, 10)
                .padding(
                    .bottom,
                    max(safeAreaInsets.bottom, 8)
                )
            } else {
                PlayerOptionsSheet(
                    panel: panel,
                    model: model
                ) {
                    activePanel = nil
                }
                .padding(.horizontal, 10)
                .padding(
                    .bottom,
                    max(safeAreaInsets.bottom, 8)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Shared Playback Failure Presentation
    private func playbackErrorOverlay(_ error: String) -> some View {
        KinetiqUnifiedPlayerFailureOverlay(
            message: error,
            onRetry: {
                model.retryPlayback()
                revealControls()
            },
            onSkip: {
                model.next()
                revealControls()
            }
        )
    }

    // MARK: Controls Visibility

    private func toggleControls() {
        if controlsVisible {
            cancelAutoHide()

            withAnimation(.easeInOut(duration: 0.22)) {
                controlsVisible = false
            }
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.22)) {
            controlsVisible = true
        }

        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        cancelAutoHide()

        guard model.isPlaying,
              activePanel == nil,
              !isSeeking else {
            return
        }

        autoHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: autoHideDelay)

                guard !Task.isCancelled,
                      model.isPlaying,
                      activePanel == nil,
                      !isSeeking else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.28)) {
                    controlsVisible = false
                }
            } catch {
                // A user interaction cancelled the pending hide.
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}

// MARK: - Player Options Sheet

private struct PlayerOptionsSheet: View {
    let panel: PlayerPanel

    @ObservedObject var model: KinetiqPlaybackModel

    let onClose: () -> Void

    private let speeds: [Float] = [
        0.5,
        0.75,
        1.0,
        1.25,
        1.5,
        1.75,
        2.0
    ]

    var body: some View {
        KinetiqUnifiedPlayerOptionsFrame(
            title: panel.rawValue,
            symbol: panel.symbol,
            onClose: onClose
        ) {
            panelContent
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .episodes:
            unavailableContent(
                symbol: "list.number",
                title: "No episode list",
                message: """
                This is a standalone local video. Episode navigation will \
                become available when a catalogue or module provides \
                episode information.
                """
            )

        case .servers:
            VStack(alignment: .leading, spacing: 12) {
                optionRow(
                    title: "On this device",
                    subtitle: "Local file",
                    symbol: "iphone",
                    selected: true
                )

                Text(
                    "Alternative servers and stream sources will appear here when a connected source provides them."
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .padding(.top, 4)
            }

        case .audio:
            if model.audioOptions.isEmpty {
                unavailableContent(
                    symbol: "waveform",
                    title: "No alternate audio tracks",
                    message: """
                    This file does not expose selectable audio tracks.
                    """
                )
            } else {
                optionRow(
                    title: "Automatic / Default",
                    subtitle: "Use the default audio selection",
                    symbol: "speaker.wave.2",
                    selected: model.selectedAudio == nil
                ) {
                    model.selectAudio(nil)
                }

                ForEach(
                    Array(model.audioOptions.enumerated()),
                    id: \.offset
                ) { _, option in
                    optionRow(
                        title: option.displayName,
                        subtitle: option.locale?.identifier ?? "Audio track",
                        symbol: "waveform",
                        selected: model.selectedAudio == option
                    ) {
                        model.selectAudio(option)
                    }
                }
            }

        case .playback:
            VStack(alignment: .leading, spacing: 13) {
                sectionLabel("PLAYBACK SPEED")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 9
                ) {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            model.setRate(speed)
                        } label: {
                            Text(String(format: "%.2fx", speed))
                                .font(
                                    .system(
                                        size: 13,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    model.playbackRate == speed
                                        ? .black
                                        : .white
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    model.playbackRate == speed
                                        ? KinetiqPalette.cyan
                                        : .white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 11)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("ASPECT RATIO")

                optionRow(
                    title: "Fit",
                    subtitle: "Show the complete video",
                    symbol: "arrow.left.and.right",
                    selected: !model.aspectFill
                ) {
                    model.aspectFill = false
                }

                optionRow(
                    title: "Fill",
                    subtitle: "Fill the screen (may crop edges)",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    selected: model.aspectFill
                ) {
                    model.aspectFill = true
                }
            }

        case .subtitles:
            if model.captionChoice != .settings {
                Button("Use saved subtitle default") { model.useSubtitleDefault() }
                    .buttonStyle(.bordered)
                    .tint(KinetiqPalette.accent)
            }
            if model.requiresEmbeddedSubtitle {
                Text("This file requires an embedded subtitle track.").font(.caption)
            }
            if !model.hasSubtitleSelection
                && model.subtitleOptions.isEmpty {
                unavailableContent(
                    symbol: "captions.bubble",
                    title: "No subtitle tracks",
                    message: """
                    This file does not expose selectable embedded subtitles.
                    """
                )
            } else {
                optionRow(
                    title: "Off",
                    subtitle: "Disable subtitles",
                    symbol: "nosign",
                    selected: model.selectedSubtitle == nil
                ) {
                    model.selectSubtitle(nil)
                }
                .disabled(model.requiresEmbeddedSubtitle)

                ForEach(
                    Array(model.subtitleOptions.enumerated()),
                    id: \.offset
                ) { _, option in
                    optionRow(
                        title: option.displayName,
                        subtitle: option.locale?.identifier ?? "Subtitle track",
                        symbol: "captions.bubble",
                        selected: model.selectedSubtitle == option
                    ) {
                        model.selectSubtitle(option)
                    }
                }
            }

        case .queue:
            unavailableContent(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Queue",
                message: "Open the Queue tab to manage upcoming videos."
            )

        case .more:
            VStack(alignment: .leading, spacing: 13) {
                sectionLabel("SLEEP TIMER")

                HStack(spacing: 9) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button {
                            model.setSleepTimer(minutes)
                        } label: {
                            Text("\(minutes)m")
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    model.sleepTimerMinutes == minutes
                                        ? .black
                                        : .white
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    model.sleepTimerMinutes == minutes
                                        ? KinetiqPalette.cyan
                                        : .white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let minutes = model.sleepTimerMinutes {
                    HStack {
                        Label(
                            "Timer set: \(minutes) minutes",
                            systemImage: "moon.zzz.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(KinetiqPalette.cyan)

                        Spacer()

                        Button("Cancel") {
                            model.setSleepTimer(nil)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("MEDIA INFORMATION")

                informationRow(
                    "File",
                    value: model.currentURL.lastPathComponent
                )

                informationRow(
                    "Format",
                    value: model.currentURL.pathExtension.uppercased()
                )

                informationRow(
                    "Resolution",
                    value: model.resolutionText
                )

                informationRow(
                    "File size",
                    value: model.fileSizeText
                )

                informationRow(
                    "Duration",
                    value: model.formattedDuration
                )

                informationRow(
                    "Playback speed",
                    value: String(
                        format: "%.2fx",
                        model.playbackRate
                    )
                )
            }
        }
    }

    // MARK: Reusable Options

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(
                .system(
                    size: 10,
                    weight: .bold,
                    design: .rounded
                )
            )
            .tracking(1.3)
            .foregroundStyle(.white.opacity(0.48))
    }

    private func optionRow(
        title: String,
        subtitle: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        selected
                            ? KinetiqPalette.cyan
                            : .white.opacity(0.65)
                    )
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(
                            .system(
                                size: 13,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 5)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KinetiqPalette.cyan)
                }
            }
            .padding(12)
            .background(
                selected
                    ? KinetiqPalette.cyan.opacity(0.12)
                    : .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func unavailableContent(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(KinetiqPalette.cyan)

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func informationRow(
        _ title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.white.opacity(0.52))

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.system(size: 11, weight: .medium))
    }
}
