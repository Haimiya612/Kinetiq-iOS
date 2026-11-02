import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit

// MARK: - Local Media

private struct LocalMedia: Identifiable {
    let url: URL

    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
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

            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KinetiqMedia", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

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
                                    colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
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
                    Label("Photo Library", systemImage: "photo.on.rectangle")
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
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
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
                Task { await importPhotos(newItems) }
            }
            .onChange(of: requestedMediaID) { _, _ in
                openRequestedMediaIfAvailable()
            }
            .onChange(of: media.map(\.id)) { _, _ in
                openRequestedMediaIfAvailable()
            }
            .fullScreenCover(item: $selectedMedia) { item in
                LocalVideoPlayerView(url: item.url)
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
                Button("OK", role: .cancel) { errorMessage = nil }
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
        guard let requestedMediaID else {
            return
        }

        if let item = media.first(where: { $0.id == requestedMediaID }) {
            self.requestedMediaID = nil
            selectedMedia = item
            return
        }

        // Remove history for a file that no longer exists in the local library.
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
                            colors: [KinetiqPalette.cyan, KinetiqPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Your library starts here.")
                    .font(.system(size: 23, weight: .bold, design: .rounded))

                Text("Bring your own media into Kinetiq.\nYour imported videos stay on your device.")
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
                            colors: [KinetiqPalette.cyan, KinetiqPalette.blue, KinetiqPalette.violet],
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
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(KinetiqPalette.cyan)

                        Text("\(media.count) videos")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
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
                            Label("Remove from library", systemImage: "trash")
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
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(
                        LinearGradient(
                            colors: [KinetiqPalette.cyan.opacity(0.2), KinetiqPalette.violet.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(KinetiqPalette.cyan)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.url.pathExtension.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
                    Label("On this device", systemImage: "iphone")
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

                let fileExtension = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
                let filename = UUID().uuidString + "." + fileExtension
                let destinationURL = mediaDirectory.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
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
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
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
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                .map { LocalMedia(url: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMedia(_ item: LocalMedia) {
        do {
            try FileManager.default.removeItem(at: item.url)
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
    case more = "More"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .episodes: "list.number"
        case .servers: "server.rack"
        case .audio: "waveform"
        case .playback: "slider.horizontal.3"
        case .subtitles: "captions.bubble"
        case .more: "ellipsis.circle"
        }
    }
}

// MARK: - Playback Engine

@MainActor
private final class KinetiqPlaybackModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var playbackError: String?

    @Published var audioOptions: [AVMediaSelectionOption] = []
    @Published var subtitleOptions: [AVMediaSelectionOption] = []
    @Published var selectedAudio: AVMediaSelectionOption?
    @Published var selectedSubtitle: AVMediaSelectionOption?
    @Published var hasAudioSelection = false
    @Published var hasSubtitleSelection = false

    @Published var playbackRate: Float = 1.0
    @Published var aspectFill = false
    @Published var sleepTimerMinutes: Int?

    let url: URL

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var sleepTask: Task<Void, Never>?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?

    private var lastSavedPosition: Double = 0
    private var hasRestoredProgress = false

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
        configurePlayer()
    }

    var formattedCurrentTime: String { Self.formatTime(currentTime) }
    var formattedDuration: String { Self.formatTime(duration) }

    private func configurePlayer() {
        player.automaticallyWaitsToMinimizeStalling = true

        statusObservation = player.currentItem?.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    self.isBuffering = false
                    let loadedDuration = item.duration.seconds
                    self.duration = loadedDuration.isFinite ? loadedDuration : 0
                    self.restorePlaybackProgressIfNeeded()

                case .failed:
                    self.isBuffering = false
                    self.playbackError = item.error?.localizedDescription
                        ?? "Unable to play this video."

                default:
                    self.isBuffering = true
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let seconds = time.seconds

                if seconds.isFinite {
                    self.currentTime = seconds

                    // Save periodically to protect progress if the app closes unexpectedly.
                    if self.duration > 0,
                       abs(seconds - self.lastSavedPosition) >= 5 {
                        self.saveProgress()
                    }
                }

                self.isPlaying = self.player.rate != 0
            }
        }

        Task {
            await loadMediaOptions()
        }
    }

    // MARK: Resume Playback

    private func restorePlaybackProgressIfNeeded() {
        guard !hasRestoredProgress else {
            return
        }

        hasRestoredProgress = true

        guard duration > 0 else {
            return
        }

        let savedPosition = PlaybackHistoryStore.shared.resumePosition(
            for: url.lastPathComponent
        )

        guard savedPosition >= 8,
              savedPosition < duration * 0.97 else {
            return
        }

        currentTime = savedPosition
        lastSavedPosition = savedPosition

        player.seek(
            to: CMTime(seconds: savedPosition, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: Save Playback

    func saveProgress() {
        guard duration.isFinite,
              duration > 0,
              currentTime.isFinite,
              currentTime >= 0 else {
            return
        }

        let title = url.deletingPathExtension().lastPathComponent

        PlaybackHistoryStore.shared.save(
            mediaID: url.lastPathComponent,
            title: title,
            position: currentTime,
            duration: duration
        )

        lastSavedPosition = currentTime
    }

    // MARK: Media Options

    private func loadMediaOptions() async {
        guard let asset = player.currentItem?.asset else { return }

        do {
            let audio = try await asset.loadMediaSelectionGroup(for: .audible)
            let subtitles = try await asset.loadMediaSelectionGroup(for: .legible)

            audioGroup = audio
            subtitleGroup = subtitles
            audioOptions = audio?.options ?? []
            subtitleOptions = subtitles?.options ?? []
            hasAudioSelection = audio != nil
            hasSubtitleSelection = subtitles?.allowsEmptySelection ?? false

            if let audio {
                selectedAudio = player.currentItem?.currentMediaSelection.selectedMediaOption(in: audio)
            }

            if let subtitles {
                selectedSubtitle = player.currentItem?.currentMediaSelection.selectedMediaOption(in: subtitles)
            }
        } catch {
            playbackError = error.localizedDescription
        }
    }

    // MARK: Playback Controls

    func play() {
        playbackError = nil
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        saveProgress()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let safeTime = min(max(seconds, 0), max(duration, 0))

        player.seek(
            to: CMTime(seconds: safeTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate

        if isPlaying {
            player.rate = rate
        }
    }

    func selectAudio(_ option: AVMediaSelectionOption?) {
        guard let group = audioGroup else { return }
        player.currentItem?.select(option, in: group)
        selectedAudio = option
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let group = subtitleGroup else { return }
        player.currentItem?.select(option, in: group)
        selectedSubtitle = option
    }

    // MARK: Sleep Timer

    func setSleepTimer(_ minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerMinutes = minutes

        guard let minutes else { return }

        sleepTask = Task {
            do {
                try await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                pause()
                sleepTimerMinutes = nil
            } catch {
                // The timer was cancelled or replaced.
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

        player.pause()
        player.replaceCurrentItem(with: nil)
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
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - AVPlayer Layer Surface

private final class KinetiqPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct KinetiqPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let aspectFill: Bool

    func makeUIView(context: Context) -> KinetiqPlayerUIView {
        let view = KinetiqPlayerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ uiView: KinetiqPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
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
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var model: KinetiqPlaybackModel

    @State private var controlsVisible = true
    @State private var activePanel: PlayerPanel?
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var autoHideTask: Task<Void, Never>?

    private let autoHideDelay: Duration = .seconds(3.4)

    init(url: URL) {
        self.url = url
        _model = StateObject(
            wrappedValue: KinetiqPlaybackModel(url: url)
        )
    }

    private var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    private var displayedTime: Double {
        isSeeking ? seekPosition : model.currentTime
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                // The video surface always occupies the complete presentation area.
                KinetiqPlayerSurface(
                    player: model.player,
                    aspectFill: model.aspectFill
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .background(.black)

                // This transparent hit target toggles the HUD without changing layout.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleControls)
                    .accessibilityLabel("Show or hide playback controls")

                if controlsVisible {
                    controlOverlay(safeAreaInsets: geometry.safeAreaInsets)
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

                if let error = model.playbackError {
                    playbackErrorOverlay(error)
                        .zIndex(4)
                }

                if let activePanel {
                    optionsOverlay(
                        for: activePanel,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .background(.black)
            .clipped()
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
                model.play()
                revealControls()
            }
            .onDisappear {
                autoHideTask?.cancel()
                autoHideTask = nil
                model.stop()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                model.saveProgress()
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
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(.black)
    }

    // MARK: Overlay Layout

    private func controlOverlay(safeAreaInsets: EdgeInsets) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.58), location: 0),
                    .init(color: .clear, location: 0.27),
                    .init(color: .clear, location: 0.60),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topControls
                    .padding(.top, max(safeAreaInsets.top, 14))

                Spacer(minLength: 18)

                centreControls

                Spacer(minLength: 18)

                bottomControls
                    .padding(.bottom, max(safeAreaInsets.bottom, 15))
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topControls: some View {
        HStack(spacing: 13) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.34), in: Circle())
                    .overlay(
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 3) {
                Text("NOW PLAYING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(KinetiqPalette.cyan)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                model.aspectFill.toggle()
                scheduleAutoHide()
            } label: {
                Image(
                    systemName: model.aspectFill
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.34), in: Circle())
                .overlay(
                    Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                )
            }
            .accessibilityLabel(
                model.aspectFill
                    ? "Fit video to screen"
                    : "Fill screen with video"
            )
        }
    }

    private var centreControls: some View {
        HStack(spacing: 34) {
            Button {
                model.skip(by: -10)
                scheduleAutoHide()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Back 10 seconds")

            Button {
                model.togglePlayback()

                if model.isPlaying {
                    scheduleAutoHide()
                } else {
                    cancelAutoHide()

                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                }
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().fill(.black.opacity(0.18)))
                    .overlay(
                        Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(
                        color: .black.opacity(0.28),
                        radius: 18,
                        y: 7
                    )
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            Button {
                model.skip(by: 10)
                scheduleAutoHide()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Forward 10 seconds")
        }
        .buttonStyle(.plain)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { displayedTime },
                        set: { newValue in
                            isSeeking = true
                            seekPosition = newValue
                        }
                    ),
                    in: 0...max(model.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            cancelAutoHide()
                        } else {
                            model.seek(to: seekPosition)
                            isSeeking = false
                            scheduleAutoHide()
                        }
                    }
                )
                .tint(KinetiqPalette.cyan)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(KinetiqPlaybackModel.formatTime(displayedTime))
                    Spacer()
                    Text(model.formattedDuration)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
            }

            playerMenuBar
        }
    }

    private var playerMenuBar: some View {
        HStack(spacing: 2) {
            ForEach(PlayerPanel.allCases) { panel in
                Button {
                    if activePanel == panel {
                        activePanel = nil
                    } else {
                        activePanel = panel
                    }

                    controlsVisible = true
                    cancelAutoHide()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: panel.symbol)
                            .font(.system(size: 16, weight: .semibold))

                        Text(panel.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(
                        activePanel == panel
                            ? KinetiqPalette.cyan
                            : .white.opacity(0.92)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.rawValue)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(.black.opacity(0.27)))
        .overlay(
            Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    // MARK: Options Overlay

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

            PlayerOptionsSheet(panel: panel, model: model) {
                activePanel = nil
            }
            .padding(.horizontal, 10)
            .padding(.bottom, max(safeAreaInsets.bottom, 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func playbackErrorOverlay(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Playback issue")
                .font(.headline)
                .foregroundStyle(.white)

            Text(error)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Button("Try again") {
                model.play()
                revealControls()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(KinetiqPalette.cyan, in: Capsule())
            .padding(.top, 5)
        }
        .padding(24)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(30)
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
        0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack {
                HStack(spacing: 10) {
                    Image(systemName: panel.symbol)
                        .foregroundStyle(KinetiqPalette.cyan)

                    Text(panel.rawValue)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Close options")
            }
            .padding(.horizontal, 19)
            .padding(.bottom, 14)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    panelContent
                }
                .padding(18)
            }
            .frame(maxHeight: 370)
        }
        .background(.ultraThinMaterial)
        .background(
            Color(red: 0.035, green: 0.045, blue: 0.065).opacity(0.90)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
            .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 25, y: -5)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .episodes:
            unavailableContent(
                symbol: "list.number",
                title: "No episode list",
                message: "This is a standalone local video. Episode navigation will become available when Kinetiq receives episode information from a catalogue or module."
            )

        case .servers:
            VStack(alignment: .leading, spacing: 12) {
                optionRow(
                    title: "On this device",
                    subtitle: "Local file",
                    symbol: "iphone",
                    selected: true
                )

                Text("Alternative servers and stream sources will appear here when a connected module provides them.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 4)
            }

        case .audio:
            if model.audioOptions.isEmpty {
                unavailableContent(
                    symbol: "waveform",
                    title: "No alternate audio tracks",
                    message: "This file does not expose selectable audio tracks."
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
                                .font(.system(size: 13, weight: .bold))
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
            if !model.hasSubtitleSelection && model.subtitleOptions.isEmpty {
                unavailableContent(
                    symbol: "captions.bubble",
                    title: "No subtitle tracks",
                    message: "This file does not expose selectable embedded subtitles."
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

        case .more:
            VStack(alignment: .leading, spacing: 13) {
                sectionLabel("SLEEP TIMER")

                HStack(spacing: 9) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button {
                            model.setSleepTimer(minutes)
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 12, weight: .bold))
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

                sectionLabel("PLAYBACK INFORMATION")
                informationRow("File", value: model.url.lastPathComponent)
                informationRow("Format", value: model.url.pathExtension.uppercased())
                informationRow("Duration", value: model.formattedDuration)
                informationRow(
                    "Playback speed",
                    value: String(format: "%.2fx", model.playbackRate)
                )
            }
        }
    }

    // MARK: Reusable Options

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
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
                        .font(.system(size: 13, weight: .semibold))
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
