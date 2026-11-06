
// MARK: - Module Playback Engine

@MainActor
private final class KinetiqModulePlaybackModel: ObservableObject {

    let player = AVPlayer()

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var playbackError: String?

    @Published var playbackRate: Float = 1.0
    @Published var aspectFill = false

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var currentStream: ModuleResolvedStream?
    private(set) var currentStreamID: UUID?

    private var shouldAutoplay = true

    var onItemFinished: (() -> Void)?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true

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
                    self.currentTime = max(0, seconds)
                }

                self.isPlaying = self.player.rate > 0

                self.isBuffering =
                    self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    // MARK: Stream Loading

    func load(
        _ stream: ModuleResolvedStream,
        force: Bool = false
    ) {
        guard force || currentStreamID != stream.id else {
            return
        }

        currentStream = stream
        currentStreamID = stream.id

        currentTime = 0
        duration = 0

        playbackError = nil
        isPlaying = false
        isBuffering = true

        shouldAutoplay = true

        statusObservation?.invalidate()
        statusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player.pause()

        // Preserve the headers returned by the module.
        let asset = AVURLAsset(
            url: stream.url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": stream.headers
            ]
        )

        let item = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: item)

        observe(item)
        observeCompletion(of: item)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation?.invalidate()

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
                    let loadedDuration = observedItem.duration.seconds

                    self.duration = loadedDuration.isFinite
                        ? max(0, loadedDuration)
                        : 0

                    self.isBuffering = false

                    if self.shouldAutoplay {
                        self.player.playImmediately(
                            atRate: self.playbackRate
                        )

                        self.isPlaying = true
                    }

                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false

                    self.playbackError =
                        observedItem.error?.localizedDescription
                        ?? "Kinetiq could not play this module stream."

                default:
                    self.isBuffering = true
                }
            }
        }
    }

    private func observeCompletion(of item: AVPlayerItem) {
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

                self.isPlaying = false
                self.onItemFinished?()
            }
        }
    }

    // MARK: Playback Controls

    func play() {
        guard player.currentItem != nil else { return }

        shouldAutoplay = true
        playbackError = nil

        if player.currentItem?.status == .readyToPlay {
            player.playImmediately(atRate: playbackRate)
        } else {
            player.play()
        }

        isPlaying = true
    }

    func pause() {
        shouldAutoplay = false

        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        let safeTime: Double

        if duration > 0 {
            safeTime = min(max(seconds, 0), duration)
        } else {
            safeTime = max(seconds, 0)
        }

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

    func setRate(_ rate: Float) {
        playbackRate = rate

        guard isPlaying else { return }

        player.rate = rate
    }

    func retryCurrentStream() {
        guard let currentStream else {
            playbackError = "There is no stream to retry."
            return
        }

        load(currentStream, force: true)
    }

    // MARK: Cleanup

    func stop() {
        shouldAutoplay = false

        player.pause()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        statusObservation?.invalidate()
        statusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player.replaceCurrentItem(with: nil)

        isPlaying = false
        isBuffering = false
    }
}

// MARK: - Module Player Panels

private enum KinetiqModulePlayerPanel: String, CaseIterable, Identifiable, Equatable {
    case episodes = "Episodes"
    case playback = "Playback"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .episodes:
            "list.number"

        case .playback:
            "slider.horizontal.3"
        }
    }
}

// MARK: - Kinetiq Module Player

struct KinetiqModulePlayerView: View {

    @ObservedObject private var session: ModuleEpisodePlaybackSession

    @StateObject private var model = KinetiqModulePlaybackModel()

    @StateObject private var pictureInPicture =
        KinetiqPictureInPictureController()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controlsVisible = true

    @State private var activePanel: KinetiqModulePlayerPanel?

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    @State private var autoHideTask: Task<Void, Never>?

    private let autoHideDelay: Duration = .seconds(3.4)

    private let speeds: [Float] = [
        0.5,
        0.75,
        1.0,
        1.25,
        1.5,
        1.75,
        2.0
    ]

    init(session: ModuleEpisodePlaybackSession) {
        self.session = session
    }

