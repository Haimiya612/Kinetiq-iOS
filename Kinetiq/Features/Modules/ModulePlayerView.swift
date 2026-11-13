import SwiftUI
import AVKit
import AVFoundation
import Combine
import UIKit
import WebKit
import CoreMedia

// MARK: - Module Player Panels

// Matches the Local Library player panel order and symbols.
// Kept private to avoid clashing with LibraryView.swift's PlayerPanel.
private enum ModulePlayerPanel: String, CaseIterable, Identifiable {
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

// MARK: - Full-Screen Module Player

/// Uses the visual language of LocalVideoPlayerView, while keeping all
/// module playback state independent of the local Files/Photos queue.
@MainActor
struct KinetiqModulePlayerView: View {
    @ObservedObject private var session: ModuleEpisodePlaybackSession
    @ObservedObject private var subtitleSettings = KinetiqSubtitleSettings.shared
    @StateObject private var playback: ModulePlayerPlaybackController
    @StateObject private var pictureInPicture =
        ModulePictureInPictureController()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasOrientationLease = false
    @State private var controlsVisible = true
    @State private var activePanel: ModulePlayerPanel?
    @State private var webPlayerStream: ModuleResolvedStream?

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var seekFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var autoHideTask: Task<Void, Never>?
    // An AVKit transition can fail without a user-visible error.
    // Restore external captions if no PiP session actually starts.
    @State private var pipCaptionRollbackTask: Task<Void, Never>?
    @State private var loadingStartedAt = Date()

    private let autoHideDelay: Duration = .seconds(3.4)

    init(session: ModuleEpisodePlaybackSession) {
        _session = ObservedObject(wrappedValue: session)
        _playback = StateObject(
            wrappedValue: ModulePlayerPlaybackController(session: session)
        )
    }

