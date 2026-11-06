import SwiftUI
import AVKit
import AVFoundation
import Combine
import UIKit

// MARK: - Module Player

/// Native AVPlayer surface for remote streams resolved by a module.
/// This player has its own playback state and never writes to the local
/// media queue or local playback history.
@MainActor
struct KinetiqModulePlayerView: View {

    @ObservedObject private var session: ModuleEpisodePlaybackSession
    @StateObject private var playback: ModulePlayerPlaybackController

    @Environment(\.dismiss) private var dismiss

    @State private var showingEpisodes = false
    @State private var showingPlaybackOptions = false
    @State private var isShowingControls = true

    init(session: ModuleEpisodePlaybackSession) {
        self._session = ObservedObject(wrappedValue: session)
        self._playback = StateObject(
            wrappedValue: ModulePlayerPlaybackController(session: session)
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ModulePlayerSurface(
                player: playback.player,
                aspectFill: playback.isAspectFill
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingControls.toggle()
                }
            }

            if playback.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.25)
                    .allowsHitTesting(false)
            }

            if isShowingControls {
                playerControls
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingEpisodes) {
            episodePicker
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            "Playback Options",
            isPresented: $showingPlaybackOptions,
            titleVisibility: .visible
        ) {
            Button(playback.isAspectFill ? "Use Fit" : "Use Fill") {
                playback.isAspectFill.toggle()
            }

            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button(String(format: "%.2fx Speed", rate)) {
                    playback.setRate(Float(rate))
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Playback",
            isPresented: Binding(
                get: { playback.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        playback.dismissError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                playback.dismissError()
            }
        } message: {
            Text(playback.errorMessage ?? "The stream could not be played.")
        }
        .onDisappear {
            playback.stop()
        }
    }

    // MARK: Controls

    private var playerControls: some View {
        VStack(spacing: 0) {
            header

            Spacer()

            centerControls

            Spacer()

            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.78), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Button {
                playback.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.13), in: Circle())
            }
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 4) {
                Text(session.animeTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(session.sourceName)  •  \(session.currentEpisodeTitle)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            ModuleAirPlayButton()
                .frame(width: 39, height: 39)
                .accessibilityLabel("AirPlay")

            Menu {
                Button {
                    showingEpisodes = true
                } label: {
                    Label("Episodes", systemImage: "list.number")
                }

                Button {
                    showingPlaybackOptions = true
                } label: {
                    Label("Playback Options", systemImage: "slider.horizontal.3")
                }

                if let episode = session.currentEpisode {
                    Menu("Language") {
                        if session.supports("sub", for: episode) {
                            Button {
                                playback.selectLanguage("sub")
                            } label: {
                                if session.selectedLanguage == "sub" {
                                    Label("Sub", systemImage: "checkmark")
                                } else {
                                    Text("Sub")
                                }
                            }
                        }

                        if session.supports("dub", for: episode) {
                            Button {
                                playback.selectLanguage("dub")
                            } label: {
                                if session.selectedLanguage == "dub" {
                                    Label("Dub", systemImage: "checkmark")
                                } else {
                                    Text("Dub")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.13), in: Circle())
            }
            .accessibilityLabel("More player options")
        }
    }

    private var centerControls: some View {
        HStack(spacing: 34) {
            Button {
                playback.playPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Previous episode")

            Button {
                playback.seek(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Back 10 seconds")

            Button {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 68, height: 68)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button {
                playback.seek(by: 10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Forward 10 seconds")

            Button {
                playback.playNext()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Next episode")
        }
        .buttonStyle(.plain)
        .disabled(playback.isResolvingEpisode)
        .opacity(playback.isResolvingEpisode ? 0.55 : 1)
    }

    private var footer: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                Text(playback.formattedCurrentTime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(minWidth: 42, alignment: .leading)

                Slider(
                    value: $playback.scrubPosition,
                    in: 0...max(playback.duration, 1),
                    onEditingChanged: { editing in
                        playback.setScrubbing(editing)
                    }
                )
                .tint(KinetiqPalette.accent)

                Text(playback.formattedDuration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(minWidth: 42, alignment: .trailing)
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(KinetiqPalette.accent)
                        .frame(width: 6, height: 6)

                    Text(session.selectedLanguage.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer()

                Button {
                    showingEpisodes = true
                } label: {
                    Label("Episodes", systemImage: "list.number")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    showingPlaybackOptions = true
                } label: {
                    Label(
                        String(format: "%.2fx", playback.playbackRate),
                        systemImage: "speedometer"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Episode Picker

    private var episodePicker: some View {
        NavigationStack {
            List {
                ForEach(session.episodes) { episode in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Episode \(episode.number)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(languageDescription(for: episode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        if episode.subAvailable {
                            Button("Sub") {
                                showingEpisodes = false
                                playback.play(episode: episode, language: "sub")
                            }
                            .buttonStyle(.bordered)
                            .tint(KinetiqPalette.accent)
                            .disabled(playback.isResolvingEpisode)
                        }

                        if episode.dubAvailable {
                            Button("Dub") {
                                showingEpisodes = false
                                playback.play(episode: episode, language: "dub")
                            }
                            .buttonStyle(.bordered)
                            .tint(KinetiqPalette.accent)
                            .disabled(playback.isResolvingEpisode)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(
                        episode.id == session.currentEpisode?.id
                            ? KinetiqPalette.accent.opacity(0.10)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingEpisodes = false
                    }
                }
            }
        }
    }

    private func languageDescription(
        for episode: ModuleAnimeEpisode
    ) -> String {
        switch (episode.subAvailable, episode.dubAvailable) {
        case (true, true):
            return "Sub and Dub"
        case (true, false):
            return "Sub"
        case (false, true):
            return "Dub"
        case (false, false):
            return "No language listed"
        }
    }
}

// MARK: - Module Playback Controller

@MainActor
private final class ModulePlayerPlaybackController: ObservableObject {

    @Published private(set) var player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var isResolvingEpisode = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0

    @Published var scrubPosition: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var isAspectFill = false

    private let session: ModuleEpisodePlaybackSession

    private var streamCancellable: AnyCancellable?
    private var errorCancellable: AnyCancellable?
    private var resolvingCancellable: AnyCancellable?
    private var timeObserver: Any?
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var lastStreamID: UUID?
    private var isScrubbing = false
    private var hasStopped = false

    init(session: ModuleEpisodePlaybackSession) {
        self.session = session

        player.automaticallyWaitsToMinimizeStalling = true

        streamCancellable = session.$currentStream
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stream in
                self?.load(stream)
            }

        errorCancellable = session.$playbackError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                if let message, !message.isEmpty {
                    self.errorMessage = message
                }
            }

        resolvingCancellable = session.$isResolving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolving in
                self?.isResolvingEpisode = resolving
            }

        installTimeObserver()
        installPlayerStatusObserver()
    }

    var formattedCurrentTime: String {
        Self.timeString(currentTime)
    }

    var formattedDuration: String {
        Self.timeString(duration)
    }

    // MARK: AVPlayer Observation

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }

                self.currentTime = seconds

                if !self.isScrubbing {
                    self.scrubPosition = seconds
                }

                if let item = self.player.currentItem {
                    let length = item.duration.seconds
                    if length.isFinite, length > 0 {
                        self.duration = length
                    }
                }
            }
        }
    }

    private func installPlayerStatusObserver() {
        playerStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.isPlaying =
                    observedPlayer.timeControlStatus == .playing

                self.isBuffering =
                    observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    // MARK: Stream Handoff

    private func load(_ stream: ModuleResolvedStream) {
        guard !hasStopped, lastStreamID != stream.id else {
            return
        }

        lastStreamID = stream.id
        errorMessage = nil
        isBuffering = true
        isPlaying = false
        duration = 0
        currentTime = 0
        scrubPosition = 0

        removeCurrentItemObservers()

        var assetOptions: [String: Any]?

        if !stream.headers.isEmpty {
            assetOptions = [
                "AVURLAssetHTTPHeaderFieldsKey": stream.headers
            ]
        }

        let asset = AVURLAsset(
            url: stream.url,
            options: assetOptions
        )

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8

        player.replaceCurrentItem(with: item)

        itemStatusObservation = item.observe(
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
                    let seconds = observedItem.duration.seconds
                    if seconds.isFinite, seconds > 0 {
                        self.duration = seconds
                    }
                    self.player.playImmediately(atRate: self.playbackRate)

                case .failed:
                    self.isBuffering = false
                    self.errorMessage =
                        observedItem.error?.localizedDescription
                        ?? "The source stream could not be opened."

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    self.isBuffering = false
                    self.errorMessage = "The player returned an unknown stream status."
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.player.currentItem === item else {
                    return
                }

                await self.session.playNext()

                if let message = self.session.playbackError,
                   !message.isEmpty {
                    self.errorMessage = message
                }
            }
        }
    }

    private func removeCurrentItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    // MARK: Playback Controls

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.playImmediately(atRate: playbackRate)
        }
    }

    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        guard duration > 0 else { return }

        let target = min(max(seconds, 0), duration)
        let time = CMTime(seconds: target, preferredTimescale: 600)

        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing

        if !scrubbing {
            seek(to: scrubPosition)
        }
    }

    func setRate(_ rate: Float) {
        let safeRate = min(max(rate, 0.5), 2.0)
        playbackRate = safeRate

        if player.timeControlStatus == .playing {
            player.rate = safeRate
        }
    }

    func selectLanguage(_ language: String) {
        guard let episode = session.currentEpisode,
              session.supports(language, for: episode) else {
            return
        }

        play(episode: episode, language: language)
    }

    func play(
        episode: ModuleAnimeEpisode,
        language: String
    ) {
        Task {
            let success = await session.play(
                episode: episode,
                language: language
            )

            if !success {
                errorMessage = session.playbackError
                    ?? "The selected episode could not be resolved."
            }
        }
    }

    func playNext() {
        Task {
            await session.playNext()

            if let message = session.playbackError,
               !message.isEmpty {
                errorMessage = message
            }
        }
    }

    func playPrevious() {
        Task {
            await session.playPrevious()

            if let message = session.playbackError,
               !message.isEmpty {
                errorMessage = message
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: Lifecycle

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        player.pause()
        removeCurrentItemObservers()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        playerStatusObservation?.invalidate()
        playerStatusObservation = nil

        streamCancellable?.cancel()
        streamCancellable = nil

        errorCancellable?.cancel()
        errorCancellable = nil

        resolvingCancellable?.cancel()
        resolvingCancellable = nil

        player.replaceCurrentItem(with: nil)
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }

        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
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
            format: "%d:%02d",
            minutes,
            remainingSeconds
        )
    }
}

// MARK: - AVPlayer Surface

private struct ModulePlayerSurface: UIViewRepresentable {

    let player: AVPlayer
    let aspectFill: Bool

    func makeUIView(context: Context) -> ModulePlayerLayerView {
        let view = ModulePlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = aspectFill
            ? .resizeAspectFill
            : .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(
        _ uiView: ModulePlayerLayerView,
        context: Context
    ) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = aspectFill
            ? .resizeAspectFill
            : .resizeAspect
    }
}

private final class ModulePlayerLayerView: UIView {

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

// MARK: - AirPlay Button

private struct ModuleAirPlayButton: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(
            red: 0.20,
            green: 0.78,
            blue: 0.95,
            alpha: 1
        )
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(
        _ uiView: AVRoutePickerView,
        context: Context
    ) {}
}