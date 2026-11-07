import SwiftUI
import AVKit
import AVFoundation
import Combine
import UIKit

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

    @State private var controlsVisible = true
    @State private var activePanel: ModulePlayerPanel?

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var seekFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var autoHideTask: Task<Void, Never>?

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

                if playback.isBuffering && playback.errorMessage == nil {
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
                .spring(response: 0.34, dampingFraction: 0.88),
                value: activePanel
            )
            .onAppear {
                revealControls()
            }
            .onDisappear {
                autoHideTask?.cancel()
                feedbackTask?.cancel()
                playback.stop()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )) { _ in
                playback.persistCurrentProgress()
            }
            .onChange(of: subtitleSettings.appearance) { _, style in
                playback.player.currentItem?.textStyleRules = style.nativeRules
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
            pictureInPictureAvailable: pictureInPicture.isPossible,
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
            onStartPictureInPicture: { pictureInPicture.start() },
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
                session: session
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
                            subtitle: "\(stream.hostName) • \(stream.streamType.uppercased())",
                            symbol: "server.rack",
                            selected: session.currentStream?.id == stream.id
                        ) {
                            playback.selectServer(stream)
                            onClose()
                        }
                    }

                    if session.availableStreams.count == 1 {
                        Text("This module returned one playable stream. Other servers appear here only when the module provides them.")
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
                Text("Source subtitles display in the app. They are not yet shown in Picture in Picture or on AirPlay video.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

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

                sectionLabel("STREAM INFORMATION")
                informationRow("Source", value: session.sourceName)
                informationRow(
                    "Selected server",
                    value: session.currentStream?.label ?? "None"
                )
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
            "Kinetiq module playback diagnostics",
            "Source: \(session.sourceName)",
            "Episode: \(session.currentEpisode?.number ?? "Unknown")",
            "Language: \(session.selectedLanguage)",
            "Server label: \(session.currentStream?.label ?? "None")",
            "Host: \(session.currentStream?.hostName ?? "None")",
            "Stream type: \(session.currentStream?.streamType ?? "Unknown")",
            "Playback state: \(playbackStatus)",
            "HTTP status: \(lastHTTPStatus.map(String.init) ?? "Unknown")",
            "Player resolution: \(resolutionText)",
            "Quality preference: \(videoQuality.selectionDescription)",
            "Current presentation: \(videoQuality.presentedResolution ?? "Not reported")",
            "Events:"
        ]
        return (lines + diagnosticEvents).joined(separator: "\n")
    }

    private func note(_ event: String) {
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 14 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 14)
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

                if observedPlayer.timeControlStatus == .playing {
                    self.playbackStatus = "Playing"
                    self.stallTask?.cancel()
                    self.stallTask = nil
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

        attemptedStreamIDs.insert(stream.id)
        isHandlingStreamFailure = false
        lastStreamID = stream.id
        lastHTTPStatus = nil
        playbackStatus = "Opening \(stream.label)"
        note("Opening \(stream.label) on \(stream.hostName)")
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
        externalSubtitles.configure(tracks: stream.subtitles)

        removeCurrentItemObservers()

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
        item.textStyleRules = KinetiqSubtitleSettings.shared.appearance.nativeRules
        item.preferredForwardBufferDuration = 8

        player.replaceCurrentItem(with: item)
        videoQuality.configure(for: item)

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
                                self.player.playImmediately(atRate: self.playbackRate)
                            }
                        }
                    } else {
                        self.isRestoringPosition = false
                        self.externalSubtitles.updatePlaybackTime(self.player.currentTime().seconds)
                        self.player.playImmediately(atRate: self.playbackRate)
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

        // Read only a numeric status: never expose token-bearing URLs or
        // raw response headers from AVFoundation logs.
        let status = item.errorLog()?.events.last?.errorStatusCode
        if let status, (100...599).contains(status) {
            lastHTTPStatus = status
        }

        let reason = lastHTTPStatus.map { "HTTP \($0)" }
            ?? "AVPlayer failure"
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

        if let alternate = session.availableStreams.first(where: {
            !attemptedStreamIDs.contains($0.id)
        }) {
            playbackStatus = "Switching to \(alternate.label)"
            note("Automatic fallback: \(alternate.label)")
            _ = session.selectStream(alternate)
            return
        }

        playbackStatus = "Playback failed"
        if authorizationRejected {
            errorMessage = "The server denied playback (HTTP \(lastHTTPStatus ?? 403)). Try a different source or language."
        } else {
            errorMessage = message
        }
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
        if let option {
            guard subtitleOptions.contains(option), subtitleOptionsItem === player.currentItem else { return }
            captionChoice = .embedded(KinetiqCaptionLanguage(option))
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
            refreshCaptions(preference: KinetiqSubtitleSettings.shared.language)
        }
    }

    func selectExternalSubtitle(_ track: ModuleRemoteSubtitleTrack) {
        guard canSelectSourceSubtitle, let item = player.currentItem,
              externalSubtitles.tracks.contains(where: { $0.id == track.id }) else { return }
        captionChoice = .source
        selectedSubtitle = KinetiqCaptionTarget.manualSource.apply(to: item, group: subtitleGroup)
        externalSubtitles.updatePlaybackTime(isRestoringPosition ? .nan : player.currentTime().seconds)
        externalSubtitles.select(track)
    }

    func useSubtitleDefault() {
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
        if player.timeControlStatus == .playing {
            persistCurrentProgress()
            player.pause()
        } else {
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
private final class ModulePictureInPictureController:
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

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        guard let pipController =
            AVPictureInPictureController(playerLayer: layer) else {
            return
        }

        pipController.delegate = self
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pipController

        possibleObservation = pipController.observe(
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

extension ModulePictureInPictureController:
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
        completionHandler(true)
    }
}

// MARK: - Module AVPlayer Surface

private struct ModulePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let aspectFill: Bool
    let pictureInPicture: ModulePictureInPictureController

    func makeUIView(context: Context) -> ModulePlayerLayerView {
        let view = ModulePlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = aspectFill
            ? .resizeAspectFill
            : .resizeAspect
        view.backgroundColor = .black
        pictureInPicture.attach(to: view.playerLayer)
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
        pictureInPicture.attach(to: uiView.playerLayer)
    }

    static func dismantleUIView(
        _ uiView: ModulePlayerLayerView,
        coordinator: ()
    ) {
        uiView.playerLayer.player = nil
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