    private var displayedTime: Double {
        isSeeking ? seekPosition : playback.currentTime
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ModulePlayerSurface(
                    player: playback.player,
                    aspectFill: playback.isAspectFill,
                    pictureInPicture: pictureInPicture,
                    onFirstFrame: { item in playback.registerFirstVideoFrame(item: item) }
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .background(.black)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleControls)
                    .accessibilityLabel("Show or hide playback controls")

                if let text = playback.externalSubtitles.currentText,
                   !pictureInPicture.isActive {
                    VStack {
                        Spacer()
                        KinetiqCaptionText(text: text)
                            .padding(.horizontal, 24)
                            .padding(.bottom, controlsVisible ? 130 : max(geometry.safeAreaInsets.bottom + 12, 24))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .zIndex(1)
                }

                if controlsVisible {
                    controlOverlay(
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

                // Batch 06C: an honest, user-readable loading scene replaces
                // the unexplained spinner. Diagnostics are sanitized by the
                // existing module runtime and never expose signed media URLs.
                if playback.errorMessage == nil,
                   webPlayerStream == nil,
                   (playback.isResolvingEpisode ||
                    !playback.hasFinishedPresentingFirstFrame) {
                    KinetiqModuleLoadingScene(
                        title: session.currentEpisodeTitle,
                        sourceName: ModulePlaybackDiagnostics.redact(session.sourceName, limit: 70),
                        phase: ModulePlaybackDiagnostics.redact(playback.playbackStatus, limit: 110),
                        isResolving: playback.isResolvingEpisode,
                        hasServer: session.currentStream != nil,
                        recentEvents: Array((session.resolutionDiagnosticEvents + playback.diagnosticEvents)
                            .suffix(8).map { ModulePlaybackDiagnostics.redact($0, limit: 160) }),
                        startedAt: loadingStartedAt,
                        onCopy: { UIPasteboard.general.string = playback.diagnosticSummary },
                        onClose: { dismiss() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(3)
                } else if playback.isBuffering && playback.errorMessage == nil {
                    // A brief rebuffer during existing playback should not
                    // cover the video or disable standard player controls.
                    ProgressView().tint(KinetiqPalette.cyan)
                        .scaleEffect(1.2)
                        .allowsHitTesting(false)
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
                        .background(.ultraThinMaterial, in: Capsule())
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(4)
                }

                if let error = playback.errorMessage {
                    VStack(spacing: 12) {
                        playbackErrorOverlay(error)
                        Button {
                            UIPasteboard.general.string = playback.diagnosticSummary
                        } label: {
                            Label("Copy Diagnostics", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        if let stream = session.currentStream,
                           ModuleWebFallbackPolicy.allows(stream.url) {
                            Button(action: openWebFallback) {
                                Label("Try Web Player", systemImage: "globe")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(.white.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
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

                if let webPlayerStream {
                    ModuleWebFallbackPlayer(
                        stream: webPlayerStream,
                        episodeTitle: session.currentEpisodeTitle,
                        onClose: {
                            self.webPlayerStream = nil
                            self.activePanel = .servers
                            self.revealControls()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(20)
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

                        let seconds: Double = isLeftSide ? -10 : 10
                        playback.seek(by: seconds)
                        showSeekFeedback(
                            isLeftSide ? "−10 seconds" : "+10 seconds"
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
                reduceMotion ? nil : KinetiqMotionMode.chosen.animation,
                value: activePanel
            )
            .onAppear {
                if !hasOrientationLease {
                    KinetiqPlaybackPresentation.enterPlayer()
                    hasOrientationLease = true
                }
                KinetiqPlaybackPresentation.preparePlayer(playback.player)
                revealControls()
                displayEmbeddedPlayerIfNeeded()
            }
            .onChange(of: session.currentStream?.id) { _, _ in
                loadingStartedAt = Date()
                displayEmbeddedPlayerIfNeeded()
            }
            .onChange(of: session.currentEpisode?.id) { _, _ in
                loadingStartedAt = Date()
            }
            .onDisappear {
                if hasOrientationLease {
                    KinetiqPlaybackPresentation.leavePlayer()
                    hasOrientationLease = false
                }
                autoHideTask?.cancel()
                feedbackTask?.cancel()
                pipCaptionRollbackTask?.cancel()
                if let reason = playback.errorMessage {
                    session.recordPlayerFailure(
                        diagnostics: playback.diagnosticSummary, reason: reason
                    )
                } else {
                    session.clearPlayerFailure()
                }
                if !pictureInPicture.isActive { playback.stop() }
            }
            .onChange(of: playback.errorMessage) { _, failure in
                if let failure {
                    session.recordPlayerFailure(
                        diagnostics: playback.diagnosticSummary, reason: failure
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )) { _ in
                playback.persistCurrentProgress()
                // Select a matching native legible track BEFORE AVKit starts
                // presenting its independent PiP video surface.
                if webPlayerStream == nil,
                   playback.isPlaying,
                   pictureInPicture.isPossible,
                   !pictureInPicture.isActuallyActive {
                    playback.prepareNativeCaptionsForPiP()
                    pictureInPicture.startIfLeavingAppWhilePlaying(true)
                    schedulePiPCaptionRollback()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                // System interruptions can leave the app foregrounded without
                // a successful PiP start. Never strand the external selection.
                guard !pictureInPicture.isActuallyActive else { return }
                pipCaptionRollbackTask?.cancel()
                pipCaptionRollbackTask = nil
                playback.restoreCaptionsAfterPiP()
            }
            .onChange(of: subtitleSettings.appearance) { _, style in
                playback.player.currentItem?.textStyleRules =
                    KinetiqModuleNativeCaptionStyle.rules(
                        for: style, inPiP: pictureInPicture.isActuallyActive
                    )
            }
            .onChange(of: subtitleSettings.language) { _, language in
                if playback.captionChoice == .settings { playback.refreshCaptions(preference: language) }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.mediaSelectionDidChangeNotification).receive(on: DispatchQueue.main)) { event in
                playback.syncCaptionSelection(for: event.object as? AVPlayerItem)
            }
            .onChange(of: playback.isPlaying) { _, playing in
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
                pipCaptionRollbackTask?.cancel()
                pipCaptionRollbackTask = nil
                if active {
                    // Also cover PiP that AVKit starts automatically without
                    // our willResignActive callback.
                    playback.prepareNativeCaptionsForPiP()
                    cancelAutoHide()
                    activePanel = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = false
                    }
                } else {
                    playback.restoreCaptionsAfterPiP()
                    revealControls()
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(.black)
        .alert("Picture in Picture", isPresented: Binding(
            get: { pictureInPicture.lastFailure != nil },
            set: { if !$0 { pictureInPicture.clearFailure() } }
        )) {
            Button("OK", role: .cancel) { pictureInPicture.clearFailure() }
        } message: {
            Text(pictureInPicture.lastFailure ?? "PiP isn't available for this video.")
        }
    }

    // MARK: - PiP Caption Handoff (Batch 06B)

    private func startPiPWithCaptions() {
        let eligible = pictureInPicture.isPossible &&
            !pictureInPicture.isActuallyActive
        if eligible {
            playback.prepareNativeCaptionsForPiP()
        }
        pictureInPicture.start()
        if eligible { schedulePiPCaptionRollback() }
    }

    private func schedulePiPCaptionRollback() {
        pipCaptionRollbackTask?.cancel()
        pipCaptionRollbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            guard !pictureInPicture.isActuallyActive else { return }
            playback.restoreCaptionsAfterPiP()
        }
    }

    // MARK: - Web-only Player Fallback (Batch 05C)

    private func displayEmbeddedPlayerIfNeeded() {
        guard let stream = session.currentStream else {
            webPlayerStream = nil
            return
        }
        if stream.isWebEmbed && ModuleWebFallbackPolicy.allows(stream.url) {
            playback.player.pause()
            activePanel = nil
            webPlayerStream = stream
        } else {
            webPlayerStream = nil
        }
    }

    private func openWebFallback() {
        guard let stream = session.currentStream,
              ModuleWebFallbackPolicy.allows(stream.url) else { return }
        playback.player.pause()
        activePanel = nil
        webPlayerStream = stream
    }

    // MARK: - Shared Player Chrome (Batch 05A)
    // The same component is used by local playback in LibraryView.swift.
    // The module session continues to own streams, quality, episodes and captions.

    private func controlOverlay(safeAreaInsets: EdgeInsets) -> some View {
        KinetiqUnifiedPlayerChrome(
            safeAreaInsets: safeAreaInsets,
            title: session.currentEpisodeTitle,
            playing: playback.isPlaying,
            busy: playback.isResolvingEpisode,
            aspectFill: playback.isAspectFill,
            pictureInPictureAvailable: pictureInPicture.isSupported,
            displayedTime: displayedTime,
            duration: playback.duration,
            elapsedLabel: ModulePlayerPlaybackController.timeString(displayedTime),
            durationLabel: playback.formattedDuration,
            panels: ModulePlayerPanel.allCases.map { option in
                KinetiqUnifiedPlayerChrome.Panel(
                    id: option.rawValue,
                    symbol: option.symbol,
                    selected: activePanel == option
                )
            },
            airPlayControl: AnyView(ModuleAirPlayButton()),
            onClose: { dismiss() },
            onStartPictureInPicture: { startPiPWithCaptions() },
            onToggleAspect: {
                playback.isAspectFill.toggle()
                scheduleAutoHide()
            },
            onPrevious: {
                playback.playPrevious()
                revealControls()
            },
            onRewind: {
                playback.seek(by: -10)
                showSeekFeedback("−10 seconds")
                scheduleAutoHide()
            },
            onTogglePlay: {
                playback.togglePlayback()
                if playback.isPlaying {
                    scheduleAutoHide()
                } else {
                    cancelAutoHide()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = true
                    }
                }
            },
            onForward: {
                playback.seek(by: 10)
                showSeekFeedback("+10 seconds")
                scheduleAutoHide()
            },
            onNext: {
                playback.playNext()
                revealControls()
            },
            onSeekChanged: { value in
                isSeeking = true
                seekPosition = value
            },
            onSeekEditingChanged: { editing in
                if editing {
                    cancelAutoHide()
                } else {
                    playback.seek(to: seekPosition)
                    isSeeking = false
                    scheduleAutoHide()
                }
            },
            onPanelSelected: { name in
                guard let panel = ModulePlayerPanel(rawValue: name) else { return }
                activePanel = activePanel == panel ? nil : panel
                controlsVisible = true
                cancelAutoHide()
            }
        )
    }

    // MARK: Options Overlay

    @ViewBuilder
    private func optionsOverlay(
        for panel: ModulePlayerPanel,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    activePanel = nil
                }

            ModulePlayerOptionsSheet(
                panel: panel,
                playback: playback,
                session: session,
                onOpenWebPlayer: openWebFallback
            ) {
                activePanel = nil
            }
            .padding(.horizontal, 10)
            .padding(.bottom, max(safeAreaInsets.bottom, 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Shared Playback Failure Presentation
    private func playbackErrorOverlay(_ error: String) -> some View {
        KinetiqUnifiedPlayerFailureOverlay(
            message: error,
            onRetry: {
                playback.retryCurrentStream()
                revealControls()
            },
            onSkip: {
                playback.dismissError()
                playback.playNext()
                revealControls()
            }
        )
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
                // Another gesture replaced the current seek feedback.
            }
        }
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

        guard playback.isPlaying,
              activePanel == nil,
              !isSeeking else {
            return
        }

        autoHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: autoHideDelay)

                guard !Task.isCancelled,
                      playback.isPlaying,
                      activePanel == nil,
                      !isSeeking else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.28)) {
                    controlsVisible = false
                }
            } catch {
                // Cancelled by interaction or player state.
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}

// MARK: - Module Player Options Sheet

/// Mirrors the Library player's glass bottom sheet; every selectable
/// control is connected to the module AVPlayer or module episode session.
@MainActor
private struct ModulePlayerOptionsSheet: View {
    let panel: ModulePlayerPanel
    @ObservedObject var playback: ModulePlayerPlaybackController
    @ObservedObject var session: ModuleEpisodePlaybackSession
    let onOpenWebPlayer: () -> Void
    let onClose: () -> Void

    private let speeds: [Float] = [
        0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
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
            if session.episodes.isEmpty {
                unavailableContent(
                    symbol: "list.number",
                    title: "No episodes",
                    message: "The selected source has not returned an episode list."
                )
            } else {
                episodeList
            }

        case .servers:
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("AVAILABLE SERVERS")

                if session.availableStreams.isEmpty {
                    unavailableContent(
                        symbol: "server.rack",
                        title: "No servers resolved",
                        message: "The module has not returned any playable stream choices."
                    )
                } else {
                    ForEach(session.availableStreams) { stream in
                        optionRow(
                            title: stream.label,
                            subtitle: "\(stream.hostName) • \(playback.serverHealthStatus(for: stream))",
                            symbol: "server.rack",
                            selected: session.currentStream?.id == stream.id
                        ) {
                            playback.selectServer(stream)
                            onClose()
                        }
                    }

                    if session.availableStreams.count == 1 {
                        Text("This module returned one stream. Kinetiq will retry it and refresh the episode link once if it fails; additional servers require real alternatives from the module.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    if session.availableStreams.contains(where: {
                        !$0.headers.isEmpty
                    }) {
                        Text("Some servers request custom HTTP headers. iOS may not forward those headers to every HLS segment, so a server can resolve successfully but still fail to play.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
            }

        case .audio:
            VStack(alignment: .leading, spacing: 12) {
                if let episode = session.currentEpisode,
                   episode.subAvailable || episode.dubAvailable {
                    sectionLabel("EPISODE LANGUAGE")

                    if episode.subAvailable {
                        optionRow(
                            title: "Sub",
                            subtitle: "Subtitled episode stream",
                            symbol: "captions.bubble.fill",
                            selected: session.selectedLanguage == "sub"
                        ) {
                            playback.selectLanguage("sub")
                        }
                    }

                    if episode.dubAvailable {
                        optionRow(
                            title: "Dub",
                            subtitle: "Dubbed episode stream",
                            symbol: "speaker.wave.2.fill",
                            selected: session.selectedLanguage == "dub"
                        ) {
                            playback.selectLanguage("dub")
                        }
                    }
                }

                sectionLabel("EMBEDDED AUDIO TRACKS")

                if playback.audioOptions.isEmpty {
                    unavailableContent(
                        symbol: "waveform",
                        title: "No alternate embedded audio",
                        message: "This stream does not expose selectable embedded audio tracks. Use Sub or Dub above when the source offers them."
                    )
                } else {
                    ForEach(
                        Array(playback.audioOptions.enumerated()),
                        id: \.offset
                    ) { _, option in
                        optionRow(
                            title: option.displayName,
                            subtitle: option.locale?.identifier ?? "Audio track",
                            symbol: "waveform",
                            selected: playback.selectedAudio == option
                        ) {
                            playback.selectAudio(option)
                        }
                    }
                }
            }

        case .playback:
            VStack(alignment: .leading, spacing: 13) {
                qualityOptions

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

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
                            playback.setRate(speed)
                        } label: {
                            Text(String(format: "%.2fx", speed))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(
                                    playback.playbackRate == speed
                                        ? .black
                                        : .white
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    playback.playbackRate == speed
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
                    selected: !playback.isAspectFill
                ) {
                    playback.isAspectFill = false
                }

                optionRow(
                    title: "Fill",
                    subtitle: "Fill the screen (may crop edges)",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    selected: playback.isAspectFill
                ) {
                    playback.isAspectFill = true
                }
            }

        case .subtitles:
            if playback.captionChoice != .settings {
                Button("Use saved subtitle default") { playback.useSubtitleDefault() }
                    .buttonStyle(.bordered)
                    .tint(KinetiqPalette.accent)
            }
            if playback.requiresEmbeddedSubtitle {
                Text("This stream requires an embedded subtitle track.").font(.caption)
            }
            optionRow(
                title: "Off",
                subtitle: "Disable embedded and source subtitles",
                symbol: "nosign",
                selected: playback.selectedSubtitle == nil && !playback.externalSubtitles.isRequested
            ) {
                playback.selectSubtitle(nil)
            }
            .disabled(playback.requiresEmbeddedSubtitle)

            if playback.subtitleOptions.isEmpty && playback.externalSubtitles.tracks.isEmpty {
                unavailableContent(
                    symbol: "captions.bubble",
                    title: "No selectable subtitle tracks",
                    message: "This stream exposes no embedded or supported source subtitle tracks. Sub and Dub streams remain available in Audio when the source provides them."
                )
            }

            if !playback.subtitleOptions.isEmpty {
                sectionLabel("Embedded")
                ForEach(
                    Array(playback.subtitleOptions.enumerated()),
                    id: \.offset
                ) { _, option in
                    optionRow(
                        title: option.displayName,
                        subtitle: option.locale?.identifier ?? "Subtitle track",
                        symbol: "captions.bubble",
                        selected: playback.selectedSubtitle == option
                    ) {
                        playback.selectSubtitle(option)
                    }
                }
            }

            if !playback.externalSubtitles.tracks.isEmpty {
                sectionLabel("From source")
                ForEach(playback.externalSubtitles.tracks) { track in
                    optionRow(
                        title: track.label,
                        subtitle: [track.language?.uppercased(), track.format?.rawValue.uppercased() ?? "SRT / WebVTT"]
                            .compactMap { $0 }.joined(separator: " · "),
                        symbol: "captions.bubble",
                        selected: playback.externalSubtitles.selectedTrackID == track.id
                    ) {
                        playback.selectExternalSubtitle(track)
                    }
                    .disabled(!playback.canSelectSourceSubtitle)
                }
            }

            Text(playback.pictureInPictureCaptionNotice)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            if playback.externalSubtitles.isLoading {
                ProgressView("Loading subtitles…")
                    .tint(KinetiqPalette.accent)
                    .foregroundStyle(.white)
            }
            if let message = playback.externalSubtitles.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                if playback.externalSubtitles.selectedTrackID != nil {
                    Button("Retry Subtitles") { playback.externalSubtitles.retry() }
                        .buttonStyle(.bordered)
                        .tint(KinetiqPalette.accent)
                }
            }

        case .queue:
            if session.episodes.isEmpty {
                unavailableContent(
                    symbol: "text.line.first.and.arrowtriangle.forward",
                    title: "No episode queue",
                    message: "The selected source has not provided episodes."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("SERIES QUEUE")
                    Text("\(session.upcomingEpisodes.count) episodes after the current episode")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                    episodeList
                }
            }

        case .more:
            VStack(alignment: .leading, spacing: 13) {
                sectionLabel("SLEEP TIMER")

                HStack(spacing: 9) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button {
                            playback.setSleepTimer(minutes)
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    playback.sleepTimerMinutes == minutes
                                        ? .black
                                        : .white
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    playback.sleepTimerMinutes == minutes
                                        ? KinetiqPalette.cyan
                                        : .white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let minutes = playback.sleepTimerMinutes {
                    HStack {
                        Label(
                            "Timer set: \(minutes) minutes",
                            systemImage: "moon.zzz.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(KinetiqPalette.cyan)

                        Spacer()

                        Button("Cancel") {
                            playback.setSleepTimer(nil)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("WEB PLAYBACK FALLBACK")
                if let stream = session.currentStream,
                   ModuleWebFallbackPolicy.allows(stream.url) {
                    Button(action: onOpenWebPlayer) {
                        Label("Try Web Player", systemImage: "globe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    Text("Opens this source-provided address in a private WebKit view. Native controls, PiP and external captions may be unavailable there.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    Text("No secure browser fallback is available for this server.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("STREAM INFORMATION")
                informationRow("Source", value: session.sourceName)
                informationRow(
                    "Selected server",
                    value: session.currentStream?.label ?? "None"
                )
                informationRow(
                    "Server choices",
                    value: String(session.availableStreams.count)
                )
                if let current = session.currentStream {
                    informationRow(
                        "Server health",
                        value: playback.serverHealthStatus(for: current)
                    )
                }
                Button {
                    playback.resetServerHealth()
                } label: {
                    Label("Reset learned server health", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
                informationRow(
                    "Playback state",
                    value: playback.playbackStatus
                )
                if let status = playback.lastHTTPStatus {
                    informationRow("Latest HTTP status", value: "\(status)")
                }
                informationRow(
                    "Server",
                    value: session.currentStream?.url.host ?? "Unavailable"
                )
                informationRow(
                    "Type",
                    value: session.currentStream?.streamType ?? "Unknown"
                )
                informationRow(
                    "Session cookies",
                    value: String(session.currentStream?.cookies.count ?? 0)
                )
                informationRow(
                    "Resolution",
                    value: playback.videoQuality.presentedResolution ?? playback.resolutionText
                )
                informationRow(
                    "Duration",
                    value: playback.formattedDuration
                )
                informationRow(
                    "Language",
                    value: session.selectedLanguage.uppercased()
                )
                informationRow(
                    "Playback speed",
                    value: String(format: "%.2fx", playback.playbackRate)
                )

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("PLAYBACK DIAGNOSTICS")

                if playback.diagnosticEvents.isEmpty {
                    Text("No stream events recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    ForEach(
                        Array(playback.diagnosticEvents.enumerated()),
                        id: \.offset
                    ) { _, event in
                        Text(event)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    UIPasteboard.general.string = playback.diagnosticSummary
                } label: {
                    Label(
                        "Copy diagnostics",
                        systemImage: "doc.on.doc"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(KinetiqPalette.cyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Episode List

    private var episodeList: some View {
        VStack(spacing: 9) {
            ForEach(session.episodes) { episode in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 11) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                episode.id == session.currentEpisode?.id
                                    ? KinetiqPalette.cyan
                                    : .white.opacity(0.6)
                            )
                            .frame(width: 26)

                        Text("Episode \(episode.number)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        if episode.id == session.currentEpisode?.id {
                            Text("PLAYING")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(KinetiqPalette.cyan)
                        }
                    }

                    HStack(spacing: 10) {
                        Spacer(minLength: 30)

                        if episode.subAvailable {
                            episodeButton(
                                "Sub",
                                episode: episode,
                                language: "sub"
                            )
                        }
                        if episode.dubAvailable {
                            episodeButton(
                                "Dub",
                                episode: episode,
                                language: "dub"
                            )
                        }
                    }
                }
                .padding(12)
                .background(
                    episode.id == session.currentEpisode?.id
                        ? KinetiqPalette.cyan.opacity(0.12)
                        : .white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }

    private func episodeButton(
        _ title: String,
        episode: ModuleAnimeEpisode,
        language: String
    ) -> some View {
        Button {
            playback.play(episode: episode, language: language)
            onClose()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .padding(.vertical, 9)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(playback.isResolvingEpisode)
    }

    // MARK: Reusable Options

    @ViewBuilder
    private var qualityOptions: some View {
        sectionLabel("VIDEO QUALITY")

        if let resolution = playback.videoQuality.presentedResolution {
            informationRow("Current presentation", value: resolution)
        }

        switch playback.videoQuality.state {
        case .idle, .loading:
            ProgressView("Checking quality options…")
                .tint(KinetiqPalette.accent)
                .foregroundStyle(.white)

        case .available:
            optionRow(
                title: "Auto",
                subtitle: "Adapt to your connection and device",
                symbol: "sparkles",
                selected: playback.videoQuality.selectedID == nil
            ) {
                playback.videoQuality.select(nil)
            }
            ForEach(playback.videoQuality.options) { option in
                optionRow(
                    title: option.title,
                    subtitle: option.detail,
                    symbol: "tv",
                    selected: playback.videoQuality.selectedID == option.id
                ) {
                    playback.videoQuality.select(option.id)
                }
            }
            Text("These are preferred limits. Your device may play a lower quality, and buffered video can delay changes. Each new episode or server starts in Auto.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

        case .unavailable:
            Text("This stream does not expose multiple video resolutions. Playback stays in Auto; other source streams can be selected in Servers.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

        case .failed:
            Text("Quality options could not be read. Playback can continue in Auto.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Button("Retry Quality Detection") { playback.videoQuality.retry() }
                .buttonStyle(.bordered)
                .tint(KinetiqPalette.accent)
        }
    }

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
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(2)
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

// MARK: - Module Playback Controller

@MainActor
private final class ModulePlayerPlaybackController: ObservableObject {

    let externalSubtitles = ModuleExternalSubtitleController()
    private var subtitleChanges: AnyCancellable?
    @Published private(set) var captionChoice: KinetiqCaptionChoice = .settings

    // PiP presents an independent AVFoundation video surface. SwiftUI-based
    // SRT/WebVTT overlays do NOT appear there. Native legible options can.
    // When a source track has a matching embedded option, switch before PiP.
    // Native legible captions are painted by iOS in system PiP. The styling
    // below is an AVTextStyleRule preference, *not* a guaranteed override of
    // accessibility caption settings or non-WebVTT subtitle formats.
    private weak var pipStyleItem: AVPlayerItem?
    private var pipStyleApplied = false

    private var pipCaptionRestore: (
        item: AVPlayerItem,
        track: ModuleRemoteSubtitleTrack,
        choice: KinetiqCaptionChoice,
        automaticSelection: Bool
    )?

    private func matchingEmbeddedCaption(for track: ModuleRemoteSubtitleTrack) -> AVMediaSelectionOption? {
        guard subtitleOptionsItem === player.currentItem,
              let language = KinetiqCaptionLanguage(tag: track.language, name: track.label).tag else {
            return nil
        }
        let ranked: [(Int, Int)] = subtitleOptions.enumerated().compactMap { index, option in
            guard let rank = KinetiqCaptionLanguage.rank(
                KinetiqCaptionLanguage(option).tag, for: language
            ) else { return nil }
            return (rank, index)
        }
        guard let selected = ranked.min(by: {
            $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
        }), subtitleOptions.indices.contains(selected.1) else { return nil }
        return subtitleOptions[selected.1]
    }

    var pictureInPictureCaptionNotice: String {
        if let selectedID = externalSubtitles.selectedTrackID,
           let track = externalSubtitles.tracks.first(where: { $0.id == selectedID }) {
            return matchingEmbeddedCaption(for: track) == nil
                ? "PiP subtitles unavailable for this selection: the source provides only an SRT/WebVTT overlay. Playback itself still works."
                : "PiP caption handoff available: a matching embedded track will be selected before PiP and your source subtitles restored afterward."
        }
        if selectedSubtitle != nil {
            return "Embedded subtitles are selected. AVFoundation can carry native legible tracks into PiP when the stream and iOS renderer support them."
        }
        if subtitleOptions.isEmpty {
            return "This stream has no native legible track. Overlay-only source subtitles cannot appear in system PiP."
        }
        return "To get subtitles in PiP, select an embedded track when available. External-only overlays cannot be carried into the system window."
    }

    func prepareNativeCaptionsForPiP() {
        guard !hasStopped else { return }
        if !pipStyleApplied, let item = player.currentItem {
            pipStyleApplied = true
            pipStyleItem = item
            item.textStyleRules = KinetiqModuleNativeCaptionStyle.rules(
                for: KinetiqSubtitleSettings.shared.appearance, inPiP: true
            )
        }
        guard pipCaptionRestore == nil,
              captionChoice != .off,
              let item = player.currentItem,
              item === subtitleOptionsItem,
              let subtitleGroup,
              let selectedID = externalSubtitles.selectedTrackID,
              let track = externalSubtitles.tracks.first(where: { $0.id == selectedID }),
              let selected = matchingEmbeddedCaption(for: track) else { return }

        // Explicit selection prevents automatic criteria from overriding the
        // native option while PiP is being created.
        pipCaptionRestore = (
            item, track, captionChoice, player.appliesMediaSelectionCriteriaAutomatically
        )
        player.appliesMediaSelectionCriteriaAutomatically = false
        externalSubtitles.turnOff()
        item.select(selected, in: subtitleGroup)
        selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
    }

    func restoreCaptionsAfterPiP() {
        if pipStyleApplied {
            if let item = player.currentItem, item === pipStyleItem {
                item.textStyleRules = KinetiqModuleNativeCaptionStyle.rules(
                    for: KinetiqSubtitleSettings.shared.appearance, inPiP: false
                )
            }
            pipStyleApplied = false
            pipStyleItem = nil
        }
        guard let restore = pipCaptionRestore else { return }
        pipCaptionRestore = nil
        guard !hasStopped,
              let item = player.currentItem,
              item === restore.item,
              externalSubtitles.tracks.contains(where: { $0.id == restore.track.id }) else {
            return
        }
        // Keep the user's explicit setting and track; an AVKit handoff must
        // never silently change their stored caption preference.
        player.appliesMediaSelectionCriteriaAutomatically = restore.automaticSelection
        captionChoice = restore.choice
        selectedSubtitle = KinetiqCaptionTarget.manualSource.apply(
            to: item, group: subtitleGroup
        )
        let playbackTime = player.currentTime().seconds
        externalSubtitles.updatePlaybackTime(playbackTime.isFinite ? playbackTime : .nan)
        externalSubtitles.select(
            restore.track, rememberForSession: restore.choice == .source
        )
    }
    private weak var subtitleOptionsItem: AVPlayerItem?
    var requiresEmbeddedSubtitle: Bool { subtitleGroup?.allowsEmptySelection == false }
    var canSelectSourceSubtitle: Bool {
        player.currentItem != nil && !requiresEmbeddedSubtitle
    }
    let videoQuality = ModuleVideoQualityController()
    private var qualityChanges: AnyCancellable?

    @Published private(set) var player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var hasFinishedPresentingFirstFrame = false
    private var sawFirstVideoFrame = false
    private var startupOverlayTask: Task<Void, Never>?
    @Published private(set) var isResolvingEpisode = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0

    @Published var scrubPosition: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var isAspectFill = false

    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published private(set) var selectedAudio: AVMediaSelectionOption?
    @Published private(set) var selectedSubtitle: AVMediaSelectionOption?
    @Published private(set) var sleepTimerMinutes: Int?
    @Published private(set) var resolutionText = "Analyzing…"
    @Published private(set) var playbackStatus = "Preparing stream"
    @Published private(set) var lastHTTPStatus: Int?
    @Published private(set) var diagnosticEvents: [String] = []

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var sleepTask: Task<Void, Never>?

    private let session: ModuleEpisodePlaybackSession

    private var streamCancellable: AnyCancellable?
    private var errorCancellable: AnyCancellable?
    private var resolvingCancellable: AnyCancellable?
    private var timeObserver: Any?
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedEndObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var recoveryTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var manifestProbeTasks: [Task<Void, Never>] = []
    private var manifestProbedHosts = Set<String>()

    // A ready AVPlayerItem is not evidence that frames are actually playing.
    // Some providers remain in "waiting" forever without sending a stall
    // notification. Watch startup and post-start buffering independently.
    private var startedCurrentItem = false
    private var playbackProofItem: ObjectIdentifier?
    private var playbackProofAnchor: Double?
    private var verifiedPlayingStreamID: UUID?
    private var streamStartedLoadingAt = Date()
    private var wantsToPlay = true
    private var refreshedEpisodeKey: String?
    private var loadedEpisodeKey: String?

    private var attemptedStreamIDs = Set<UUID>()
    private var automaticRetriedIDs = Set<UUID>()
    private var knownStreamChoices = Set<UUID>()
    private var isHandlingStreamFailure = false
    private var lastStreamID: UUID?
    private var lastLoadedEpisode: ModuleAnimeEpisode?
    private var lastLoadedLanguage = "sub"
    private var pendingResumePosition: Double = 0
    private var isRestoringPosition = false
    private var lastSavedProgressAt = Date.distantPast
    private var isScrubbing = false
    private var hasStopped = false

    init(session: ModuleEpisodePlaybackSession) {
        self.session = session

        subtitleChanges = externalSubtitles.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        qualityChanges = videoQuality.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

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
                    self.playbackStatus = "Source resolution failed"
                    self.note("Module handler reported an error")
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

    /// This summary deliberately excludes URL paths, query parameters,
    /// authentication headers, cookies, and any module JavaScript.
    var diagnosticSummary: String {
        let lines: [String] = [
            "Kinetiq module playback diagnostics · Batch 05H",
            "Source: \(ModulePlaybackDiagnostics.redact(session.sourceName, limit: 80))",
            "Episode: \(ModulePlaybackDiagnostics.redact(session.currentEpisode?.number ?? "Unknown", limit: 30))",
            "Language: \(session.selectedLanguage)",
            "Server label: \(ModulePlaybackDiagnostics.redact(session.currentStream?.label ?? "None", limit: 80))",
            "Server health: \(session.currentStream.map { serverHealthStatus(for: $0) } ?? "Not tested")",
            "Source-provided servers: \(session.availableStreams.count)",
            "Distinct server hosts: \(Set(session.availableStreams.map { $0.hostName.lowercased() }).count)",
            "Tried servers: \(attemptedStreamIDs.count)",
            "Refreshed links: \(refreshedEpisodeKey == loadedEpisodeKey && loadedEpisodeKey != nil ? "Yes" : "No")",
            "Host: \(session.currentStream?.hostName ?? "None")",
            "Stream type: \(session.currentStream?.streamType ?? "Unknown")",
            "Playback state: \(playbackStatus)",
            "HTTP status: \(lastHTTPStatus.map(String.init) ?? "Unknown")",
            "Player resolution: \(resolutionText)",
            "Quality preference: \(videoQuality.selectionDescription)",
            "Current presentation: \(videoQuality.presentedResolution ?? "Not reported")",
            "PiP native caption tracks: \(subtitleOptions.count)",
            "PiP caption selection: \(externalSubtitles.isRequested ? "source overlay" : (selectedSubtitle == nil ? "none" : "native track"))",
            "PiP native handoff: \(pipCaptionRestore == nil ? "inactive" : "active")",
            "Events:"
        ]
        return (lines.map { ModulePlaybackDiagnostics.redact($0) } +
                diagnosticEvents + ["", session.diagnosticSummary])
            .joined(separator: "\n")
    }

    func serverHealthStatus(for stream: ModuleResolvedStream) -> String {
        ModuleServerHealthStore.shared.status(
            for: stream,
            sourceID: session.sourceID,
            sourceName: session.sourceName
        )
    }

    func resetServerHealth() {
        ModuleServerHealthStore.shared.resetAll()
        note("Server health history cleared by user")
    }

    private func note(_ event: String) {
        diagnosticEvents.append(ModulePlaybackDiagnostics.redact(event))
        if diagnosticEvents.count > 38 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 38)
        }
        // Keep the outside-player copy button current when an asynchronous
        // HLS probe finishes after the failure alert first appeared.
        if let failure = errorMessage, !failure.isEmpty {
            session.recordPlayerFailure(diagnostics: diagnosticSummary, reason: failure)
        }
    }

    // MARK: AVPlayer Observation

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Read the active item rather than a time captured before
                // an episode/server handoff reached this MainActor task.
                let seconds = self.player.currentTime().seconds
                guard seconds.isFinite, seconds >= 0 else { return }

                self.currentTime = seconds
                self.externalSubtitles.updatePlaybackTime(self.isRestoringPosition ? .nan : seconds)

                if !self.isScrubbing {
                    self.scrubPosition = seconds
                }

                if let item = self.player.currentItem {
                    let length = item.duration.seconds
                    if length.isFinite, length > 0 {
                        self.duration = length
                    }
                }

                if self.player.timeControlStatus == .playing {
                    self.savePlaybackProgress(force: false)
                    if !self.isRestoringPosition,
                       let item = self.player.currentItem,
                       let stream = self.session.currentStream,
                       !stream.isWebEmbed,
                       item.presentationSize.width > 0,
                       item.presentationSize.height > 0,
                       self.lastStreamID == stream.id,
                       self.verifiedPlayingStreamID != stream.id {
                        let itemID = ObjectIdentifier(item)
                        if self.playbackProofItem != itemID {
                            self.playbackProofItem = itemID
                            self.playbackProofAnchor = seconds
                        } else if let start = self.playbackProofAnchor,
                                  seconds >= start + 1.25 {
                            // AVPlayer 'ready' or 'playing' alone is not
                            // evidence of actual video progress. Only count
                            // advancing playback as a verified success.
                            self.verifiedPlayingStreamID = stream.id
                            let elapsed = Date().timeIntervalSince(self.streamStartedLoadingAt)
                            ModuleServerHealthStore.shared.recordSuccess(
                                stream,
                                sourceID: self.session.sourceID,
                                sourceName: self.session.sourceName,
                                startupSeconds: elapsed
                            )
                            self.note("Verified playback progress on \(stream.hostName)")
                            self.registerFirstVideoFrame(item: item)
                        }
                    }
                }
            }
        }
    }

    // Video item readiness is NOT the same as video being visible.
    // Finish the full-screen loading scene only after AVPlayerLayer displays video.
    func registerFirstVideoFrame(item: AVPlayerItem?) {
        guard !hasStopped, let item, player.currentItem === item,
              !sawFirstVideoFrame else { return }
        sawFirstVideoFrame = true
        playbackStatus = "Video ready"
        note("First video frame ready for display")
        startupTask?.cancel()
        startupTask = nil
        startupOverlayTask?.cancel()
        startupOverlayTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(950)) }
            catch { return }
            guard let self, !self.hasStopped, self.player.currentItem === item,
                  self.sawFirstVideoFrame else { return }
            self.hasFinishedPresentingFirstFrame = true
        }
    }

    private func installPlayerStatusObserver() {
        playerStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hasStopped else { return }

                let status = observedPlayer.timeControlStatus
                self.isPlaying = status == .playing
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate

                switch status {
                case .playing:
                    self.startedCurrentItem = true
                    self.playbackStatus = "Playing"
                    // Startup watchdog stays active until the first video frame.
                    self.stallTask?.cancel()
                    self.stallTask = nil
                case .waitingToPlayAtSpecifiedRate:
                    if self.wantsToPlay,
                       self.startedCurrentItem,
                       let item = self.player.currentItem {
                        self.playbackStatus = "Buffering stream"
                        self.scheduleStallRecovery(for: item)
                    }
                case .paused:
                    self.stallTask?.cancel()
                    self.stallTask = nil
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: Stream Handoff

    private func load(_ stream: ModuleResolvedStream) {
        guard !hasStopped, lastStreamID != stream.id else {
            return
        }

        // Save the OLD episode before a new one replaces the player item.
        // Failover between servers for the same episode retains the current
        // in-memory position, whereas a different episode uses saved progress.
        let previousEpisodeID = lastLoadedEpisode?.id
        let previousLanguage = lastLoadedLanguage
        let sampledPosition = player.currentTime().seconds
        let previousPosition = sampledPosition.isFinite ? sampledPosition : currentTime
        if lastStreamID != nil {
            savePlaybackProgress(force: true)
        }

        lastLoadedEpisode = session.currentEpisode
        lastLoadedLanguage = session.selectedLanguage

        let storedPosition: Double
        if let sourceID = session.sourceID,
           let anime = session.animeItem,
           let episode = session.currentEpisode {
            storedPosition = ModuleAnimeCollectionStore.shared.resumePosition(
                sourceID: sourceID,
                animeID: anime.id,
                episodeID: episode.id,
                language: session.selectedLanguage
            )
        } else {
            storedPosition = 0
        }

        if previousEpisodeID == session.currentEpisode?.id &&
           previousLanguage == session.selectedLanguage {
            // Preserve the pending seek during early server failures.
            pendingResumePosition = max(
                previousPosition,
                pendingResumePosition,
                storedPosition
            )
        } else {
            pendingResumePosition = storedPosition
        }

        lastSavedProgressAt = .distantPast
        isRestoringPosition = true

        let episodeKey = (session.currentEpisode?.id ?? "") + "|" + session.selectedLanguage
        if loadedEpisodeKey != episodeKey {
            loadedEpisodeKey = episodeKey
            refreshedEpisodeKey = nil
            manifestProbedHosts.removeAll()
            manifestProbeTasks.forEach { $0.cancel() }
            manifestProbeTasks.removeAll()
        }

        let choices = Set(session.availableStreams.map(\.id))
        if choices != knownStreamChoices {
            knownStreamChoices = choices
            attemptedStreamIDs.removeAll()
            automaticRetriedIDs.removeAll()
        }

        recoveryTask?.cancel()
        recoveryTask = nil
        stallTask?.cancel()
        stallTask = nil
        startupTask?.cancel()
        startupTask = nil
        startedCurrentItem = false
        startupOverlayTask?.cancel()
        startupOverlayTask = nil
        sawFirstVideoFrame = false
        hasFinishedPresentingFirstFrame = false
        playbackProofItem = nil
        playbackProofAnchor = nil
        verifiedPlayingStreamID = nil
        streamStartedLoadingAt = Date()
        wantsToPlay = true

        attemptedStreamIDs.insert(stream.id)
        isHandlingStreamFailure = false
        lastStreamID = stream.id
        lastHTTPStatus = nil
        playbackStatus = "Opening \(stream.label)"
        note("Opening \(stream.label) on \(stream.hostName)")
        note("Server health: \(serverHealthStatus(for: stream))")
        let headerNames = Set(stream.headers.keys.map { $0.lowercased() })
        note("Request context: custom headers=\(stream.headers.count), cookies=\(stream.cookies.count), referer=\(headerNames.contains("referer")), user-agent=\(headerNames.contains("user-agent")), origin=\(headerNames.contains("origin"))")
        errorMessage = nil
        isBuffering = true
        isPlaying = false
        duration = 0
        currentTime = 0
        scrubPosition = 0
        isScrubbing = false
        resolutionText = "Analyzing…"
        audioOptions = []
        subtitleOptions = []
        selectedAudio = nil
        selectedSubtitle = nil
        audioGroup = nil
        subtitleGroup = nil
        subtitleOptionsItem = nil
        pipCaptionRestore = nil
        pipStyleItem = nil
        pipStyleApplied = false
        externalSubtitles.configure(tracks: stream.subtitles)

        removeCurrentItemObservers()

        if stream.isWebEmbed {
            player.pause()
            player.replaceCurrentItem(with: nil)
            isBuffering = false
            isPlaying = false
            playbackStatus = "Web player available"
            note("Source supplied a browser embed rather than a native video")
            // The view opens the isolated WebKit player for this source.
            return
        }

        var assetOptions: [String: Any] = [:]

        // This key is undocumented and is retained only as best-effort
        // compatibility for Referer and other provider-specific headers.
        // iOS does not guarantee propagation to every HLS child request.
        if !stream.headers.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
        }

        // Official AVFoundation options. Do not put credentials into logs.
        if let userAgent = stream.headers.first(where: {
            $0.key.lowercased() == "user-agent"
        })?.value {
            assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent
        }

        let hasExplicitCookieHeader = stream.headers.keys.contains {
            $0.lowercased() == "cookie"
        }

        if !hasExplicitCookieHeader && !stream.cookies.isEmpty {
            let playerCookies = stream.cookies.compactMap { cookie in
                HTTPCookie(properties: [
                    .name: cookie.name,
                    .value: cookie.value,
                    .domain: cookie.domain,
                    .path: cookie.path,
                    .secure: cookie.isSecure ? "TRUE" : "FALSE"
                ])
            }

            if !playerCookies.isEmpty {
                assetOptions[AVURLAssetHTTPCookiesKey] = playerCookies
            }
        }

        let asset = AVURLAsset(
            url: stream.url,
            options: assetOptions.isEmpty ? nil : assetOptions
        )

        let item = AVPlayerItem(asset: asset)
        item.textStyleRules = KinetiqModuleNativeCaptionStyle.rules(
            for: KinetiqSubtitleSettings.shared.appearance, inPiP: false
        )
        item.preferredForwardBufferDuration = 8

        player.replaceCurrentItem(with: item)
        videoQuality.configure(for: item)
        scheduleStartupWatchdog(for: item)

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
                    self.playbackStatus = "Ready to play"
                    self.note("Stream ready: \(stream.label)")
                    let seconds = observedItem.duration.seconds
                    if seconds.isFinite, seconds > 0 {
                        self.duration = seconds
                    }
                    // Seek before playback begins, avoiding a brief jump
                    // from zero on resumed episodes and server failover.
                    let savedPosition = self.pendingResumePosition
                    self.pendingResumePosition = 0
                    let safePosition: Double
                    if seconds.isFinite, seconds > 5 {
                        safePosition = min(savedPosition, max(0, seconds - 5))
                    } else {
                        safePosition = 0
                    }

                    if safePosition >= 3 {
                        self.player.seek(
                            to: CMTime(seconds: safePosition, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        ) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self,
                                      self.player.currentItem === observedItem else { return }
                                self.isRestoringPosition = false
                                self.externalSubtitles.updatePlaybackTime(self.player.currentTime().seconds)
                                if self.wantsToPlay {
                                    self.player.playImmediately(atRate: self.playbackRate)
                                }
                            }
                        }
                    } else {
                        self.isRestoringPosition = false
                        self.externalSubtitles.updatePlaybackTime(self.player.currentTime().seconds)
                        if self.wantsToPlay {
                            self.player.playImmediately(atRate: self.playbackRate)
                        }
                    }

                    Task { [weak self] in
                        guard let self else { return }
                        await self.loadMediaOptions(for: observedItem)
                        await self.loadResolution(for: observedItem)
                    }

                case .failed:
                    self.isBuffering = false
                    self.handleStreamFailure(
                        for: observedItem,
                        message: "The source stream could not be opened."
                    )

                case .unknown:
                    self.isBuffering = true

                @unknown default:
                    self.isBuffering = false
                    self.handleStreamFailure(
                        for: observedItem,
                        message: "The player returned an unknown stream status."
                    )
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

                self.savePlaybackProgress(force: true, finished: true)
                await self.session.playNext()

                if let message = self.session.playbackError,
                   !message.isEmpty {
                    self.errorMessage = message
                }
            }
        }

        failedEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleStreamFailure(
                    for: item,
                    message: "Playback stopped unexpectedly."
                )
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleStallRecovery(for: item)
            }
        }
    }

    private func removeCurrentItemObservers() {
        videoQuality.stop()
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
            self.failedEndObserver = nil
        }

        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
    }

    // MARK: Bounded Recovery and Diagnostics

    private func scheduleStartupWatchdog(for item: AVPlayerItem) {
        startupTask?.cancel()
        let timeout = session.currentStream.map {
            ModuleServerHealthStore.shared.startupTimeout(
                for: $0, sourceID: session.sourceID, sourceName: session.sourceName
            )
        } ?? 24
        startupTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled,
                      let self,
                      !self.hasStopped,
                      self.wantsToPlay,
                      !self.sawFirstVideoFrame,
                      !self.isHandlingStreamFailure,
                      self.player.currentItem === item else { return }

                self.note("Startup timed out before video began playing")
                self.handleStreamFailure(
                    for: item,
                    message: "The server did not start playback within \(Int(timeout)) seconds."
                )
            } catch {
                // Playing, paused, switched servers, or closed the player.
            }
        }
    }

    private func scheduleStallRecovery(for item: AVPlayerItem) {
        guard !hasStopped, player.currentItem === item else { return }

        note("Player reported a stall")
        stallTask?.cancel()
        stallTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled,
                      let self,
                      !self.hasStopped,
                      self.player.currentItem === item,
                      self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
                    return
                }

                self.handleStreamFailure(
                    for: item,
                    message: "The stream stalled while buffering."
                )
            } catch {
                // Recovered naturally, switched servers, or closed player.
            }
        }
    }

    private func handleStreamFailure(
        for item: AVPlayerItem,
        message: String
    ) {
        guard !hasStopped,
              !isHandlingStreamFailure,
              player.currentItem === item,
              let stream = session.currentStream else { return }

        isHandlingStreamFailure = true
        startupTask?.cancel()
        startupTask = nil
        stallTask?.cancel()
        stallTask = nil

        // Read only a numeric status: never expose token-bearing URLs or
        // raw response headers from AVFoundation logs.
        let errorEvents = item.errorLog()?.events ?? []
        if let status = errorEvents.last?.errorStatusCode,
           (100...599).contains(status) {
            lastHTTPStatus = status
        }

        // AVFoundation can fail before it has an HTTP error-log event. Capture
        // safe numeric NSError codes/domains instead of a generic 'unknown'.
        if let itemError = item.error as NSError? {
            note("AVPlayerItem error: \(ModuleHLSPreflight.safeDomain(itemError.domain)) / \(itemError.code)")
            if let underlying = itemError.userInfo[NSUnderlyingErrorKey] as? NSError {
                note("Underlying error: \(ModuleHLSPreflight.safeDomain(underlying.domain)) / \(underlying.code)")
            }
        }
        if let playerError = player.error as NSError? {
            note("AVPlayer error: \(ModuleHLSPreflight.safeDomain(playerError.domain)) / \(playerError.code)")
        }
        for event in errorEvents.suffix(3) {
            note("AVFoundation event: \(ModuleHLSPreflight.safeDomain(event.errorDomain)) / \(event.errorStatusCode)")
        }
        if errorEvents.isEmpty {
            note("AVFoundation provided no HTTP error-log event")
        }
        scheduleManifestProbeIfNeeded(for: stream)

        let reason = lastHTTPStatus.map { "HTTP \($0)" }
            ?? "AVPlayer failure"
        let failureCode: String
        switch lastHTTPStatus {
        case 401, 403: failureCode = "HTTP_AUTHORIZATION_REJECTED"
        case 404, 410: failureCode = "HTTP_MEDIA_NOT_FOUND"
        case 429: failureCode = "HTTP_RATE_LIMITED"
        case let .some(code) where (500...599).contains(code):
            failureCode = "HTTP_PROVIDER_FAILURE"
        case .some: failureCode = "HTTP_MEDIA_RESPONSE_FAILURE"
        case .none: failureCode = "AVPLAYER_STARTUP_OR_DECODE_FAILURE"
        }
        note("Stage=AVPlayer; code=\(failureCode); status=\(lastHTTPStatus.map(String.init) ?? "unknown")")
        note("\(reason) on \(stream.hostName)")

        // Exactly one automatic retry per server. If the server rejects
        // authorization, move directly to a different available server.
        let authorizationRejected = lastHTTPStatus == 401 || lastHTTPStatus == 403
        if !authorizationRejected,
           automaticRetriedIDs.insert(stream.id).inserted {
            playbackStatus = "Retrying \(stream.label)"
            note("Automatic retry: \(stream.label)")
            recoveryTask?.cancel()
            recoveryTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(650))
                    guard !Task.isCancelled,
                          let self,
                          self.player.currentItem === item,
                          !self.hasStopped else { return }

                    self.lastStreamID = nil
                    self.load(stream)
                } catch {
                    // A manual selection or player dismissal cancelled retry.
                }
            }
            return
        }

        // A transient first failure gets a single retry; only an exhausted
        // attempt is persisted as unhealthy. Never record manual pause/close.
        ModuleServerHealthStore.shared.recordFailure(
            stream, sourceID: session.sourceID, sourceName: session.sourceName
        )
        note("Server health: failed after retry; seeking another candidate")

        if let alternate = ModuleServerHealthStore.shared.nextUntried(
            from: session.availableStreams,
            excluding: attemptedStreamIDs,
            avoidingHost: stream.hostName,
            sourceID: session.sourceID,
            sourceName: session.sourceName
        ) {
            playbackStatus = "Switching to \(alternate.label)"
            note("Automatic fallback: \(alternate.label)")
            if session.selectStream(alternate) {
                return
            }
            note("Unable to select next server")
        }

        // Signed URLs and provider APIs can rotate between extractions.
        // Refresh *once* per episode/language after exhausting the module's
        // known alternatives. Never loop indefinitely on identical links.
        if let episodeKey = loadedEpisodeKey,
           refreshedEpisodeKey != episodeKey {
            refreshedEpisodeKey = episodeKey
            playbackStatus = "Refreshing server links"
            note("All known servers failed; re-resolving episode once")
            recoveryTask?.cancel()
            recoveryTask = Task { @MainActor [weak self] in
                guard let self, !self.hasStopped else { return }
                let success = await self.session.retryCurrent()
                guard !Task.isCancelled, !self.hasStopped else { return }
                if success {
                    self.note("Episode links refreshed; opening new stream")
                    // session.currentStream publishes the new player handoff.
                } else {
                    self.playbackStatus = "Playback failed"
                    self.errorMessage = self.session.playbackError
                        ?? "The source could not refresh its stream links."
                    self.note("Source could not refresh stream links")
                }
            }
            return
        }

        playbackStatus = "Playback failed"
        let count = max(session.availableStreams.count, 1)
        let suffix = authorizationRejected
            ? "Last server returned HTTP \(lastHTTPStatus ?? 403)."
            : message
        errorMessage = "Tried all \(count) available server(s). \(suffix) Check Diagnostics or choose another source."
    }

    /// Bounded background probe after AVPlayer fails (never during healthy
    /// playback). Runs once per host/episode, without printing stream URLs.
    private func scheduleManifestProbeIfNeeded(for stream: ModuleResolvedStream) {
        guard stream.streamType.lowercased() == "hls" ||
                stream.url.pathExtension.lowercased() == "m3u8" else { return }
        let host = stream.hostName.lowercased()
        guard manifestProbedHosts.insert(host).inserted else { return }
        let episodeKey = loadedEpisodeKey
        note("HLS manifest probe scheduled on failed host")
        let job = Task { @MainActor [weak self] in
            let observations = await ModuleHLSPreflight.inspect(stream)
            guard !Task.isCancelled,
                  let self, !self.hasStopped,
                  self.loadedEpisodeKey == episodeKey else { return }
            for observation in observations { self.note(observation) }
        }
        manifestProbeTasks.append(job)
    }

    // MARK: Stream Tracks and Metadata

    private func loadMediaOptions(for item: AVPlayerItem) async {
        // Missing audio metadata must not prevent subtitle detection (or
        // leave native subtitles enabled under an external subtitle overlay).
        let audio: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(
            for: .audible
        )
        let subtitles: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(
            for: .legible
        )

        guard player.currentItem === item else { return }
        audioGroup = audio
        subtitleGroup = subtitles
        audioOptions = audio?.options ?? []
        subtitleOptions = subtitles?.options ?? []

        if let audio {
            selectedAudio = item.currentMediaSelection.selectedMediaOption(in: audio)
        }
        subtitleOptionsItem = item
        refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
    }

    private func loadResolution(for item: AVPlayerItem) async {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                guard player.currentItem === item else { return }
                resolutionText = "No video track"
                return
            }

            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let adjusted = CGRect(origin: .zero, size: naturalSize)
                .applying(transform)

            guard player.currentItem === item else { return }
            let width = Int(abs(adjusted.width))
            let height = Int(abs(adjusted.height))
            resolutionText = width > 0 && height > 0
                ? "\(width) × \(height)"
                : "Unavailable"
        } catch {
            guard player.currentItem === item else { return }
            resolutionText = "Unavailable"
        }
    }

    func selectAudio(_ option: AVMediaSelectionOption?) {
        guard let audioGroup else { return }
        player.currentItem?.select(option, in: audioGroup)
        selectedAudio = option
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        pipCaptionRestore = nil
        if let option {
            guard subtitleOptions.contains(option), subtitleOptionsItem === player.currentItem else { return }
            captionChoice = .embedded(KinetiqCaptionLanguage(option))
            player.appliesMediaSelectionCriteriaAutomatically = false
            // Apply the actual option now, even when two tracks have identical metadata.
            externalSubtitles.turnOff()
            if let item = player.currentItem, let subtitleGroup {
                item.select(option, in: subtitleGroup)
                selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
            }
        } else {
            guard !requiresEmbeddedSubtitle else { return }
            externalSubtitles.turnOff()
            captionChoice = .off
            player.appliesMediaSelectionCriteriaAutomatically = false
            refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
        }
    }

    func selectExternalSubtitle(_ track: ModuleRemoteSubtitleTrack) {
        guard canSelectSourceSubtitle, let item = player.currentItem,
              externalSubtitles.tracks.contains(where: { $0.id == track.id }) else { return }
        pipCaptionRestore = nil
        captionChoice = .source
        player.appliesMediaSelectionCriteriaAutomatically = false
        selectedSubtitle = KinetiqCaptionTarget.manualSource.apply(to: item, group: subtitleGroup)
        externalSubtitles.updatePlaybackTime(isRestoringPosition ? .nan : player.currentTime().seconds)
        externalSubtitles.select(track)
    }

    func useSubtitleDefault() {
        pipCaptionRestore = nil
        externalSubtitles.turnOff()
        captionChoice = .settings
        refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
    }

    func refreshCaptions(preference: String) {
        guard !hasStopped, let item = subtitleOptionsItem, item === player.currentItem else { return }
        let tracks = externalSubtitles.tracks
        let target = captionChoice.target(
            preference: preference,
            embedded: subtitleOptions.map(KinetiqCaptionLanguage.init),
            sources: requiresEmbeddedSubtitle ? [] : tracks.map { KinetiqCaptionLanguage(tag: $0.language, name: $0.label) }
        )
        // Respect the saved subtitle preference, including Off, rather than
        // allowing automatic language criteria to override an explicit target.
        player.appliesMediaSelectionCriteriaAutomatically = (target == .automatic)
        selectedSubtitle = target.apply(to: item, group: subtitleGroup)
        switch target {
        case .source(let index):
            let track = tracks[index]
            if externalSubtitles.selectedTrackID != track.id {
                externalSubtitles.updatePlaybackTime(isRestoringPosition ? .nan : player.currentTime().seconds)
                externalSubtitles.select(track, rememberForSession: false)
            }
        case .manualSource:
            if requiresEmbeddedSubtitle { externalSubtitles.suspendForRequiredEmbeddedTrack() }
            else { externalSubtitles.restoreManualSelection() }
        default:
            if externalSubtitles.isRequested { externalSubtitles.turnOff() }
        }
    }

    func syncCaptionSelection(for item: AVPlayerItem?) {
        guard !hasStopped, let item, item === subtitleOptionsItem, item === player.currentItem, let subtitleGroup else { return }
        let actual = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
        if actual != selectedSubtitle { selectedSubtitle = actual }
    }

    // MARK: Playback Controls

    func togglePlayback() {
        let waitingOrPlaying = player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if wantsToPlay && waitingOrPlaying {
            wantsToPlay = false
            startupTask?.cancel()
            startupTask = nil
            stallTask?.cancel()
            stallTask = nil
            persistCurrentProgress()
            player.pause()
        } else {
            wantsToPlay = true
            if let item = player.currentItem, !startedCurrentItem {
                scheduleStartupWatchdog(for: item)
            }
            player.playImmediately(atRate: playbackRate)
        }
    }

    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0,
              let item = player.currentItem else { return }

        let target = min(max(seconds, 0), duration)
        let time = CMTime(seconds: target, preferredTimescale: 600)

        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard finished, let self,
                      self.player.currentItem === item else { return }
                self.externalSubtitles.updatePlaybackTime(self.player.currentTime().seconds)
                self.persistCurrentProgress()
            }
        }
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

    func selectServer(_ stream: ModuleResolvedStream) {
        guard !hasStopped,
              session.currentStream?.id != stream.id else { return }

        recoveryTask?.cancel()
        stallTask?.cancel()
        errorMessage = nil
        playbackStatus = "Switching to \(stream.label)"
        note("Manual server selection: \(stream.label)")
        _ = session.selectStream(stream)
    }

    func dismissError() {
        errorMessage = nil
    }

    func retryCurrentStream() {
        guard let stream = session.currentStream else {
            errorMessage = "No stream is available to retry."
            return
        }
        // Explicit retries reset the automatic limits, but automatic
        // recovery can never loop without user interaction.
        recoveryTask?.cancel()
        stallTask?.cancel()
        automaticRetriedIDs.removeAll()
        attemptedStreamIDs.removeAll()
        refreshedEpisodeKey = nil
        playbackStatus = "Retrying manually"
        note("Manual retry: \(stream.label)")
        lastStreamID = nil
        load(stream)
    }

    func setSleepTimer(_ minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerMinutes = nil

        guard let minutes, minutes > 0 else { return }
        sleepTimerMinutes = minutes

        sleepTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled, let self else { return }
                self.player.pause()
                self.sleepTimerMinutes = nil
            } catch {
                // The timer was cancelled or changed.
            }
        }
    }

    // MARK: Lifecycle

    // MARK: Independent Remote Playback History

    func persistCurrentProgress() {
        savePlaybackProgress(force: true)
    }

    private func savePlaybackProgress(
        force: Bool,
        finished: Bool = false
    ) {
        guard !isRestoringPosition,
              let activeItem = player.currentItem,
              activeItem.status == .readyToPlay,
              let sourceID = session.sourceID,
              let anime = session.animeItem,
              let episode = lastLoadedEpisode else {
            return
        }

        let length = activeItem.duration.seconds
        let position = finished ? length : player.currentTime().seconds
        guard length.isFinite, length > 5,
              position.isFinite, position >= 3 else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastSavedProgressAt) < 7 {
            return
        }

        ModuleAnimeCollectionStore.shared.recordPlayback(
            sourceID: sourceID,
            sourceName: session.sourceName,
            anime: anime,
            episode: episode,
            language: lastLoadedLanguage,
            position: position,
            duration: length,
            finished: finished
        )
        lastSavedProgressAt = now
    }

    func stop() {
        guard !hasStopped else { return }
        savePlaybackProgress(force: true)
        hasStopped = true

        externalSubtitles.stop()
        subtitleOptionsItem = nil
        subtitleChanges?.cancel()
        subtitleChanges = nil
        qualityChanges?.cancel()
        qualityChanges = nil
        player.pause()
        recoveryTask?.cancel()
        recoveryTask = nil
        stallTask?.cancel()
        stallTask = nil
        startupTask?.cancel()
        startupTask = nil
        manifestProbeTasks.forEach { $0.cancel() }
        manifestProbeTasks.removeAll()
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerMinutes = nil
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

    static func timeString(_ seconds: Double) -> String {
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

// MARK: - Module Picture in Picture

@MainActor
private final class ModulePictureInPictureController: NSObject, ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false
    @Published private(set) var lastFailure: String?

    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    var isActuallyActive: Bool { controller?.isPictureInPictureActive == true }

    private weak var attachedLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var reviewFailure: Task<Void, Never>?
    private var attemptSerial = 0
    private var lastRequestTime: Date?
    private var manualRequest = false

    func attach(to layer: AVPlayerLayer) {
        guard attachedLayer !== layer else { return }
        // SwiftUI may recreate the view during presentation transitions.
        // Do not destroy a PiP controller while PiP is actively playing.
        if controller?.isPictureInPictureActive == true { return }

        reviewFailure?.cancel()
        reviewFailure = nil
        attemptSerial &+= 1
        possibleObservation?.invalidate()
        possibleObservation = nil
        controller?.delegate = nil
        controller = nil
        attachedLayer = layer
        isPossible = false
        isActive = false
        lastFailure = nil
        lastRequestTime = nil
        manualRequest = false

        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let next = AVPictureInPictureController(playerLayer: layer) else { return }
        next.delegate = self
        next.canStartPictureInPictureAutomaticallyFromInline = true
        controller = next
        possibleObservation = next.observe(
            \.isPictureInPicturePossible, options: [.initial, .new]
        ) { [weak self] observed, change in
            let possible = change.newValue ?? false
            let observedID = ObjectIdentifier(observed)
            Task { @MainActor [weak self] in
                // KVO is nonisolated. Only a Sendable identity crosses actors.
                guard let self,
                      self.controller.map({ ObjectIdentifier($0) }) == observedID else { return }
                self.isPossible = possible
            }
        }
    }

    func start() {
        guard isSupported, let controller else {
            lastFailure = "Picture in Picture isn't available for this video surface."
            return
        }
        guard (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true else {
            lastFailure = "Background playback isn't enabled in this build."
            return
        }
        guard controller.isPictureInPicturePossible || controller.isPictureInPictureActive else {
            lastFailure = "Start video playback and try PiP again."
            return
        }
        requestStart(manual: true)
    }

    func startIfLeavingAppWhilePlaying(_ playing: Bool) {
        guard playing, isSupported, let controller,
              controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive else { return }
        requestStart(manual: false)
    }

    private func requestStart(manual: Bool) {
        guard let controller, !controller.isPictureInPictureActive else { return }
        // AVKit may be automatically starting PiP at the same time we get
        // the foreground transition callback. Coalesce duplicate requests.
        if let lastRequestTime, Date().timeIntervalSince(lastRequestTime) < 2.0 { return }
        lastRequestTime = Date()
        manualRequest = manual
        lastFailure = nil
        reviewFailure?.cancel()
        reviewFailure = nil
        attemptSerial &+= 1
        controller.startPictureInPicture()
    }

    func clearFailure() { lastFailure = nil }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }
}

extension ModulePictureInPictureController: @preconcurrency AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        let reportedID = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self,
                  self.controller.map({ ObjectIdentifier($0) }) == reportedID else { return }
            self.reviewFailure?.cancel()
            self.reviewFailure = nil
            self.manualRequest = false
            self.lastRequestTime = nil
            self.lastFailure = nil
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        let reportedID = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self,
                  self.controller.map({ ObjectIdentifier($0) }) == reportedID else { return }
            self.reviewFailure?.cancel()
            self.reviewFailure = nil
            self.manualRequest = false
            self.lastRequestTime = nil
            self.lastFailure = nil
            self.isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let reportedID = ObjectIdentifier(pictureInPictureController)
        Task { @MainActor [weak self] in
            guard let self,
                  self.controller.map({ ObjectIdentifier($0) }) == reportedID else { return }
            let wasManual = self.manualRequest
            let serial = self.attemptSerial
            self.manualRequest = false
            self.lastRequestTime = nil
            self.reviewFailure?.cancel()
            // A delegate failure may race against a successful automatic
            // PiP start. Only a genuine failed MANUAL attempt shows an error.
            self.reviewFailure = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, let self,
                      self.controller.map({ ObjectIdentifier($0) }) == reportedID,
                      self.attemptSerial == serial,
                      !self.isActive,
                      self.controller?.isPictureInPictureActive != true else { return }
                if wasManual {
                    self.lastFailure = "PiP didn't start this time. Playback is unchanged; try again."
                }
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - Module AVPlayer Surface

private struct ModulePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let aspectFill: Bool
    let pictureInPicture: ModulePictureInPictureController
    let onFirstFrame: (AVPlayerItem?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFirstFrame: onFirstFrame)
    }

    func makeUIView(context: Context) -> ModulePlayerLayerView {
        let view = ModulePlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        context.coordinator.watch(view.playerLayer)
        pictureInPicture.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: ModulePlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.watch(uiView.playerLayer)
        pictureInPicture.attach(to: uiView.playerLayer)
    }

    static func dismantleUIView(_ uiView: ModulePlayerLayerView, coordinator: Coordinator) {
        coordinator.stopWatching()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        var onFirstFrame: (AVPlayerItem?) -> Void
        private var readinessObservation: NSKeyValueObservation?
        private weak var watchedLayer: AVPlayerLayer?

        init(onFirstFrame: @escaping (AVPlayerItem?) -> Void) {
            self.onFirstFrame = onFirstFrame
        }

        func watch(_ layer: AVPlayerLayer) {
            guard watchedLayer !== layer else { return }
            stopWatching()
            watchedLayer = layer
            readinessObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] observed, _ in
                guard observed.isReadyForDisplay else { return }
                let item = observed.player?.currentItem
                DispatchQueue.main.async { [weak self] in self?.onFirstFrame(item) }
            }
        }

        func stopWatching() {
            readinessObservation?.invalidate()
            readinessObservation = nil
            watchedLayer = nil
        }
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

// MARK: - Module AirPlay Button

private struct ModuleAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemTeal
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(
        _ uiView: AVRoutePickerView,
        context: Context
    ) {}
}

// MARK: - Module Video Quality (Batch 03F)

/// Plain metadata only: never retain or display variant URLs or provider headers.
struct ModuleVideoQualityVariant: Sendable {
    let width: Double
    let height: Double
    let peakBitRate: Double?
}

struct ModuleVideoQualityOption: Identifiable, Equatable, Sendable {
    let width: Int
    let height: Int
    let peakBitRate: Double?

    var id: String { "\(width)x\(height)" }
    var title: String { "Up to \(min(width, height))p" }
    var resolution: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
    var detail: String {
        let dimensions = "\(width) × \(height)"
        guard let peakBitRate else { return dimensions + " · Peak bitrate unavailable" }
        let bitrate = peakBitRate >= 1_000_000
            ? String(format: "%.1f Mbps", peakBitRate / 1_000_000)
            : String(format: "%.0f kbps", peakBitRate / 1_000)
        return dimensions + " · Advertised peak " + bitrate
    }
}

enum ModuleVideoQualityCatalog {
    static let maximumVariants = 256
    static let maximumOptions = 32

    static func dimensions(width: Double, height: Double) -> (width: Int, height: Int)? {
        guard width.isFinite, height.isFinite,
              width >= 1, height >= 1, width <= 32_768, height <= 32_768 else { return nil }
        return (Int(width.rounded(.up)), Int(height.rounded(.up)))
    }

    static func options(from variants: [ModuleVideoQualityVariant]) -> [ModuleVideoQualityOption] {
        var grouped: [String: ModuleVideoQualityOption] = [:]
        for variant in variants.prefix(maximumVariants) {
            guard let size = dimensions(width: variant.width, height: variant.height) else { continue }
            let peak = variant.peakBitRate.flatMap { value -> Double? in
                value.isFinite && value > 0 && value <= 1_000_000_000_000 ? value : nil
            }
            let key = "\(size.width)x\(size.height)"
            if let existing = grouped[key] {
                // Different codecs/frame rates can share a resolution. Do not
                // exclude one with an unknown peak by inventing a bitrate limit.
                let combined: Double?
                if let previous = existing.peakBitRate, let peak {
                    combined = max(previous, peak)
                } else {
                    combined = nil
                }
                grouped[key] = ModuleVideoQualityOption(width: size.width, height: size.height, peakBitRate: combined)
            } else {
                grouped[key] = ModuleVideoQualityOption(width: size.width, height: size.height, peakBitRate: peak)
            }
        }
        let sorted = grouped.values.sorted {
            let lhs = $0.width * $0.height
            let rhs = $1.width * $1.height
            return lhs == rhs ? $0.width < $1.width : lhs < rhs
        }
        // A single advertised resolution is not a manual resolution choice.
        guard sorted.count > 1 else { return [] }
        return Array(sorted.prefix(maximumOptions))
    }

    static func preferredPeakBitRate(for option: ModuleVideoQualityOption, in options: [ModuleVideoQualityOption]) -> Double {
        let eligible = options.filter { $0.width <= option.width && $0.height <= option.height }
        // Account for higher-bitrate codecs/frame rates at LOWER resolutions.
        // If any eligible peak is unknown, apply only the resolution preference.
        guard !eligible.isEmpty, eligible.allSatisfy({ $0.peakBitRate != nil }) else { return 0 }
        return eligible.compactMap(\.peakBitRate).max() ?? 0
    }
}

/// Updates preferences on the existing item. It never swaps media playlists,
/// starts playback, seeks, or changes audio/subtitle selections.
@MainActor
final class ModuleVideoQualityController: ObservableObject {
    enum State: Equatable {
        case idle, loading, available, unavailable, failed
    }

    typealias Loader = @MainActor (AVURLAsset) async throws -> [ModuleVideoQualityVariant]

    @Published private(set) var options: [ModuleVideoQualityOption] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var state: State = .idle
    @Published private(set) var presentedResolution: String?

    private weak var item: AVPlayerItem?
    private let loader: Loader
    private let timeout: Duration
    private var requestID: UUID?
    private var discoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var presentationObservation: NSKeyValueObservation?

    var selectionDescription: String {
        options.first(where: { $0.id == selectedID })?.title ?? "Auto"
    }

    init(loader: Loader? = nil, timeout: Duration = .seconds(12)) {
        self.loader = loader ?? { asset in
            let variants = try await asset.load(.variants)
            try Task.checkCancellation()
            return variants.prefix(ModuleVideoQualityCatalog.maximumVariants).compactMap { variant in
                guard let video = variant.videoAttributes else { return nil }
                return ModuleVideoQualityVariant(
                    width: Double(video.presentationSize.width),
                    height: Double(video.presentationSize.height),
                    peakBitRate: variant.peakBitRate
                )
            }
        }
        self.timeout = timeout
    }

    func configure(for item: AVPlayerItem) {
        stop()
        self.item = item
        // Every new episode/server starts in Auto. Do not silently reuse a cap
        // from a different source's resolution ladder.
        item.preferredMaximumResolution = .zero
        item.preferredPeakBitRate = 0
        presentationObservation = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.item === observed else { return }
                self.updatePresentationSize(observed.presentationSize)
            }
        }
        guard let asset = item.asset as? AVURLAsset, !asset.url.isFileURL else {
            state = .unavailable
            return
        }
        state = .loading
        let identity = UUID()
        requestID = identity
        let loader = self.loader
        discoveryTask = Task { [weak self] in
            do {
                let variants = try await loader(asset)
                guard !Task.isCancelled, let self,
                      self.requestID == identity, self.item === item else { return }
                self.finishDiscovery()
                self.options = ModuleVideoQualityCatalog.options(from: variants)
                self.state = self.options.isEmpty ? .unavailable : .available
            } catch {
                guard !Task.isCancelled, let self,
                      self.requestID == identity, self.item === item else { return }
                self.finishDiscovery()
                self.state = .failed
            }
        }
        let timeout = self.timeout
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled, let self,
                      self.requestID == identity, self.item === item else { return }
                // Do not call asset.cancelLoading(): playback shares this asset.
                self.discoveryTask?.cancel()
                self.finishDiscovery()
                self.state = .failed
            } catch {
                // Completed, replaced, retried, or closed.
            }
        }
    }

    func select(_ id: String?) {
        guard let item else { return }
        if let id {
            guard state == .available,
                  let option = options.first(where: { $0.id == id }) else { return }
            item.preferredMaximumResolution = option.resolution
            item.preferredPeakBitRate = ModuleVideoQualityCatalog.preferredPeakBitRate(for: option, in: options)
            selectedID = id
        } else {
            item.preferredMaximumResolution = .zero
            item.preferredPeakBitRate = 0
            selectedID = nil
        }
    }

    func retry() {
        guard state == .failed, let item else { return }
        configure(for: item)
    }

    func stop() {
        discoveryTask?.cancel()
        finishDiscovery()
        presentationObservation?.invalidate()
        presentationObservation = nil
        item?.preferredMaximumResolution = .zero
        item?.preferredPeakBitRate = 0
        item = nil
        options = []
        selectedID = nil
        presentedResolution = nil
        state = .idle
    }

    private func finishDiscovery() {
        requestID = nil
        discoveryTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func updatePresentationSize(_ size: CGSize) {
        let dimensions = ModuleVideoQualityCatalog.dimensions(width: Double(size.width), height: Double(size.height))
        let text = dimensions.map { "\($0.width) × \($0.height)" }
        if presentedResolution != text { presentedResolution = text }
    }
}

// MARK: - Batch 05A Shared Visual Layer
// This is deliberately compiled in ModulePlayerView.swift, which is already
// listed in the Kinetiq app target's PBXSourcesBuildPhase. The earlier
// KinetiqUnifiedPlayer.swift standalone file is NOT in that build phase.

// MARK: - Unified visual layer
//
// The renderer is deliberately independent of AVPlayer and module/networking
// objects. Local and remote playback adapters both drive this same interface.
// Every visible action is forwarded to the active playback engine.

@MainActor
struct KinetiqUnifiedPlayerChrome: View {
    struct Panel: Identifiable {
        let id: String
        let symbol: String
        let selected: Bool
    }

    let safeAreaInsets: EdgeInsets
    let title: String
    let playing: Bool
    let busy: Bool
    let aspectFill: Bool
    let pictureInPictureAvailable: Bool
    let displayedTime: Double
    let duration: Double
    let elapsedLabel: String
    let durationLabel: String
    let panels: [Panel]
    let airPlayControl: AnyView

    let onClose: () -> Void
    let onStartPictureInPicture: () -> Void
    let onToggleAspect: () -> Void
    let onPrevious: () -> Void
    let onRewind: () -> Void
    let onTogglePlay: () -> Void
    let onForward: () -> Void
    let onNext: () -> Void
    let onSeekChanged: (Double) -> Void
    let onSeekEditingChanged: (Bool) -> Void
    let onPanelSelected: (String) -> Void

    var body: some View {
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
                header
                    .padding(.top, max(safeAreaInsets.top, 14))
                Spacer(minLength: 18)
                transport
                Spacer(minLength: 18)
                footer
                    .padding(.bottom, max(safeAreaInsets.bottom, 15))
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 11) {
            headerButton("chevron.down", label: "Close player", size: 15, action: onClose)
                .frame(width: 42, height: 42)

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

            Spacer(minLength: 4)

            airPlayControl
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.34), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                .accessibilityLabel("AirPlay")

            if pictureInPictureAvailable {
                headerButton("pip", label: "Start Picture in Picture", size: 15, action: onStartPictureInPicture)
            }

            headerButton(
                aspectFill
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: aspectFill ? "Fit video to screen" : "Fill screen with video",
                size: 14,
                action: onToggleAspect
            )
        }
    }

    private func headerButton(
        _ symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.34), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var transport: some View {
        HStack(spacing: 13) {
            transportButton("backward.end.fill", size: 18, width: 38,
                            label: "Previous", action: onPrevious)
            transportButton("gobackward.10", size: 25, width: 44,
                            label: "Back 10 seconds", action: onRewind)

            Button(action: onTogglePlay) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().fill(.black.opacity(0.18)))
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 7)
            }
            .accessibilityLabel(playing ? "Pause" : "Play")

            transportButton("goforward.10", size: 25, width: 44,
                            label: "Forward 10 seconds", action: onForward)
            transportButton("forward.end.fill", size: 18, width: 38,
                            label: "Next", action: onNext)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        width: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: width, height: 58)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { min(max(displayedTime.isFinite ? displayedTime : 0, 0), max(duration, 1)) },
                        set: { onSeekChanged($0) }
                    ),
                    in: 0...max(duration.isFinite ? duration : 1, 1),
                    onEditingChanged: onSeekEditingChanged
                )
                .tint(KinetiqPalette.cyan)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(elapsedLabel)
                    Spacer()
                    Text(durationLabel)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
            }

            panelBar
        }
    }

    private var panelBar: some View {
        HStack(spacing: 1) {
            ForEach(panels) { panel in
                Button {
                    onPanelSelected(panel.id)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: panel.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(panel.id)
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(
                        panel.selected
                            ? KinetiqPalette.cyan
                            : .white.opacity(0.92)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.id)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(.black.opacity(0.27)))
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }
}

// MARK: - Shared options-sheet frame

@MainActor
struct KinetiqUnifiedPlayerOptionsFrame<Content: View>: View {
    let title: String
    let symbol: String
    let onClose: () -> Void
    private let content: Content

    init(
        title: String,
        symbol: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(KinetiqPalette.cyan)
                    Text(title)
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
                    content
                }
                .padding(18)
            }
            .frame(maxHeight: 390)
        }
        .background(.ultraThinMaterial)
        .background(Color(red: 0.035, green: 0.045, blue: 0.065).opacity(0.90))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 25, y: -5)
    }
}