    private var displayedTime: Double {
        isSeeking ? seekPosition : model.currentTime
    }

    private var displayedError: String? {
        model.playbackError ?? session.playbackError
    }

    // MARK: Body

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

                if controlsVisible {
                    controlOverlay(
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

                if (model.isBuffering || session.isResolving)
                    && displayedError == nil {
                    ProgressView()
                        .tint(KinetiqPalette.cyan)
                        .scaleEffect(1.25)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                if let displayedError {
                    playbackErrorOverlay(displayedError)
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

                        model.skip(by: isLeftSide ? -10 : 10)
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
                model.onItemFinished = {
                    Task {
                        await session.playNext()
                    }
                }

                if let stream = session.currentStream {
                    model.load(stream)
                }

                revealControls()
            }
            .onDisappear {
                autoHideTask?.cancel()
                autoHideTask = nil

                model.stop()
                pictureInPicture.stop()
            }
            .onChange(of: session.currentStream?.id) { _, _ in
                guard let stream = session.currentStream else {
                    return
                }

                model.load(stream)
                revealControls()
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
            .onChange(of: pictureInPicture.isActive) { _, active in
                if active {
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

    // MARK: Control Overlay

    private func controlOverlay(
        safeAreaInsets: EdgeInsets
    ) -> some View {
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
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Top Controls

    private var topControls: some View {
        HStack(spacing: 11) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        .black.opacity(0.34),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 3) {
                Text(session.sourceName.uppercased())
                    .font(
                        .system(
                            size: 9,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.5)
                    .foregroundStyle(KinetiqPalette.cyan)

                Text(session.currentEpisodeTitle)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(session.selectedLanguage.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 4)

            KinetiqAirPlayPicker()
                .frame(width: 40, height: 40)
                .background(
                    .black.opacity(0.34),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .accessibilityLabel("AirPlay")

            if pictureInPicture.isPossible {
                Button {
                    pictureInPicture.start()
                } label: {
                    Image(systemName: "pip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            .black.opacity(0.34),
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Start Picture in Picture")
            }

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
                .background(
                    .black.opacity(0.34),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
            }
            .accessibilityLabel(
                model.aspectFill
                    ? "Fit video to screen"
                    : "Fill screen with video"
            )
        }
    }

    // MARK: Centre Controls

    private var centreControls: some View {
        HStack(spacing: 13) {
            Button {
                Task {
                    await session.playPrevious()
                }

                revealControls()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 52)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous episode")

            Button {
                model.skip(by: -10)
                revealControls()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 58)
                    .contentShape(Rectangle())
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
                Image(
                    systemName: model.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                )
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 72, height: 72)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().fill(.black.opacity(0.18))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(0.28),
                    radius: 18,
                    y: 7
                )
            }
            .accessibilityLabel(
                model.isPlaying ? "Pause" : "Play"
            )

            Button {
                model.skip(by: 10)
                revealControls()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 58)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Forward 10 seconds")

            Button {
                Task {
                    await session.playNext()
                }

                revealControls()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 52)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next episode")
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom Controls

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
                    Text(
                        KinetiqPlaybackModel.formatTime(displayedTime)
                    )

                    Spacer()

                    Text(
                        KinetiqPlaybackModel.formatTime(model.duration)
                    )
                }
                .font(
                    .system(
                        size: 10,
                        weight: .semibold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(.white.opacity(0.88))
            }

            modulePlayerMenuBar
        }
    }

    private var modulePlayerMenuBar: some View {
        HStack(spacing: 1) {
            ForEach(KinetiqModulePlayerPanel.allCases) { panel in
                Button {
                    activePanel = activePanel == panel
                        ? nil
                        : panel

                    controlsVisible = true
                    cancelAutoHide()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: panel.symbol)
                            .font(
                                .system(
                                    size: 15,
                                    weight: .semibold
                                )
                            )

                        Text(panel.rawValue)
                            .font(
                                .system(
                                    size: 8,
                                    weight: .semibold
                                )
                            )
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        activePanel == panel
                            ? KinetiqPalette.cyan
                            : .white.opacity(0.92)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            Capsule().fill(.black.opacity(0.27))
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.22),
            radius: 16,
            y: 6
        )
    }

    // MARK: Options Overlay

    private func optionsOverlay(
        for panel: KinetiqModulePlayerPanel,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    activePanel = nil
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 38, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                HStack {
                    Label(
                        panel.rawValue,
                        systemImage: panel.symbol
                    )
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                    Spacer()

                    Button {
                        activePanel = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(
                                .white.opacity(0.10),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Close options")
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)

                ScrollView {
                    Group {
                        switch panel {
                        case .episodes:
                            episodesPanel

                        case .playback:
                            playbackPanel
                        }
                    }
                    .padding(18)
                }
                .frame(maxHeight: 390)
            }
            .background(.ultraThinMaterial)
            .background(
                Color(
                    red: 0.035,
                    green: 0.045,
                    blue: 0.065
                )
                .opacity(0.92)
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
            .shadow(
                color: .black.opacity(0.32),
                radius: 25,
                y: -5
            )
            .padding(.horizontal, 10)
            .padding(
                .bottom,
                max(safeAreaInsets.bottom, 8)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: Episode Panel

    private var episodesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(session.episodes.count) episodes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))

            if session.episodes.isEmpty {
                Text("This source did not return an episode list.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(session.episodes) { episode in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Episode \(episode.number)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)

                            if session.currentEpisode?.id == episode.id {
                                Text("NOW PLAYING")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(KinetiqPalette.cyan)
                            } else {
                                Text("Select this episode")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                        }

                        Spacer(minLength: 5)

                        if episode.subAvailable {
                            Button("SUB") {
                                selectEpisode(
                                    episode,
                                    language: "sub"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(KinetiqPalette.cyan)
                            .disabled(session.isResolving)
                        }

                        if episode.dubAvailable {
                            Button("DUB") {
                                selectEpisode(
                                    episode,
                                    language: "dub"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(KinetiqPalette.cyan)
                            .disabled(session.isResolving)
                        }

                        if !episode.subAvailable && !episode.dubAvailable {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(
                        session.currentEpisode?.id == episode.id
                            ? KinetiqPalette.cyan.opacity(0.12)
                            : .white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }

            if session.isResolving {
                HStack(spacing: 9) {
                    ProgressView()
                        .tint(KinetiqPalette.cyan)

                    Text("Resolving episode stream…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 4)
            }
        }
    }

    private func selectEpisode(
        _ episode: ModuleAnimeEpisode,
        language: String
    ) {
        Task {
            let succeeded = await session.play(
                episode: episode,
                language: language
            )

            if succeeded {
                activePanel = nil
                revealControls()
            }
        }
    }

    // MARK: Playback Panel

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PLAYBACK SPEED")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.48))

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

            Text("ASPECT RATIO")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.48))

            moduleOptionRow(
                title: "Fit",
                subtitle: "Show the complete video",
                symbol: "arrow.left.and.right",
                selected: !model.aspectFill
            ) {
                model.aspectFill = false
            }

            moduleOptionRow(
                title: "Fill",
                subtitle: "Fill the screen; edges may be cropped",
                symbol: "arrow.up.left.and.arrow.down.right",
                selected: model.aspectFill
            ) {
                model.aspectFill = true
            }
        }
    }

    private func moduleOptionRow(
        title: String,
        subtitle: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
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

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

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

    // MARK: Playback Error

    private func playbackErrorOverlay(
        _ error: String
    ) -> some View {
        VStack(spacing: 12) {
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

            HStack(spacing: 10) {
                Button {
                    Task {
                        _ = await session.retryCurrent()
                    }

                    revealControls()
                } label: {
                    Label(
                        "Try again",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        KinetiqPalette.cyan,
                        in: Capsule()
                    )
                }

                Button {
                    Task {
                        await session.playNext()
                    }

                    revealControls()
                } label: {
                    Label(
                        "Next episode",
                        systemImage: "forward.end.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        .white.opacity(0.13),
                        in: Capsule()
                    )
                }
            }
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
                // A new interaction cancelled the pending hide.
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