// MARK: - Shared playback error presentation

@MainActor
struct KinetiqUnifiedPlayerFailureOverlay: View {
    let message: String
    let onRetry: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Playback issue")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(KinetiqPalette.cyan, in: Capsule())
                }
                Button(action: onSkip) {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.13), in: Capsule())
                }
            }
            .padding(.top, 5)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(30)
    }
}



// MARK: - WebKit-only fallback for provider-supplied player pages (Batch 05C)
// This view is intentionally distinct from the unified native player: WebKit
// cannot guarantee native AVPlayer controls, external subtitle rendering, or
// PiP. It is a secondary option for authorized provider embed pages only.
@MainActor
private struct ModuleWebFallbackPlayer: View {
    let stream: ModuleResolvedStream
    let episodeTitle: String
    let onClose: () -> Void
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Return to native player")

                VStack(alignment: .leading, spacing: 3) {
                    Text(episodeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("Web Player · \(stream.hostName)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "globe")
                    .foregroundStyle(KinetiqPalette.cyan)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                    Text("Web player unavailable")
                        .font(.headline)
                    Text(failure)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Back to Kinetiq", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ModuleEphemeralWebView(
                    url: stream.url,
                    directMedia: !stream.isWebEmbed,
                    failure: $failure
                )
                    .background(.black)
            }

            HStack {
                Image(systemName: "lock.shield")
                Text("Private web session · no app credentials shared")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

@MainActor
private struct ModuleEphemeralWebView: UIViewRepresentable {
    let url: URL
    let directMedia: Bool
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(failure: $failure, allowLocalDocument: directMedia)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        if ModuleWebFallbackPolicy.allows(url) {
            if directMedia {
                // A WKWebView navigation to a raw .m3u8 playlist is NOT a
                // browser video player. Use an actual HTML5 video element so
                // WebKit can attempt native HLS playback as an alternative to
                // our AVPlayerLayer. This is an explicit user-initiated action.
                let escaped = url.absoluteString
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                let page = """
                <!doctype html><html><head>
                <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
                <style>html,body{margin:0;width:100%;height:100%;background:#000}
                video{width:100%;height:100%;object-fit:contain;background:#000}</style>
                </head><body><video controls playsinline autoplay preload="metadata"
                src="\(escaped)"></video></body></html>
                """
                webView.loadHTMLString(page, baseURL: nil)
            } else {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                webView.load(request)
            }
        } else {
            failure = "This server does not provide a permitted HTTPS web address."
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var failure: String?
        private let allowLocalDocument: Bool

        init(failure: Binding<String?>, allowLocalDocument: Bool) {
            _failure = failure
            self.allowLocalDocument = allowLocalDocument
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Let same-page media subresources load normally; block new
            // windows, non-HTTPS top-level redirects, and local addresses.
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true {
                guard let url = navigationAction.request.url else {
                    decisionHandler(.cancel)
                    return
                }
                if allowLocalDocument && url.absoluteString == "about:blank" {
                    decisionHandler(.allow)
                    return
                }
                guard ModuleWebFallbackPolicy.allows(url) else {
                    failure = "This web player tried to navigate to an unsupported address."
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failure = "The provider's web page could not finish loading."
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failure = "The provider's web page could not be opened."
        }
    }
}


// MARK: - HLS Transport Preflight (Batch 05H)

/// Probe only the original module-supplied HTTPS playlist on a failed host.
/// No URLs, paths, query strings, authentication material, or response bodies
/// are copied into diagnostics. The probe does not bypass provider access.
private enum ModuleHLSPreflight {
    private static let maximumManifestBytes = 131_072

    static func safeDomain(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(String.UnicodeScalarView(text.unicodeScalars.filter {
            allowed.contains($0)
        }).prefix(80))
    }

    static func inspect(_ stream: ModuleResolvedStream) async -> [String] {
        guard stream.url.scheme?.lowercased() == "https",
              let originalHost = stream.url.host?.lowercased(),
              !originalHost.isEmpty else {
            return ["HLS preflight: skipped; invalid HTTPS playlist address"]
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 9
        configuration.timeoutIntervalForResource = 11

        // Inject cookies into this isolated, transient storage. URLSession
        // performs normal domain/path/secure checks for each cookie.
        for stored in stream.cookies.prefix(40) {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: stored.name,
                .value: stored.value,
                .domain: stored.domain,
                .path: stored.path,
                .secure: stored.isSecure ? "TRUE" : "FALSE"
            ]
            if let cookie = HTTPCookie(properties: properties) {
                configuration.httpCookieStorage?.setCookie(cookie)
            }
        }

        let guardDelegate = ModuleHLSProbeRedirectGuard(host: originalHost)
        let client = URLSession(configuration: configuration,
                                delegate: guardDelegate, delegateQueue: nil)
        defer { client.invalidateAndCancel() }

        var request = URLRequest(url: stream.url)
        request.timeoutInterval = 9
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
                         forHTTPHeaderField: "Accept")
        for (name, value) in stream.headers {
            guard !name.isEmpty, !name.contains("\r"), !name.contains("\n"),
                  !value.contains("\r"), !value.contains("\n") else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            // Stream bytes incrementally: a mislabeled media file must never
            // be downloaded in full merely to inspect an HLS manifest.
            let (bytes, response) = try await client.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ["HLS preflight: response was not HTTP"]
            }
            let status = http.statusCode
            var results = ["HLS preflight HTTP status: \(status)"]
            if !(200...299).contains(status) {
                results.append("HLS preflight: playlist request not successful")
                return results
            }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                .lowercased()
            var data = Data()
            for try await byte in bytes {
                if Task.isCancelled { return ["HLS preflight: cancelled"] }
                if data.count >= maximumManifestBytes { break }
                data.append(byte)
            }
            results.append(contentsOf: manifestSummary(data, mime: mime))
            return results
        } catch {
            let nsError = error as NSError
            return ["HLS preflight transport: \(safeDomain(nsError.domain)) / \(nsError.code)"]
        }
    }

    static func manifestSummary(_ data: Data, mime: String) -> [String] {
        let mimeKind: String = mime.contains("mpegurl") || mime.contains("m3u8")
            ? "HLS" : mime.contains("text/html") ? "HTML"
            : mime.contains("application/json") ? "JSON"
            : mime.isEmpty ? "unspecified" : "other"
        var results = ["HLS response MIME category: \(mimeKind)"]
        guard let body = String(data: data, encoding: .utf8) else {
            results.append("HLS preflight: response is not UTF-8 playlist text")
            return results
        }
        let hasBOM = body.hasPrefix("\u{FEFF}")
        let withoutBOM = hasBOM ? String(body.dropFirst()) : body
        let trimmed = withoutBOM.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasBOM { results.append("HLS compatibility warning: UTF-8 BOM") }
        guard trimmed.hasPrefix("#EXTM3U") else {
            results.append(body.lowercased().contains("<html") ||
                           body.lowercased().contains("<!doctype")
                           ? "HLS preflight: server returned HTML instead of a playlist"
                           : "HLS preflight: response is not a valid HLS manifest")
            return results
        }
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        let variants = lines.filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }.count
        let segmentDurations = lines.filter { $0.hasPrefix("#EXTINF:") }.count
        let keyTags = lines.filter { $0.hasPrefix("#EXT-X-KEY:") }
        let encrypted = keyTags.contains { !$0.contains("METHOD=NONE") }
        let uris = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let unusual = uris.filter { line in
            let path = line.components(separatedBy: "?").first ?? line
            let lower = path.lowercased()
            return [".html", ".htm", ".jpg", ".jpeg", ".png", ".php"]
                .contains { lower.hasSuffix($0) }
        }.count
        results.append("HLS manifest: valid; variants=\(variants), media segments=\(segmentDurations), encryption=\(encrypted)")
        if unusual > 0 {
            results.append("HLS compatibility warning: \(unusual) nonstandard media/playlist suffixes")
        }
        if variants == 0 && segmentDurations == 0 {
            results.append("HLS compatibility warning: no variants or media segments in sampled data")
        }
        results.append("HLS preflight checks playlist only, not media segments")
        return results
    }
}

/// Never forward authorization/cookies from the module's host to a different
/// host through a diagnostic redirect. This does not affect AVPlayer itself.
private final class ModuleHLSProbeRedirectGuard: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    init(host: String) { self.host = host }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https",
              request.url?.host?.lowercased() == host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

// MARK: - Batch 06C: Transparent native-caption styling preferences
// AVTextStyleRule applies only to native WebVTT. Closed captions, some HLS
// formats and the system PiP UI can instead obey Apple's accessibility styles.
// No code here claims to turn overlay SRT/WebVTT into PiP native captions.
private enum KinetiqModuleNativeCaptionStyle {
    static func rules(
        for appearance: KinetiqSubtitleAppearance,
        inPiP: Bool
    ) -> [AVTextStyleRule]? {
        var attributes: [String: Any] =
            appearance.nativeRules?.first?.textMarkupAttributes ?? [:]

        // Native captions may use either a box behind the whole line or boxes
        // behind individual glyphs. Explicitly request transparent geometry
        // for both; a simple zero-alpha SwiftUI overlay cannot change these.
        if appearance.background == .clear {
            let clear: [Double] = [0.0, 0.0, 0.0, 0.0]
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = clear
            attributes[kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String] = clear
        }

        // The in-player default already has a readable size. PiP's much smaller
        // video rectangle may render the system default too small. Increase the
        // *WebVTT style preference* only for the PiP handoff and restore after.
        // The exact final size remains under AVFoundation/iOS control.
        if inPiP {
            let target: Double
            switch appearance.size {
            case .small: target = 4.4
            case .standard: target = 6.0
            case .large: target = 7.5
            }
            attributes[kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight as String] = target
        }

        guard !attributes.isEmpty,
              let rule = AVTextStyleRule(textMarkupAttributes: attributes) else {
            return nil
        }
        return [rule]
    }
}

// MARK: - Batch 06C: Streaming-first loading experience
// A real activity log, not a simulated percent bar or fictitious download
// progress. Event texts are already redacted by ModulePlaybackDiagnostics.
@MainActor
private struct KinetiqModuleLoadingScene: View {
    let title: String
    let sourceName: String
    let phase: String
    let isResolving: Bool
    let hasServer: Bool
    let recentEvents: [String]
    let startedAt: Date
    let onCopy: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRaw = KinetiqVisualTheme.signature.rawValue
    @AppStorage(KinetiqMotionMode.storageKey)
    private var motionRaw = KinetiqMotionMode.balanced.rawValue
    @State private var glow = false
    @State private var expandedConsole = true

    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRaw) ?? .signature
    }
    private var shouldAnimate: Bool {
        !reduceMotion && motionRaw != KinetiqMotionMode.quiet.rawValue
    }
    private var currentStep: Int {
        if isResolving && !hasServer { return 0 }
        if !hasServer { return 1 }
        return 2
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.backdrop.ignoresSafeArea()
                RadialGradient(
                    colors: [theme.accent.opacity(0.21), theme.backdrop.opacity(0.1), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.95
                ).ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 6)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            loadingEmblem
                            VStack(spacing: 8) {
                                Text("GETTING YOUR STREAM READY")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(2.3)
                                    .foregroundStyle(theme.accent)
                                Text(title.isEmpty ? "Preparing episode" : title)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.82)
                                Text(phase)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.67))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            progressSteps
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                let elapsed = max(0, Int(timeline.date.timeIntervalSince(startedAt)))
                                VStack(spacing: 4) {
                                    Text("\(elapsed)s elapsed")
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                    if elapsed >= 12 {
                                        Text("Some sources need extra time to resolve a server, redirect, or media playlist. You can inspect the real events below.")
                                            .font(.caption2)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.white.opacity(0.52))
                                    }
                                }
                            }
                            liveConsole
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                    }
                    Spacer(minLength: 4)
                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear { glow = true }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("KINETIQ PLAYER")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                Text(sourceName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.63))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.11), in: Circle())
            }
            .accessibilityLabel("Close player")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 23)
        .padding(.top, 22)
    }

    private var loadingEmblem: some View {
        ZStack {
            Circle()
                .stroke(theme.accent.opacity(0.16), lineWidth: 2)
                .frame(width: 112, height: 112)
                .scaleEffect(glow && shouldAnimate ? 1.12 : 0.91)
                .opacity(glow && shouldAnimate ? 0.56 : 0.95)
                .animation(
                    shouldAnimate ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true) : nil,
                    value: glow
                )
            Circle()
                .fill(LinearGradient(colors: [theme.accent.opacity(0.28), theme.highlight.opacity(0.09)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 86, height: 86)
            Image(systemName: "play.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(.white)
                .offset(x: 3)
        }
        .accessibilityLabel("Loading video")
    }

    private var progressSteps: some View {
        VStack(spacing: 10) {
            step(index: 0, symbol: "square.stack", label: "Resolve source")
            step(index: 1, symbol: "server.rack", label: "Find media server")
            step(index: 2, symbol: "play.rectangle.on.rectangle", label: "Prepare video playback")
        }
        .padding(16)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 19))
    }

    private func step(index: Int, symbol: String, label: String) -> some View {
        let completed = index < currentStep
        let current = index == currentStep
        return HStack(spacing: 12) {
            Image(systemName: completed ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(completed || current ? theme.accent : .white.opacity(0.48))
                .frame(width: 25)
            Text(label)
                .font(.subheadline.weight(current ? .semibold : .regular))
                .foregroundStyle(.white.opacity(current || completed ? 1 : 0.58))
            Spacer()
            if current {
                ProgressView().tint(theme.accent).controlSize(.mini)
            } else if completed {
                Text("READY").font(.system(size: 9, weight: .heavy))
                    .tracking(1.1).foregroundStyle(theme.accent.opacity(0.8))
            }
        }
    }

    private var liveConsole: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(shouldAnimate ? .easeInOut(duration: 0.2) : nil) {
                    expandedConsole.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").foregroundStyle(theme.accent)
                    Text("LIVE LOADING LOG")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                    Spacer()
                    Text("\(recentEvents.count) EVENTS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: expandedConsole ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)
            if expandedConsole {
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                VStack(alignment: .leading, spacing: 9) {
                    if recentEvents.isEmpty {
                        Text("Awaiting source and player events…")
                            .foregroundStyle(.white.opacity(0.53))
                    } else {
                        ForEach(Array(recentEvents.enumerated()), id: \.offset) { index, event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(String(format: "%02d", index + 1))
                                    .foregroundStyle(theme.accent.opacity(0.75))
                                Text(event)
                                    .foregroundStyle(.white.opacity(0.73))
                            }
                        }
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                Button(action: onCopy) {
                    Label("Copy sanitized diagnostics", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copies playback diagnostics with sensitive URLs and credentials redacted")
            }
        }
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
            Text("No stream addresses or credentials are shown")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.47))
        .padding(.horizontal, 18)
        .padding(.bottom, 25)
    }
}