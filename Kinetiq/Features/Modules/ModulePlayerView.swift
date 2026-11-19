import SwiftUI
import AVKit
import AVFoundation
import Combine
import UIKit
import WebKit
import CoreMedia
import CryptoKit

/// Exact timecode entry is independent of a particular streaming server.
/// Rejects negative, malformed and minute/second overflow values.
enum KinetiqTimecodeParser {
    static func seconds(from input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 18 else { return nil }
        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        let numbers = components.compactMap { component -> Int? in
            let part = String(component).trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }) else { return nil }
            return Int(part)
        }
        guard numbers.count == components.count,
              numbers.allSatisfy({ $0 >= 0 && $0 <= 10_000 }) else { return nil }
        if numbers.count >= 2 && numbers[numbers.count - 1] > 59 { return nil }
        if numbers.count == 3 && numbers[1] > 59 { return nil }
        let total = numbers.reduce(0) { result, value in result * 60 + value }
        return Double(total)
    }
}

enum KinetiqPlayerSeekPolicy {
    static func safeInterval(_ value: Int) -> Int {
        [5, 10, 15, 30, 60].contains(value) ? value : 10
    }
}

// MARK: - M03: Private, user-confirmed scene markers

/// Manual segments only. Kinetiq never guesses that an intro or credits are
/// present, and a marker from a different provider/episode is never reused.
enum KinetiqManualChapterKind: String, Codable, CaseIterable, Identifiable {
    case opening = "Opening"
    case recap = "Recap"
    case ending = "Ending / Credits"
    var id: String { rawValue }
}

struct KinetiqManualChapter: Codable, Identifiable {
    var id: String { mediaKey + "|" + episodeKey + "|" + kind.rawValue + "|" + (streamKey ?? "legacy") }
    let mediaKey: String
    let episodeKey: String
    let kind: KinetiqManualChapterKind
    var start: Double
    var end: Double?
    // Optional for backwards compatibility with M03's saved JSON; a legacy
    // marker is preserved but cannot authorize a new floating skip prompt.
    var streamKey: String? = nil
    var expectedDuration: Double? = nil

    var isSkippable: Bool {
        guard let end else { return false }
        return start.isFinite && end.isFinite && start >= 0 && end > start + 1
    }
}

@MainActor
final class KinetiqManualChapterStore: ObservableObject {
    static let shared = KinetiqManualChapterStore()
    @Published private(set) var chapters: [KinetiqManualChapter] = []
    private let defaults: UserDefaults
    private let key = "kinetiq.player.manualChapters.m03.v1"
    private let limit = 400

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KinetiqManualChapter].self, from: data) {
            chapters = Array(decoded.filter { $0.start.isFinite && $0.start >= 0 }.prefix(limit))
        }
    }

    func chapter(mediaKey: String, episodeKey: String,
                 kind: KinetiqManualChapterKind,
                 streamKey: String? = nil) -> KinetiqManualChapter? {
        chapters.first { $0.mediaKey == mediaKey && $0.episodeKey == episodeKey &&
            $0.kind == kind && $0.streamKey == streamKey }
    }

    func markStart(mediaKey: String, episodeKey: String,
                   kind: KinetiqManualChapterKind, seconds: Double,
                   streamKey: String? = nil, expectedDuration: Double? = nil) {
        guard seconds.isFinite, seconds >= 0 else { return }
        chapters.removeAll { $0.mediaKey == mediaKey && $0.episodeKey == episodeKey &&
            $0.kind == kind && $0.streamKey == streamKey }
        chapters.insert(KinetiqManualChapter(mediaKey: mediaKey, episodeKey: episodeKey,
            kind: kind, start: seconds, end: nil, streamKey: streamKey,
            expectedDuration: expectedDuration), at: 0)
        save()
    }

    func markEnd(mediaKey: String, episodeKey: String,
                 kind: KinetiqManualChapterKind, seconds: Double,
                 streamKey: String? = nil) -> Bool {
        guard seconds.isFinite, let index = chapters.firstIndex(where: {
            $0.mediaKey == mediaKey && $0.episodeKey == episodeKey &&
            $0.kind == kind && $0.streamKey == streamKey
        }), seconds > chapters[index].start + 1 else { return false }
        chapters[index].end = seconds
        save()
        return true
    }

    func delete(_ chapter: KinetiqManualChapter) {
        chapters.removeAll { $0.id == chapter.id }
        save()
    }

    private func save() {
        if chapters.count > limit { chapters.removeLast(chapters.count - limit) }
        if let data = try? JSONEncoder().encode(chapters) { defaults.set(data, forKey: key) }
    }
}

// MARK: - M03/M04: Contextual, source-verified skip buttons

enum KinetiqChapterStreamIdentity {
    static func key(host: String, label: String, type: String) -> String {
        // Never persist a raw server URL, hostname, or provider label in
        // playback marker records. A stable one-way fingerprint is sufficient.
        let normalized = [host, label, type].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.joined(separator: "|")
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// Only a complete, user-saved segment for the exact provider/title/episode
/// may trigger a contextual skip. Title similarity or a generic time range
/// is never sufficient evidence of where an opening or credits begins.
enum KinetiqContextualSkipPolicy {
    static func matchesVerifiedEdition(
        _ chapter: KinetiqManualChapter, streamKey: String, duration: Double
    ) -> Bool {
        guard chapter.isSkippable, !streamKey.isEmpty,
              chapter.streamKey == streamKey,
              let expectedDuration = chapter.expectedDuration,
              expectedDuration.isFinite, expectedDuration > 0,
              duration.isFinite, duration > 0 else { return false }
        return abs(expectedDuration - duration) <= min(5, max(1, duration * 0.002))
    }

    static func eligibleChapter(
        _ chapters: [KinetiqManualChapter],
        mediaKey: String,
        episodeKey: String,
        streamKey: String,
        position: Double,
        duration: Double
    ) -> KinetiqManualChapter? {
        guard !mediaKey.isEmpty, !episodeKey.isEmpty, !streamKey.isEmpty,
              position.isFinite, position >= 0,
              duration.isFinite, duration > 0 else { return nil }
        for kind in KinetiqManualChapterKind.allCases {
            if let chapter = chapters.first(where: {
                $0.mediaKey == mediaKey && $0.episodeKey == episodeKey &&
                $0.streamKey == streamKey && $0.kind == kind && $0.isSkippable
            }), let end = chapter.end,
               matchesVerifiedEdition(chapter, streamKey: streamKey, duration: duration),
               end <= duration + 1,
               position >= chapter.start, position < end - 0.25 {
                return chapter
            }
        }
        return nil
    }

    static func nextEpisodeAvailable(
        position: Double, duration: Double,
        hasNextEpisode: Bool, verifiedCredits: Bool
    ) -> Bool {
        guard hasNextEpisode, position.isFinite, duration.isFinite,
              position >= 0, duration > 20 else { return false }
        return verifiedCredits || (position >= duration - 20 && position <= duration + 2)
    }

    static func label(for kind: KinetiqManualChapterKind) -> String {
        switch kind {
        case .opening: return "Skip Intro"
        case .recap: return "Skip Recap"
        case .ending: return "Skip Credits"
        }
    }
}

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

/// Confirmation applies only to the transport arrows beside Play/Pause.
/// Contextual Netflix-style Next Episode and autoplay remain one tap.
private enum KinetiqTransportEpisodeChange: String, Identifiable {
    case previous = "Previous"
    case next = "Next"
    var id: String { rawValue }
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
    @StateObject private var subStudio = KinetiqSubStudioController()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasOrientationLease = false
    @State private var controlsVisible = true
    @State private var controlsLocked = false
    @State private var pendingTransportChange: KinetiqTransportEpisodeChange?
    @State private var hasPresentedVideoOnce = false
    @StateObject private var manualChapters = KinetiqManualChapterStore.shared
    @AppStorage("kinetiq.player.contextualSkipButtons.v1") private var contextualSkipButtonsEnabled = true
    @State private var dismissedSkipChapterID: String?
    @AppStorage("kinetiq.player.m03.holdFastPlayback") private var holdFastPlaybackEnabled = true
    @State private var holdFastTask: Task<Void, Never>?
    @State private var rateBeforeFastHold: Float?
    @AppStorage("kinetiq.player.m03.doubleTapSeekSeconds") private var doubleTapSeekSeconds = 10
    @AppStorage("kinetiq.player.m03.remainingClock") private var displaysRemainingTime = false
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
    @State private var initialResolutionStarted = false

    // An initial episode is resolved INSIDE the already presented player.
    // The single loading scene remains portrait until AVPlayer has a frame.
    private let initialEpisode: ModuleAnimeEpisode?
    private let initialLanguage: String
    private let onInitialResolution: (@MainActor () -> Void)?

    private let autoHideDelay: Duration = .seconds(3.4)

    init(
        session: ModuleEpisodePlaybackSession,
        initialEpisode: ModuleAnimeEpisode? = nil,
        initialLanguage: String = "sub",
        onInitialResolution: (@MainActor () -> Void)? = nil
    ) {
        self.initialEpisode = initialEpisode
        self.initialLanguage = initialLanguage
        self.onInitialResolution = onInitialResolution
        _session = ObservedObject(wrappedValue: session)
        _playback = StateObject(
            wrappedValue: ModulePlayerPlaybackController(session: session)
        )
    }

    private var displayedTime: Double {
        isSeeking ? seekPosition : playback.currentTime
    }

    private var currentSkipChapter: KinetiqManualChapter? {
        guard contextualSkipButtonsEnabled,
              let episode = session.currentEpisode,
              let stream = session.currentStream else { return nil }
        let module = session.sourceID ?? session.sourceName
        let item = session.animeItem?.id ?? session.animeTitle
        let mediaKey = "\(module.count):\(module)|\(item)"
        return KinetiqContextualSkipPolicy.eligibleChapter(
            manualChapters.chapters, mediaKey: mediaKey,
            episodeKey: episode.id,
            streamKey: KinetiqChapterStreamIdentity.key(
                host: stream.hostName, label: stream.label, type: stream.streamType),
            position: playback.currentTime, duration: playback.duration
        )
    }

    private var nextPlayableEpisode: ModuleAnimeEpisode? {
        session.upcomingEpisodes.first { episode in
            session.supports("sub", for: episode) || session.supports("dub", for: episode)
        }
    }

    private var canOfferNextEpisode: Bool {
        return KinetiqContextualSkipPolicy.nextEpisodeAvailable(
            position: playback.currentTime, duration: playback.duration,
            hasNextEpisode: nextPlayableEpisode != nil,
            verifiedCredits: currentSkipChapter?.kind == .ending
        )
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
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 25,
                        pressing: handleFastHold, perform: {})
                    .accessibilityLabel("Show or hide playback controls")

                if !pictureInPicture.isActive,
                   (playback.externalSubtitles.currentText != nil ||
                    subStudio.secondaryText != nil || subStudio.tertiaryText != nil) {
                    VStack {
                        Spacer()
                        KinetiqSubStudioCaptionStack(
                            primary: playback.externalSubtitles.currentText,
                            primaryLanguage: playback.externalSubtitles.tracks.first {
                                $0.id == playback.externalSubtitles.selectedTrackID
                            }?.language,
                            studio: subStudio
                        )
                            .padding(.horizontal, 24)
                            .padding(.bottom, controlsVisible ? 130 :
                                max(geometry.safeAreaInsets.bottom + 40, 56))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .zIndex(1)
                }

                if controlsLocked {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                controlsLocked = false
                                revealControls()
                            } label: {
                                Label("Unlock Player", systemImage: "lock.open.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Unlocks player seeking and episode controls")
                        }
                        Spacer()
                    }
                    .padding(24)
                    .zIndex(7)
                }

                if controlsVisible && !controlsLocked {
                    controlOverlay(
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

                // Netflix-style contextual actions use only manually verified,
                // provider/episode-specific markers. They remain discoverable
                // even with the main player chrome hidden.
                if !controlsLocked, activePanel == nil, webPlayerStream == nil,
                   !pictureInPicture.isActive, playback.errorMessage == nil,
                   !playback.isResolvingEpisode, playback.hasFinishedPresentingFirstFrame {
                    contextualPlaybackActions(safeAreaInsets: geometry.safeAreaInsets)
                        .zIndex(2.5)
                }

                // Single portrait-first launch scene for both JavaScript
                // resolution and actual AVPlayer first-frame readiness.
                // A compact spinner is only used for later rebuffering.
                if playback.errorMessage == nil,
                   webPlayerStream == nil,
                   (playback.isResolvingEpisode ||
                    !playback.hasFinishedPresentingFirstFrame) {
                    if hasPresentedVideoOnce {
                        // Episode changes never recreate the first-launch
                        // portrait scene. The existing player stays mounted.
                        VStack(spacing: 10) {
                            ProgressView().tint(.white).scaleEffect(1.1)
                            Text("Opening \(session.currentEpisodeTitle)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(playback.playbackStatus)
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .frame(maxWidth: 340)
                        .transition(.opacity)
                        .zIndex(3)
                    } else {
                        KinetiqModuleLoadingScene(
                            title: initialEpisode.map {
                                "\(session.animeTitle) · Episode \($0.number)"
                            } ?? session.currentEpisodeTitle,
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
                    }
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
                        guard activePanel == nil, !controlsLocked else { return }

                        let isLeftSide =
                            value.location.x < geometry.size.width / 2

                        let interval = Double(KinetiqPlayerSeekPolicy.safeInterval(doubleTapSeekSeconds))
                        let seconds: Double = isLeftSide ? -interval : interval
                        playback.seek(by: seconds)
                        showSeekFeedback(
                            isLeftSide ? "−\(Int(interval)) seconds" : "+\(Int(interval)) seconds"
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
                // The launch scene must stay portrait while a server resolves
                // AND while AVPlayer is waiting for its first real frame.
                KinetiqPlaybackPresentation.preparePlayer(playback.player)
                if playback.hasFinishedPresentingFirstFrame {
                    hasPresentedVideoOnce = true
                    activateLandscapeIfNeeded()
                }
                revealControls()
                displayEmbeddedPlayerIfNeeded()
                subStudio.configure(tracks: session.currentStream?.subtitles ?? [])
                subStudio.updatePlaybackTime(playback.currentTime)
                updateDiscordPresence()
            }
            .task {
                // Begin after presentation, not from the details screen;
                // this makes the portrait loader the only startup scene.
                guard let initialEpisode, !initialResolutionStarted else { return }
                initialResolutionStarted = true
                let didResolve = await session.play(
                    episode: initialEpisode,
                    language: initialLanguage
                )
                if didResolve && !Task.isCancelled {
                    onInitialResolution?()
                }
            }
            .onChange(of: playback.hasFinishedPresentingFirstFrame) { _, ready in
                if ready {
                    hasPresentedVideoOnce = true
                    activateLandscapeIfNeeded()
                }
            }
            .onChange(of: webPlayerStream?.id) { _, id in
                // A web-embed has no AVPlayerLayer first-frame callback.
                // Enter landscape only once its web surface is presented.
                if id != nil { activateLandscapeIfNeeded() }
            }
            .onChange(of: session.currentStream?.id) { _, _ in
                loadingStartedAt = Date()
                displayEmbeddedPlayerIfNeeded()
                subStudio.configure(tracks: session.currentStream?.subtitles ?? [])
                subStudio.updatePlaybackTime(playback.currentTime)
            }
            .onChange(of: session.currentEpisode?.id) { _, _ in
                loadingStartedAt = Date()
                dismissedSkipChapterID = nil
                updateDiscordPresence()
            }
            .onDisappear {
                if hasOrientationLease {
                    KinetiqPlaybackPresentation.leavePlayer()
                    hasOrientationLease = false
                }
                autoHideTask?.cancel()
                holdFastTask?.cancel()
                holdFastTask = nil
                rateBeforeFastHold = nil
                feedbackTask?.cancel()
                subStudio.stop()
                pipCaptionRollbackTask?.cancel()
                if let reason = playback.errorMessage {
                    session.recordPlayerFailure(
                        diagnostics: playback.diagnosticSummary, reason: reason
                    )
                } else {
                    session.clearPlayerFailure()
                }
                if !pictureInPicture.isActive {
                    KinetiqDiscordPresenceManager.shared.playbackEnded()
                    playback.stop()
                }
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
                // A countdown that becomes invisible should not strand the
                // next episode while the user leaves for system PiP.
                if playback.nextEpisodeCountdown != nil {
                    playback.playNext()
                }
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
            .onChange(of: subtitleSettings.sourceTimingOffset) { _, _ in
                playback.externalSubtitles.updatePlaybackTime(playback.currentTime)
                subStudio.updatePlaybackTime(.nan)
                subStudio.updatePlaybackTime(playback.currentTime)
            }
            .onChange(of: playback.externalSubtitles.selectedTrackID) { _, selected in
                guard let selected else { return }
                if subStudio.secondaryTrackID == selected {
                    subStudio.select(nil, for: .secondary)
                }
                if subStudio.tertiaryTrackID == selected {
                    subStudio.select(nil, for: .tertiary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.mediaSelectionDidChangeNotification).receive(on: DispatchQueue.main)) { event in
                playback.syncCaptionSelection(for: event.object as? AVPlayerItem)
            }
            .onChange(of: playback.isPlaying) { _, playing in
                updateDiscordPresence()
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
                updateDiscordPresence()
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
            .onChange(of: playback.currentTime) { _, _ in
                subStudio.updatePlaybackTime(playback.currentTime)
                if dismissedSkipChapterID != nil,
                   currentSkipChapter?.id != dismissedSkipChapterID {
                    dismissedSkipChapterID = nil
                }
                // The presence manager deduplicates and limits network updates
                // to a 30-second cadence; never send one per AVPlayer tick.
                updateDiscordPresence()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(hasOrientationLease)
        .persistentSystemOverlays(hasOrientationLease ? .hidden : .automatic)
        .background(.black)
        .alert("Picture in Picture", isPresented: Binding(
            get: { pictureInPicture.lastFailure != nil },
            set: { if !$0 { pictureInPicture.clearFailure() } }
        )) {
            Button("OK", role: .cancel) { pictureInPicture.clearFailure() }
        } message: {
            Text(pictureInPicture.lastFailure ?? "PiP isn't available for this video.")
        }
        .confirmationDialog(
            pendingTransportChange == .previous ? "Play previous episode?" : "Play next episode?",
            isPresented: Binding(
                get: { pendingTransportChange != nil },
                set: { if !$0 { pendingTransportChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingTransportChange {
                Button("Play \(pendingTransportChange.rawValue) Episode") {
                    switch pendingTransportChange {
                    case .previous: playback.playPrevious()
                    case .next: playback.playNext()
                    }
                    self.pendingTransportChange = nil
                    revealControls()
                }
            }
            Button("Keep Watching", role: .cancel) {
                pendingTransportChange = nil
            }
        } message: {
            Text("This changes the episode. Your current watch progress will be saved.")
        }
    }

    // MARK: - PiP Caption Handoff (Batch 06B)

    private func updateDiscordPresence() {
        guard let episode = session.currentEpisode, webPlayerStream == nil,
              session.currentStream != nil else { return }
        KinetiqDiscordPresenceManager.shared.record(KinetiqPresencePlayback(
            animeTitle: session.animeTitle,
            episodeNumber: episode.number,
            episodeTitle: episode.title,
            language: session.selectedLanguage,
            posterURL: session.animeItem?.imageURL ?? episode.imageURL,
            position: playback.currentTime,
            duration: playback.duration,
            isPlaying: playback.isPlayingForPresence,
            isPictureInPicture: pictureInPicture.isActive
        ))
    }

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

    /// Playback is portrait during startup and landscape only after video
    /// has actually produced its first frame (or opened an approved web embed).
    private func activateLandscapeIfNeeded() {
        guard !hasOrientationLease else { return }
        KinetiqPlaybackPresentation.enterPlayer()
        hasOrientationLease = true
    }

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

    // MARK: - Source-specific Skip / Next Episode overlays (M03/M04)

    private func contextualPlaybackActions(safeAreaInsets: EdgeInsets) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 8) {
                    if let remaining = playback.nextEpisodeCountdown {
                        VStack(alignment: .leading, spacing: 10) {
                            if let next = nextPlayableEpisode {
                                HStack(spacing: 10) {
                                    AsyncImage(url: next.imageURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "film.stack.fill")
                                            .foregroundStyle(.white.opacity(0.62))
                                    }
                                    .frame(width: 43, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("UP NEXT")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .tracking(1.5)
                                            .foregroundStyle(KinetiqPalette.cyan)
                                        Text("Episode \(next.number)")
                                            .font(.subheadline.weight(.bold))
                                        Text(next.title ?? session.animeTitle)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.72))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "timer")
                                Text("Playing next in \(remaining)s")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.83))
                            ProgressView(value: Double(10 - remaining), total: 10)
                                .tint(KinetiqPalette.cyan)
                            HStack(spacing: 9) {
                                Button("Keep Watching") {
                                    playback.cancelNextEpisodeCountdown()
                                    revealControls()
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                Button {
                                    playback.playNext()
                                    revealControls()
                                } label: {
                                    Label("Play Now", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(KinetiqPalette.accent)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: 285, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19))
                        .overlay(RoundedRectangle(cornerRadius: 19)
                            .strokeBorder(KinetiqPalette.cyan.opacity(0.4), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                        .accessibilityElement(children: .contain)
                    } else {
                        if let chapter = currentSkipChapter,
                           dismissedSkipChapterID != chapter.id,
                           let end = chapter.end {
                            HStack(spacing: 8) {
                                Button {
                                    playback.seek(to: end)
                                    showSeekFeedback("\(chapter.kind.rawValue) skipped · Undo Seek available")
                                    revealControls()
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "forward.end.fill")
                                            .font(.subheadline.weight(.heavy))
                                        Text(KinetiqContextualSkipPolicy.label(for: chapter.kind))
                                            .font(.subheadline.weight(.bold))
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(KinetiqPalette.cyan)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 46)
                                }
                                Button {
                                    dismissedSkipChapterID = chapter.id
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Dismiss \(KinetiqContextualSkipPolicy.label(for: chapter.kind))")
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 4)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 1))
                            .shadow(color: .black.opacity(0.42), radius: 10, y: 4)
                        }
                        if canOfferNextEpisode {
                            Button {
                                playback.playNext()
                                revealControls()
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("NEXT EPISODE")
                                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                                            .tracking(1.2)
                                            .foregroundStyle(.white.opacity(0.74))
                                        if let next = nextPlayableEpisode {
                                            Text("Episode \(next.number)")
                                                .font(.subheadline.weight(.bold))
                                        }
                                    }
                                    Image(systemName: "arrow.right")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .background(LinearGradient(colors: [KinetiqPalette.accent,
                                KinetiqPalette.cyan.opacity(0.68)],
                                startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(.white.opacity(0.27), lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                            .accessibilityHint("Opens the next playable episode from this series")
                        }
                    }
                }
            }
        }
        .padding(.trailing, max(18, safeAreaInsets.trailing + 16))
        .padding(.bottom, controlsVisible ? 116 : max(24, safeAreaInsets.bottom + 14))
        .animation(.easeInOut(duration: 0.18), value: currentSkipChapter?.id)
        .animation(.easeInOut(duration: 0.18), value: playback.nextEpisodeCountdown != nil)
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
            durationLabel: displaysRemainingTime && playback.duration > 0
                ? "−" + ModulePlayerPlaybackController.timeString(
                    max(0, playback.duration - displayedTime))
                : playback.formattedDuration,
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
                guard !playback.isResolvingEpisode else { return }
                pendingTransportChange = .previous
                cancelAutoHide()
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
                guard !playback.isResolvingEpisode else { return }
                pendingTransportChange = .next
                cancelAutoHide()
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
        .lockControlsAction {
            controlsLocked = true
            controlsVisible = false
            cancelAutoHide()
        }
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
                subStudio: subStudio,
                onOpenWebPlayer: openWebFallback,
                onLockPlayer: {
                    activePanel = nil
                    controlsLocked = true
                    controlsVisible = false
                    cancelAutoHide()
                },
                onOpenSubtitles: { activePanel = .subtitles }
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
                if session.currentStream == nil, let initialEpisode {
                    playback.dismissError()
                    Task { @MainActor in
                        let didResolve = await session.play(
                            episode: initialEpisode,
                            language: initialLanguage
                        )
                        if didResolve && !Task.isCancelled {
                            onInitialResolution?()
                        }
                    }
                } else {
                    playback.retryCurrentStream()
                }
                revealControls()
            },
            onSkip: {
                if session.currentStream == nil {
                    // No stream was accepted, so there is no native
                    // episode to skip. Return to the episode list.
                    dismiss()
                } else {
                    playback.dismissError()
                    playback.playNext()
                    revealControls()
                }
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

    /// A short hold has no effect. After 0.45s, temporarily play at 2x and
    /// restore the exact previous speed on finger-up. Gesture is opt-in/off
    /// through Settings in the player and cannot run while touch-locked.
    private func handleFastHold(_ pressing: Bool) {
        if pressing {
            guard holdFastPlaybackEnabled, !controlsLocked,
                  activePanel == nil, playback.isPlaying else { return }
            holdFastTask?.cancel()
            holdFastTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(450)) }
                catch { return }
                guard !Task.isCancelled, playback.isPlaying,
                      activePanel == nil, !controlsLocked else { return }
                rateBeforeFastHold = playback.playbackRate
                playback.setRate(2.0)
                showSeekFeedback("2× while holding")
            }
        } else {
            holdFastTask?.cancel()
            holdFastTask = nil
            if let previous = rateBeforeFastHold {
                playback.setRate(previous)
                rateBeforeFastHold = nil
            }
        }
    }

    private func toggleControls() {
        guard !controlsLocked else { return }
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
        guard !controlsLocked else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            controlsVisible = true
        }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        cancelAutoHide()

        guard playback.isPlaying,
              !controlsLocked,
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

/// Isolated from the rest of the player options so frequent playback-presence
/// observations do not invalidate unrelated controls or subtitle settings.
@MainActor
private struct ModuleDiscordResyncControl: View {
    @ObservedObject private var presence = KinetiqDiscordPresenceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                presence.resyncCurrentPlayback()
            } label: {
                Label("Resync current playback", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!presence.enabled || presence.connection != .connected ||
                      presence.lastPreview == nil)
            .accessibilityHint("Requests an updated Discord activity for the current episode while respecting rate limits")

            Text(presence.enabled ? presence.playbackSyncStatus :
                "Enable Discord Presence Lab in Settings to use this control.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
    }
}

/// Mirrors the Library player's glass bottom sheet; every selectable
/// control is connected to the module AVPlayer or module episode session.
enum KinetiqPlayerAction: String, CaseIterable, Identifiable {
    case playPause, previousEpisode, nextEpisode
    case seekBack5, seekForward5, seekBack10, seekForward10
    case seekBack15, seekForward15, seekBack30, seekForward30
    case seekBack60, seekForward60, undoSeek
    case rateSlow, rateStudy, rateNormal, rateFine, rateFast, rateFaster, rateDouble
    case loopStart, loopEnd, loopClear, replayDialogue
    case captionsOff, retryCaptions, muteToggle, volumeDown, volumeUp
    case aspectFit, aspectFill, autoplayToggle
    case sleep15, sleep30, sleep60, sleepCancel
    case retryServer, resetServerHealth, bookmarkScene, copyDiagnostics
    case pauseAfter1, pauseAfter2, pauseAfter3, cancelBinge
    case brain, study, recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Play or pause"
        case .previousEpisode: return "Previous episode"
        case .nextEpisode: return "Next episode"
        case .seekBack5: return "Rewind 5 seconds"
        case .seekForward5: return "Skip forward 5 seconds"
        case .seekBack10: return "Rewind 10 seconds"
        case .seekForward10: return "Skip forward 10 seconds"
        case .seekBack15: return "Rewind 15 seconds"
        case .seekForward15: return "Skip forward 15 seconds"
        case .seekBack30: return "Rewind 30 seconds"
        case .seekForward30: return "Skip forward 30 seconds"
        case .seekBack60: return "Rewind 1 minute"
        case .seekForward60: return "Skip forward 1 minute"
        case .undoSeek: return "Undo last seek"
        case .rateSlow: return "Slow speed · 0.5×"
        case .rateStudy: return "Study speed · 0.75×"
        case .rateNormal: return "Normal speed · 1×"
        case .rateFine: return "Fine speed · 1.25×"
        case .rateFast: return "Fast playback · 1.5×"
        case .rateFaster: return "Faster playback · 1.75×"
        case .rateDouble: return "Double speed · 2×"
        case .loopStart: return "Set A/B loop start"
        case .loopEnd: return "Set A/B loop end"
        case .loopClear: return "Clear A/B loop"
        case .replayDialogue: return "What did they say?"
        case .captionsOff: return "Turn subtitles off"
        case .retryCaptions: return "Retry selected subtitles"
        case .muteToggle: return "Mute or unmute"
        case .volumeDown: return "Lower volume by 10%"
        case .volumeUp: return "Raise volume by 10%"
        case .aspectFit: return "Fit video to screen"
        case .aspectFill: return "Fill screen with video"
        case .autoplayToggle: return "Toggle next-episode autoplay"
        case .sleep15: return "Sleep timer · 15 minutes"
        case .sleep30: return "Sleep timer · 30 minutes"
        case .sleep60: return "Sleep timer · 60 minutes"
        case .sleepCancel: return "Cancel sleep timer"
        case .retryServer: return "Retry current server"
        case .resetServerHealth: return "Reset learned server health"
        case .bookmarkScene: return "Bookmark current scene"
        case .copyDiagnostics: return "Copy safe diagnostics"
        case .pauseAfter1: return "Pause after this episode"
        case .pauseAfter2: return "Pause after 2 episodes"
        case .pauseAfter3: return "Pause after 3 episodes"
        case .cancelBinge: return "Cancel binge pause limit"
        case .brain: return "Open Kinetiq Brain"
        case .study: return "Open Japanese Study Deck"
        case .recovery: return "Open Recovery Center"
        }
    }

    var category: String {
        switch self {
        case .playPause, .previousEpisode, .nextEpisode, .seekBack5,
             .seekForward5, .seekBack10, .seekForward10, .seekBack30,
             .seekForward30, .seekBack15, .seekForward15, .seekBack60,
             .seekForward60, .undoSeek: return "Transport & timeline"
        case .rateSlow, .rateStudy, .rateNormal, .rateFine, .rateFast,
             .rateFaster, .rateDouble, .loopStart, .loopEnd, .loopClear,
             .aspectFit, .aspectFill: return "Playback & repeat"
        case .replayDialogue, .captionsOff, .retryCaptions: return "Subtitles & dialogue"
        case .muteToggle, .volumeDown, .volumeUp: return "Audio"
        case .sleep15, .sleep30, .sleep60, .sleepCancel,
             .pauseAfter1, .pauseAfter2, .pauseAfter3, .cancelBinge,
             .autoplayToggle:
            return "Sleep & Binge Guard"
        case .retryServer, .resetServerHealth, .copyDiagnostics, .recovery:
            return "Recovery & diagnostics"
        case .bookmarkScene, .brain, .study: return "Personal tools"
        }
    }

    var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .previousEpisode, .seekBack5, .seekBack10, .seekBack15,
             .seekBack30, .seekBack60: return "backward.end.fill"
        case .nextEpisode, .seekForward5, .seekForward10, .seekForward15,
             .seekForward30, .seekForward60: return "forward.end.fill"
        case .undoSeek: return "arrow.uturn.backward"
        case .rateSlow, .rateStudy, .rateNormal, .rateFine,
             .rateFast, .rateFaster, .rateDouble: return "speedometer"
        case .loopStart: return "a.circle"
        case .loopEnd: return "b.circle"
        case .loopClear: return "repeat"
        case .replayDialogue: return "text.bubble"
        case .captionsOff, .retryCaptions: return "captions.bubble"
        case .muteToggle: return "speaker.slash"
        case .volumeDown: return "speaker.wave.1"
        case .volumeUp: return "speaker.wave.3"
        case .aspectFit: return "arrow.down.right.and.arrow.up.left"
        case .aspectFill: return "arrow.up.left.and.arrow.down.right"
        case .autoplayToggle: return "play.square.stack"
        case .sleep15, .sleep30, .sleep60, .sleepCancel: return "moon.zzz"
        case .retryServer: return "arrow.clockwise"
        case .resetServerHealth: return "arrow.counterclockwise"
        case .bookmarkScene: return "bookmark"
        case .copyDiagnostics: return "doc.on.doc"
        case .pauseAfter1, .pauseAfter2, .pauseAfter3, .cancelBinge: return "pause.circle"
        case .brain: return "brain.head.profile"
        case .study: return "character.book.closed"
        case .recovery: return "cross.case"
        }
    }
}

@MainActor
private struct ModulePlayerOptionsSheet: View {
    let panel: ModulePlayerPanel
    @ObservedObject var playback: ModulePlayerPlaybackController
    @ObservedObject var session: ModuleEpisodePlaybackSession
    @ObservedObject var subStudio: KinetiqSubStudioController
    @StateObject private var continuity = KinetiqContinuityStore.shared
    @StateObject private var connections = KinetiqMediaConnectionStore.shared
    @StateObject private var serverPreferences = ModuleServerPreferenceStore.shared
    @StateObject private var manualChapters = KinetiqManualChapterStore.shared
    @State private var powerNotice: String?
    @State private var typedTimecode = ""
    @State private var bookmarkNote = ""
    @State private var episodeQuery = ""
    @State private var episodeLanguageScope = "all"
    @State private var stopAtLocalTime = Date().addingTimeInterval(30 * 60)
    @State private var showBrain = false
    @State private var showActionFinder = false
    @ObservedObject private var quickDeck = KinetiqPlayerQuickDeckStore.shared
    @State private var showQuickDeckEditor = false
    @State private var showAdvancedOptions = false
    @State private var actionQuery = ""
    @State private var pendingFinderDestination: KinetiqPlayerAction?
    @State private var showRecoveryCenter = false
    @State private var showStudyDeck = false
    @State private var studySceneAnchor: KinetiqSceneAnchor?
    @AppStorage("kinetiq.player.powerDeck.seekStep.v1") private var quickSeekSeconds = 10
    @AppStorage("kinetiq.player.autoplayNext.v1") private var autoplayNextEpisode = true
    @AppStorage("kinetiq.player.contextualSkipButtons.v1") private var contextualSkipButtonsEnabled = true
    @AppStorage("kinetiq.player.nextEpisodeCountdown.v1") private var nextEpisodeCountdownEnabled = true
    @AppStorage("kinetiq.player.m03.doubleTapSeekSeconds") private var doubleTapSeekSeconds = 10
    @AppStorage("kinetiq.player.m03.remainingClock") private var displaysRemainingTime = false
    @AppStorage("kinetiq.player.m03.holdFastPlayback") private var holdFastPlaybackEnabled = true
    @State private var confirmWrongContentReport = false
    let onOpenWebPlayer: () -> Void
    let onLockPlayer: () -> Void
    let onOpenSubtitles: () -> Void
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
        .confirmationDialog("Report incorrect video?",
            isPresented: $confirmWrongContentReport, titleVisibility: .visible) {
            Button("Mark this server as mismatched and pause") {
                guard let stream = session.currentStream else { return }
                ModuleServerHealthStore.shared.recordFailure(
                    stream, sourceID: session.sourceID, sourceName: session.sourceName)
                if playback.isPlaying { playback.togglePlayback() }
                powerNotice = "This server was marked unreliable on this iPhone. Playback paused; choose another server from Servers. This report does not delete media or change your favorites."
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Kinetiq cannot reliably identify the anime from every CDN video frame. Your report affects local server ranking only; the source's original name remains visible.")
        }
        .sheet(isPresented: $showBrain) {
            NavigationStack { KinetiqBrainView() }
        }
        .sheet(isPresented: $showActionFinder, onDismiss: {
            let target = pendingFinderDestination
            pendingFinderDestination = nil
            switch target {
            case .brain: showBrain = true
            case .study:
                studySceneAnchor = playback.sceneAnchor
                showStudyDeck = true
            case .recovery: showRecoveryCenter = true
            default: break
            }
        }) {
            NavigationStack {
                List {
                    Section {
                        ForEach(KinetiqPlayerAction.allCases.filter { actionQuery.isEmpty ||
                            $0.title.localizedStandardContains(actionQuery) ||
                            $0.category.localizedStandardContains(actionQuery)
                        }) { action in
                            Button {
                                executePlayerAction(action)
                                showActionFinder = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: action.symbol)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(action.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(action.category)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .disabled(!playerActionAvailable(action))
                        }
                    } footer: {
                        Text("Unavailable actions are disabled for this stream. All actions operate on the current player session.")
                    }
                }
                .searchable(text: $actionQuery, prompt: "Search player controls")
                .navigationTitle("Action Finder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showActionFinder = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showRecoveryCenter) {
            NavigationStack { KinetiqRecoveryCenterView() }
        }
        .sheet(isPresented: $showQuickDeckEditor) {
            NavigationStack {
                KinetiqPlayerQuickDeckEditorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showQuickDeckEditor = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showStudyDeck) {
            NavigationStack {
                KinetiqStudyDeckView(
                    initialAnchor: studySceneAnchor,
                    seriesTitle: session.animeTitle,
                    onSeek: { seconds in
                        guard let original = studySceneAnchor,
                              let active = playback.sceneAnchor,
                              active.mediaID == original.mediaID,
                              active.episodeID == original.episodeID,
                              active.language == original.language else { return }
                        playback.seek(to: seconds)
                    }
                )
            }
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
                    Text("Source Flight Control ranks previously successful hosts first. A resolved stream is only a candidate: playback on this exact episode is not verified until video advances. No servers are hidden.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.60))

                    Text("Pin your preferred server for this title and language. Other servers remain available for manual selection and playback recovery.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.60))

                    Toggle("Automatic server fallback", isOn: Binding(
                        get: {
                            serverPreferences.isAutomaticFallbackEnabled(
                                sourceID: session.sourceID, sourceName: session.sourceName,
                                mediaID: session.animeItem?.id ?? session.animeTitle,
                                language: session.selectedLanguage)
                        },
                        set: { enabled in
                            serverPreferences.setAutomaticFallbackEnabled(
                                enabled, sourceID: session.sourceID,
                                sourceName: session.sourceName,
                                mediaID: session.animeItem?.id ?? session.animeTitle,
                                language: session.selectedLanguage)
                        }
                    ))
                    .tint(KinetiqPalette.accent)
                    .foregroundStyle(.white)

                    ForEach(session.availableStreams) { stream in
                        HStack(spacing: 8) {
                            optionRow(
                                title: stream.label,
                                subtitle: "\(stream.hostName) • \(playback.serverHealthStatus(for: stream))",
                                symbol: "server.rack",
                                selected: session.currentStream?.id == stream.id
                            ) {
                                playback.selectServer(stream)
                                onClose()
                            }

                            let pinned = serverPreferences.isPinned(
                                stream, sourceID: session.sourceID,
                                sourceName: session.sourceName,
                                mediaID: session.animeItem?.id ?? session.animeTitle,
                                language: session.selectedLanguage
                            )
                            Button {
                                serverPreferences.setPinned(
                                    pinned ? nil : stream,
                                    sourceID: session.sourceID,
                                    sourceName: session.sourceName,
                                    mediaID: session.animeItem?.id ?? session.animeTitle,
                                    language: session.selectedLanguage
                                )
                            } label: {
                                Image(systemName: pinned ? "pin.fill" : "pin")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(pinned ? KinetiqPalette.accent : .white.opacity(0.7))
                                    .frame(width: 42, height: 42)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(pinned ? "Unpin \(stream.label)" : "Pin \(stream.label) for this title")
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

                sectionLabel("ONE-TAP VIEWING PRESETS")
                HStack(spacing: 8) {
                    Button {
                        playback.setRate(0.75)
                        quickSeekSeconds = 5
                        powerNotice = "Study preset: 0.75× with 5-second Quick Deck seeks."
                    } label: {
                        Label("Study", systemImage: "character.book.closed")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button {
                        playback.setRate(1.0)
                        playback.isAspectFill = false
                        quickSeekSeconds = 10
                        powerNotice = "Cinema preset: 1×, aspect fit and 10-second Quick Deck seeks."
                    } label: {
                        Label("Cinema", systemImage: "film")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(playback.player.currentItem == nil)

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

                sectionLabel("NATIVE PIP SUBTITLES · BETA")
                if playback.isPreparingNativeBridge {
                    ProgressView("Preparing native subtitle track…")
                        .tint(KinetiqPalette.accent)
                } else if playback.nativeBridgeIsActive {
                    Label("Temporary native HLS rendition active", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KinetiqPalette.cyan)
                    Button("Return to Original Stream") {
                        playback.disableNativePiPBridge()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        playback.activateNativePiPBridge()
                    } label: {
                        Label("Try Native PiP Subtitles", systemImage: "pip.enter")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KinetiqPalette.accent)
                    .disabled(!playback.canPrepareNativePiPBridge)
                }
                Text(playback.nativeBridgeStatus)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            KinetiqSubStudioControls(
                studio: subStudio,
                primaryTrackID: playback.externalSubtitles.selectedTrackID,
                currentTime: playback.currentTime,
                onSeek: { playback.seek(to: $0) }
            )
            .padding(.top, 8)

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
                sectionLabel("SMART CONTROLS · ALWAYS RELEVANT")
                HStack(spacing: 9) {
                    Button(action: onLockPlayer) {
                        Label("Lock Now", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button(action: onOpenSubtitles) {
                        Label("SubStudio", systemImage: "captions.bubble.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(KinetiqPalette.cyan)

                if playback.errorMessage != nil || playback.isBuffering {
                    optionRow(
                        title: "Try recovering playback",
                        subtitle: "This stream is interrupted; retry without leaving the player",
                        symbol: "arrow.clockwise", selected: false
                    ) {
                        playback.retryCurrentStream()
                        powerNotice = "Attempting to recover the current stream."
                    }
                } else if playback.currentTime > 10 {
                    optionRow(
                        title: "What did they say?",
                        subtitle: "Replay the recent dialogue and temporarily show captions",
                        symbol: "text.bubble", selected: false
                    ) { executePlayerAction(.replayDialogue) }
                }

                if !session.upcomingEpisodes.isEmpty,
                   playback.duration > 30,
                   playback.duration - playback.currentTime < 65 {
                    optionRow(
                        title: "Episode almost finished",
                        subtitle: "The regular Next Episode button is available near the end",
                        symbol: "forward.end", selected: false
                    ) { playback.playNext() }
                }

                HStack {
                    sectionLabel("YOUR QUICK DECK")
                    Spacer()
                    Button("Customize", systemImage: "slider.horizontal.3") {
                        showQuickDeckEditor = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KinetiqPalette.cyan)
                }
                if quickDeck.pinned.isEmpty {
                    Text("No controls pinned yet. Customize to choose up to eight shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        ForEach(quickDeck.pinned) { action in
                            Button {
                                switch action {
                                case .brain: showBrain = true
                                case .study:
                                    studySceneAnchor = playback.sceneAnchor
                                    showStudyDeck = true
                                case .recovery: showRecoveryCenter = true
                                default: executePlayerAction(action)
                                }
                            } label: {
                                Label(action.title, systemImage: action.symbol)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(!playerActionAvailable(action))
                        }
                    }
                }

                optionRow(
                    title: "Find a player action",
                    subtitle: "Search all player actions instead of scrolling through them",
                    symbol: "magnifyingglass.circle", selected: false
                ) { showActionFinder = true }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvancedOptions.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(showAdvancedOptions ? "Hide Advanced Tools" : "Show Advanced Tools")
                        Spacer()
                        Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if showAdvancedOptions {
                powerDeck

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("RECOVERY & JAPANESE STUDY")
                optionRow(
                    title: "Wrong anime or episode playing?",
                    subtitle: "Pause and mark the currently selected server unreliable on this iPhone; no automatic cross-title switching",
                    symbol: "exclamationmark.bubble", selected: false
                ) { confirmWrongContentReport = true }
                .disabled(session.currentStream == nil)

                optionRow(
                    title: "Recovery Center",
                    subtitle: "Inspect categorized player failures, suggested actions and sanitized history",
                    symbol: "cross.case", selected: false
                ) { showRecoveryCenter = true }

                if session.currentStream != nil {
                    optionRow(
                        title: "Retry this server now",
                        subtitle: "Manually restart this episode stream without changing the source or watched progress",
                        symbol: "arrow.clockwise", selected: false
                    ) {
                        playback.retryCurrentStream()
                        powerNotice = "A manual retry was requested."
                    }
                }

                optionRow(
                    title: "Japanese Study Deck",
                    subtitle: "Write scene-linked vocabulary cards, review them offline and export a CSV",
                    symbol: "character.book.closed", selected: false
                ) {
                    studySceneAnchor = playback.sceneAnchor
                    showStudyDeck = true
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("PLAYER COMFORT · M03")
                optionRow(
                    title: "Lock touch controls",
                    subtitle: "Prevents accidental seeks, episode changes and taps. A clearly visible Unlock button stays available.",
                    symbol: "lock.fill", selected: false
                ) { onLockPlayer() }
                Toggle("Show time remaining on timeline", isOn: $displaysRemainingTime)
                    .tint(KinetiqPalette.cyan)
                    .foregroundStyle(.white)
                Toggle("Hold video for temporary 2× speed", isOn: $holdFastPlaybackEnabled)
                    .tint(KinetiqPalette.cyan)
                    .foregroundStyle(.white)
                Text("Double-tap seek interval")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 7) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { seconds in
                        Button("\(seconds)s") { doubleTapSeekSeconds = seconds }
                            .buttonStyle(.bordered)
                            .tint(doubleTapSeekSeconds == seconds ? KinetiqPalette.cyan : .gray)
                    }
                }
                Text("Gestures are inactive when controls are locked; player buttons stay available after unlocking.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))

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

                HStack(spacing: 10) {
                    DatePicker("Stop at local time", selection: $stopAtLocalTime,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .font(.caption)
                    Button("Set") {
                        let clock = Calendar.current.dateComponents([.hour, .minute], from: stopAtLocalTime)
                        guard let next = Calendar.current.nextDate(after: Date(),
                                matching: clock, matchingPolicy: .nextTime) else { return }
                        let minutes = max(1, Int(ceil(next.timeIntervalSinceNow / 60)))
                        playback.setSleepTimer(minutes)
                        powerNotice = "Playback will pause near the next selected local time."
                    }
                    .buttonStyle(.bordered)
                }
                Text("The absolute-time option schedules the next occurrence on this device, even if it falls tomorrow. The timer is session-only and cancels when the player closes.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("BINGE GUARD · AUTOPLAY")
                Toggle("Autoplay the next episode", isOn: $autoplayNextEpisode)
                    .tint(KinetiqPalette.cyan)
                    .foregroundStyle(.white)
                    .onChange(of: autoplayNextEpisode) { _, enabled in
                        if !enabled {
                            playback.setPauseAfterEpisodes(nil)
                            playback.cancelNextEpisodeCountdown()
                        }
                    }
                Toggle("Show contextual Skip Intro / Recap / Credits", isOn: $contextualSkipButtonsEnabled)
                    .tint(KinetiqPalette.cyan)
                    .foregroundStyle(.white)
                Toggle("Show 10-second Next Episode countdown", isOn: $nextEpisodeCountdownEnabled)
                    .tint(KinetiqPalette.cyan)
                    .foregroundStyle(.white)
                Text("Skip buttons require your completed markers for the exact module and episode. No intros or credits are guessed. The countdown runs only when autoplay and Binge Guard allow it.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
                HStack(spacing: 8) {
                    ForEach([1, 2, 3], id: \.self) { count in
                        Button("Pause after \(count)") {
                            autoplayNextEpisode = true
                            playback.setPauseAfterEpisodes(count)
                        }
                        .buttonStyle(.bordered)
                        .tint(playback.episodesUntilPause == count ? KinetiqPalette.cyan : .gray)
                    }
                }
                if let remaining = playback.episodesUntilPause {
                    HStack {
                        Text("Kinetiq will pause after \(remaining) completed episode(s), counting the current one.")
                            .font(.caption).foregroundStyle(.white.opacity(0.72))
                        Spacer(minLength: 4)
                        Button("Cancel") { playback.setPauseAfterEpisodes(nil) }
                            .font(.caption.weight(.semibold))
                    }
                } else {
                    Text("A pause limit is temporary for this player session. Turning off autoplay stops after the current episode.")
                        .font(.caption).foregroundStyle(.white.opacity(0.58))
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                    .padding(.vertical, 3)

                sectionLabel("DISCORD PRESENCE")
                ModuleDiscordResyncControl()

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
    }

    private var continuitySuggestion: KinetiqContinuitySuggestion? {
        guard let source = session.sourceID,
              let anime = session.animeItem,
              let episode = session.currentEpisode else { return nil }
        let id = String(source.utf8.count) + ":" + source + anime.id
        return continuity.suggestion(for: id, episodeNumber: episode.number,
            language: session.selectedLanguage, duration: playback.duration,
            confirmedLinks: connections.connectedIDs(to: id))
    }

    private func playerActionAvailable(_ action: KinetiqPlayerAction) -> Bool {
        switch action {
        case .previousEpisode:
            guard let current = session.currentEpisode,
                  let index = session.episodes.firstIndex(where: { $0.id == current.id })
            else { return false }
            return index > 0
        case .nextEpisode: return !session.upcomingEpisodes.isEmpty
        case .playPause, .muteToggle: return playback.player.currentItem != nil
        case .seekBack5, .seekForward5, .seekBack10, .seekForward10,
             .seekBack15, .seekForward15, .seekBack30, .seekForward30,
             .seekBack60, .seekForward60, .loopStart:
            return playback.duration > 0
        case .undoSeek: return playback.lastSeekPosition != nil
        case .loopEnd: return playback.loopStart != nil
        case .loopClear: return playback.loopStart != nil
        case .replayDialogue: return playback.canUseTemporaryCaptions
        case .retryCaptions:
            return playback.externalSubtitles.selectedTrackID != nil
        case .captionsOff:
            return playback.player.currentItem != nil && !playback.requiresEmbeddedSubtitle
        case .retryServer: return session.currentStream != nil
        case .bookmarkScene: return playback.sceneAnchor != nil
        case .sleepCancel: return playback.sleepTimerMinutes != nil
        case .cancelBinge: return playback.episodesUntilPause != nil
        case .pauseAfter1, .pauseAfter2, .pauseAfter3:
            return session.currentEpisode != nil
        case .rateSlow, .rateStudy, .rateNormal, .rateFine,
             .rateFast, .rateFaster, .rateDouble, .volumeDown,
             .volumeUp, .aspectFit, .aspectFill,
             .sleep15, .sleep30, .sleep60:
            return playback.player.currentItem != nil
        case .autoplayToggle: return true
        case .resetServerHealth, .copyDiagnostics, .brain, .study, .recovery:
            return true
        }
    }

    private func executePlayerAction(_ action: KinetiqPlayerAction) {
        switch action {
        case .playPause: playback.togglePlayback()
        case .previousEpisode: playback.playPrevious()
        case .nextEpisode: playback.playNext()
        case .seekBack5: playback.seek(by: -5)
        case .seekForward5: playback.seek(by: 5)
        case .seekBack10: playback.seek(by: -10)
        case .seekForward10: playback.seek(by: 10)
        case .seekBack15: playback.seek(by: -15)
        case .seekForward15: playback.seek(by: 15)
        case .seekBack30: playback.seek(by: -30)
        case .seekForward30: playback.seek(by: 30)
        case .seekBack60: playback.seek(by: -60)
        case .seekForward60: playback.seek(by: 60)
        case .undoSeek: playback.undoLastSeek()
        case .rateSlow: playback.setRate(0.5)
        case .rateStudy: playback.setRate(0.75)
        case .rateNormal: playback.setRate(1.0)
        case .rateFine: playback.setRate(1.25)
        case .rateFast: playback.setRate(1.5)
        case .rateFaster: playback.setRate(1.75)
        case .rateDouble: playback.setRate(2.0)
        case .loopStart: playback.markLoopStart()
        case .loopEnd: playback.markLoopEnd()
        case .loopClear: playback.clearLoop()
        case .replayDialogue: playback.rewindWithTemporaryCaptions()
        case .captionsOff: playback.selectSubtitle(nil)
        case .retryCaptions: playback.externalSubtitles.retry()
        case .muteToggle: playback.player.isMuted.toggle()
        case .volumeDown: playback.player.volume = max(0, playback.player.volume - 0.1)
        case .volumeUp: playback.player.volume = min(1, playback.player.volume + 0.1)
        case .aspectFit: playback.isAspectFill = false
        case .aspectFill: playback.isAspectFill = true
        case .autoplayToggle:
            autoplayNextEpisode.toggle()
            if !autoplayNextEpisode {
                playback.setPauseAfterEpisodes(nil)
                playback.cancelNextEpisodeCountdown()
            }
            powerNotice = autoplayNextEpisode ? "Next-episode autoplay enabled." : "Next-episode autoplay disabled."
        case .sleep15: playback.setSleepTimer(15)
        case .sleep30: playback.setSleepTimer(30)
        case .sleep60: playback.setSleepTimer(60)
        case .sleepCancel: playback.setSleepTimer(nil)
        case .retryServer: playback.retryCurrentStream()
        case .resetServerHealth: playback.resetServerHealth()
        case .bookmarkScene:
            if let anchor = playback.sceneAnchor {
                continuity.bookmark(anchor)
                powerNotice = "Scene saved in your private bookmarks."
            }
        case .copyDiagnostics:
            UIPasteboard.general.string = playback.diagnosticSummary
            powerNotice = "Sanitized player diagnostics copied."
        case .pauseAfter1, .pauseAfter2, .pauseAfter3:
            autoplayNextEpisode = true
            let count: Int
            switch action {
            case .pauseAfter1: count = 1
            case .pauseAfter2: count = 2
            default: count = 3
            }
            playback.setPauseAfterEpisodes(count)
        case .cancelBinge: playback.setPauseAfterEpisodes(nil)
        case .brain, .study, .recovery:
            pendingFinderDestination = action
        }
    }

    @ViewBuilder
    private var powerDeck: some View {
        sectionLabel("POWER DECK · TIMELINE")

        Text("Quick seek step")
            .font(.caption).foregroundStyle(.white.opacity(0.65))
        HStack(spacing: 5) {
            ForEach([5, 10, 15, 30, 60], id: \.self) { step in
                Button("\(step)s") { quickSeekSeconds = step }
                    .buttonStyle(.bordered)
                    .tint(quickSeekSeconds == step ? KinetiqPalette.cyan : .gray)
            }
        }

        HStack(spacing: 8) {
            Button { playback.seek(by: -Double(quickSeekSeconds)) } label: {
                Label("−\(quickSeekSeconds)s", systemImage: "backward.end")
            }
            Button { playback.seek(by: Double(quickSeekSeconds)) } label: {
                Label("+\(quickSeekSeconds)s", systemImage: "forward.end")
            }
            Button { playback.undoLastSeek() } label: {
                Label("Undo seek", systemImage: "arrow.uturn.backward")
            }
            .disabled(playback.lastSeekPosition == nil)
        }
        .buttonStyle(.bordered)
        .disabled(playback.duration <= 0)

        HStack(spacing: 8) {
            TextField("Jump to mm:ss or hh:mm:ss", text: $typedTimecode)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityLabel("Exact playback timestamp")
            Button("Go", systemImage: "arrow.right.circle.fill") {
                guard let seconds = KinetiqTimecodeParser.seconds(from: typedTimecode),
                      seconds <= playback.duration else {
                    powerNotice = "Invalid timecode or timestamp beyond this episode. Try 12:34 or 01:12:34."
                    return
                }
                playback.seek(to: seconds)
                typedTimecode = ""
                powerNotice = "Jumped to \(ModulePlayerPlaybackController.timeString(seconds))."
            }
            .buttonStyle(.borderedProminent)
            .disabled(playback.duration <= 0 || typedTimecode.isEmpty)
        }

        sectionLabel("QUICK PLAYBACK PROFILES")
        HStack(spacing: 8) {
            Button("Study · 0.75×", systemImage: "text.book.closed") {
                playback.setRate(0.75)
                powerNotice = "Study playback speed set. Captions remain independently selectable."
            }
            Button("Cinema · 1×", systemImage: "film") {
                playback.setRate(1.0)
                playback.clearLoop()
                powerNotice = "Normal speed restored and A/B loop cleared."
            }
        }
        .buttonStyle(.bordered)

        optionRow(title: "Ask Kinetiq Brain",
                  subtitle: "Open grounded library/search tools or opt-in on-device AI; current episode details are not uploaded",
                  symbol: "brain.head.profile", selected: false) {
            showBrain = true
        }

        optionRow(title: "What did they say?",
                  subtitle: "Rewind 10 seconds and show temporary captions when possible",
                  symbol: "text.bubble", selected: false) {
            playback.rewindWithTemporaryCaptions()
        }
        .disabled(!playback.canUseTemporaryCaptions)

        HStack(spacing: 8) {
            Button("A/B Start", systemImage: "a.circle") { playback.markLoopStart() }
            Button("A/B End", systemImage: "b.circle") { playback.markLoopEnd() }
            Button("Clear Loop", systemImage: "xmark.circle") { playback.clearLoop() }
        }
        .buttonStyle(.bordered)
        .disabled(playback.duration <= 0)

        if let start = playback.loopStart {
            Text("Loop: \(Int(start))s → \(playback.loopEnd.map { "\(Int($0))s" } ?? "set end")")
                .font(.caption).foregroundStyle(.white.opacity(0.72))
        }

        Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
        manualChapterTools

        sectionLabel("SCENE PASSPORT · PRIVATE MEMORY")
        TextField("Optional bookmark note", text: $bookmarkNote)
            .textFieldStyle(.roundedBorder)
            .onChange(of: bookmarkNote) { _, updated in
                if updated.count > 240 { bookmarkNote = String(updated.prefix(240)) }
            }
        optionRow(title: "Bookmark this scene",
                  subtitle: "Save this timecode and optional note on your device; no screenshot or URL captured",
                  symbol: "bookmark", selected: false) {
            if let anchor = playback.sceneAnchor {
                continuity.bookmark(anchor, note: bookmarkNote.trimmingCharacters(in: .whitespacesAndNewlines))
                bookmarkNote = ""
                powerNotice = "Scene saved in Settings → Scene Memory."
            }
        }
        .disabled(playback.sceneAnchor == nil)

        if let activeAnchor = playback.sceneAnchor {
            let saved = continuity.bookmarks.filter {
                $0.anchor.mediaID == activeAnchor.mediaID &&
                $0.anchor.episodeID == activeAnchor.episodeID &&
                $0.anchor.language == activeAnchor.language
            }.prefix(8)
            if !saved.isEmpty {
                Text("Saved moments in this edition")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                ForEach(Array(saved)) { bookmark in
                    HStack(spacing: 8) {
                        Button {
                            playback.seek(to: bookmark.anchor.seconds)
                            powerNotice = "Returned to saved scene."
                        } label: {
                            Label("\(ModulePlayerPlaybackController.timeString(bookmark.anchor.seconds)) · \(bookmark.note.isEmpty ? "Scene" : bookmark.note)", systemImage: "bookmark.fill")
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) { continuity.removeBookmark(bookmark.id) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove scene bookmark")
                        .buttonStyle(.borderless)
                    }
                }
            }
        }

        if let suggestion = continuitySuggestion {
            optionRow(title: "Resume from \(suggestion.anchor.sourceName)",
                      subtitle: "\(Int(suggestion.mappedSeconds))s · \(Int(suggestion.confidence * 100))% confidence · \(suggestion.explanation)",
                      symbol: "arrow.triangle.branch", selected: false) {
                playback.seek(to: suggestion.mappedSeconds)
                powerNotice = "Applied approximate Source Passport handoff. Adjust manually if the cut differs."
            }
        } else {
            Text("Cross-source resume appears only after you confirm the series in Source Passport and a matching episode, language and runtime are verified. Never jumps to an unverified cut.")
                .font(.caption).foregroundStyle(.white.opacity(0.60))
        }

        if let anchor = playback.sceneAnchor {
            ShareLink(item: "Watch \(session.animeTitle), episode \(anchor.episodeNumber) at \(ModulePlayerPlaybackController.timeString(anchor.seconds)) in your own authorized source. Shared by Kinetiq. No media link included.") {
                Label("Share spoiler-safe watch timecode", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            Text("This shares a timecode invitation, not synchronized live playback or media files.")
                .font(.caption2).foregroundStyle(.white.opacity(0.58))
        }
        if let powerNotice {
            Text(powerNotice).font(.caption).foregroundStyle(KinetiqPalette.cyan)
        }
    }

    // MARK: Episode List

    private var currentChapterKey: (media: String, episode: String,
                                    stream: String, duration: Double)? {
        guard let episode = session.currentEpisode,
              let stream = session.currentStream,
              playback.duration.isFinite, playback.duration > 0 else { return nil }
        let module = session.sourceID ?? session.sourceName
        let item = session.animeItem?.id ?? session.animeTitle
        return ("\(module.count):\(module)|\(item)", episode.id,
            KinetiqChapterStreamIdentity.key(host: stream.hostName,
                                              label: stream.label, type: stream.streamType),
            playback.duration)
    }

    @ViewBuilder
    private var manualChapterTools: some View {
        sectionLabel("MANUAL OPENING / RECAP / CREDITS · PRIVATE")
        Text("Confirm the real start and end on this server. A floating Skip button appears only for the matching provider, episode, server and video duration. Old M03 markers remain saved but should be re-marked to verify the server. Undo Seek reverses a skip.")
            .font(.caption).foregroundStyle(.white.opacity(0.64))
        if let key = currentChapterKey {
            ForEach(KinetiqManualChapterKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.rawValue).font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    if let chapter = manualChapters.chapter(
                        mediaKey: key.media, episodeKey: key.episode, kind: kind,
                        streamKey: key.stream) {
                        Text("Start: \(ModulePlayerPlaybackController.timeString(chapter.start)) · End: \(chapter.end.map { ModulePlayerPlaybackController.timeString($0) } ?? "Not set")")
                            .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                    HStack(spacing: 8) {
                        Button("Mark Start") {
                            manualChapters.markStart(mediaKey: key.media,
                                episodeKey: key.episode, kind: kind, seconds: playback.currentTime,
                                streamKey: key.stream, expectedDuration: key.duration)
                            powerNotice = "\(kind.rawValue) start saved for this exact episode."
                        }
                        Button("Mark End") {
                            if !manualChapters.markEnd(mediaKey: key.media,
                                episodeKey: key.episode, kind: kind, seconds: playback.currentTime,
                                streamKey: key.stream) {
                                powerNotice = "Set a start before the current time. Markers must span at least one second."
                            } else {
                                powerNotice = "\(kind.rawValue) range saved for this episode."
                            }
                        }
                        if let chapter = manualChapters.chapter(
                            mediaKey: key.media, episodeKey: key.episode, kind: kind,
                            streamKey: key.stream),
                           KinetiqContextualSkipPolicy.matchesVerifiedEdition(
                                chapter, streamKey: key.stream, duration: key.duration),
                           let end = chapter.end {
                            Button("Skip") {
                                playback.seek(to: end)
                                powerNotice = "Skipped \(kind.rawValue). Undo Seek returns to the previous position."
                            }
                            Button(role: .destructive) { manualChapters.delete(chapter) } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Remove \(kind.rawValue) marker")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(playback.duration <= 0)
                }
                .padding(11)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            Text("Start playing an episode before adding scene markers.")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var visibleEpisodeList: [ModuleAnimeEpisode] {
        let search = episodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.episodes.filter { episode in
            let matchesLanguage: Bool
            switch episodeLanguageScope {
            case "sub": matchesLanguage = episode.subAvailable
            case "dub": matchesLanguage = episode.dubAvailable
            default: matchesLanguage = true
            }
            return matchesLanguage && (search.isEmpty ||
                episode.number.localizedCaseInsensitiveContains(search) ||
                (episode.title?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private var episodeList: some View {
        VStack(spacing: 9) {
            TextField("Find episode number or title", text: $episodeQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            Picker("Language", selection: $episodeLanguageScope) {
                Text("All").tag("all")
                Text("Sub").tag("sub")
                Text("Dub").tag("dub")
            }
            .pickerStyle(.segmented)
            Text("\(visibleEpisodeList.count) of \(session.episodes.count) episodes · Provider order retained")
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
            if visibleEpisodeList.isEmpty {
                Text("No episodes match this search. Clear the query or change the language filter.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            ForEach(visibleEpisodeList) { episode in
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

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Episode \(episode.number)")
                                .font(.system(size: 13, weight: .semibold))
                            if let title = episode.title, !title.isEmpty {
                                Text(title)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(2)
                            }
                        }
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

/// One consistent decision for autoplay and a session-scoped binge limit.
/// Never counts server retries or manual seeks as additional episodes.
enum KinetiqBingeGuardPolicy {
    static func completedEpisode(remaining: Int?, autoplay: Bool)
        -> (advance: Bool, remaining: Int?) {
        guard autoplay else { return (false, nil) }
        guard let remaining else { return (true, nil) }
        if remaining <= 1 { return (false, nil) }
        return (true, remaining - 1)
    }
}

@MainActor
private final class ModulePlayerPlaybackController: ObservableObject {

    let externalSubtitles = ModuleExternalSubtitleController()
    private var subtitleChanges: AnyCancellable?
    @Published private(set) var captionChoice: KinetiqCaptionChoice = .settings
    @Published private(set) var isPreparingNativeBridge = false
    @Published private(set) var nativeBridgeStatus =
        "For on-demand HLS only. Builds a temporary native WebVTT rendition; original playback remains the fallback."
    private var nativeBridge: NativeHLSSubtitleBridge?
    private var nativeBridgeTask: Task<Void, Never>?
    var nativeBridgeIsActive: Bool { nativeBridge != nil }
    var canPrepareNativePiPBridge: Bool {
        guard let stream = session.currentStream else { return false }
        return !isPreparingNativeBridge &&
            NativeHLSSubtitleBridge.isEligible(stream) &&
            externalSubtitles.tracks.contains(where: { $0.id == externalSubtitles.selectedTrackID })
    }

    func activateNativePiPBridge() {
        guard canPrepareNativePiPBridge,
              let stream = session.currentStream,
              let selectedID = externalSubtitles.selectedTrackID,
              let track = externalSubtitles.tracks.first(where: { $0.id == selectedID })
        else { return }
        nativeBridgeTask?.cancel()
        isPreparingNativeBridge = true
        nativeBridgeStatus = "Validating on-demand HLS and preparing a synchronized WebVTT track…"
        let offset = KinetiqSubtitleSettings.shared.sourceTimingOffset
        nativeBridgeTask = Task { @MainActor [weak self] in
            defer {
                self?.isPreparingNativeBridge = false
                self?.nativeBridgeTask = nil
            }
            do {
                let bridge = try await NativeHLSSubtitleBridge.prepare(
                    stream: stream, track: track, offset: offset
                )
                guard !Task.isCancelled, let self, !self.hasStopped,
                      self.session.currentStream?.id == stream.id,
                      self.externalSubtitles.selectedTrackID == selectedID else { return }
                self.nativeBridgeStatus = "Opening the native subtitle presentation…"
                self.load(stream, bridge: bridge)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.nativeBridgeStatus =
                    (error as? LocalizedError)?.errorDescription ??
                    "Native subtitle preparation failed. Original playback is unchanged."
            }
        }
    }

    func disableNativePiPBridge() {
        nativeBridgeTask?.cancel()
        nativeBridgeTask = nil
        isPreparingNativeBridge = false
        guard nativeBridge != nil, let stream = session.currentStream else { return }
        nativeBridgeStatus = "Returned to the original source stream."
        load(stream)
    }

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
        if nativeBridge != nil {
            return "Native HLS bridge enabled. System PiP should use its selectable WebVTT track if iOS accepts it; confirm on-device before relying on this beta."
        }
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
        if case .embedded(let choice) = captionChoice,
           let item = player.currentItem,
           item === subtitleOptionsItem,
           let subtitleGroup,
           let selected = subtitleOptions.first(where: { KinetiqCaptionLanguage($0) == choice }) {
            player.appliesMediaSelectionCriteriaAutomatically = false
            item.select(selected, in: subtitleGroup)
            selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
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
    /// Rich Presence must not report a pause during a +10s seek or buffering.
    /// The player's explicit play/pause intent remains independent from its
    /// transient AVPlayer time-control status and the actual player UI.
    var isPlayingForPresence: Bool {
        !hasStopped && player.currentItem != nil &&
            KinetiqPresencePlaybackIntent.isPlaying(
                requestedPlayback: wantsToPlay,
                hasStartedCurrentItem: startedCurrentItem,
                playerReportsPlaying: isPlaying
            )
    }
    @Published private(set) var isBuffering = true
    @Published private(set) var hasFinishedPresentingFirstFrame = false
    private var sawFirstVideoFrame = false
    private var startupOverlayTask: Task<Void, Never>?
    @Published private(set) var isResolvingEpisode = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var nextEpisodeCountdown: Int?

    @Published var scrubPosition: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var isAspectFill = false

    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published private(set) var selectedAudio: AVMediaSelectionOption?
    @Published private(set) var selectedSubtitle: AVMediaSelectionOption?
    @Published private(set) var sleepTimerMinutes: Int?
    @Published private(set) var episodesUntilPause: Int?
    @Published private(set) var loopStart: Double?
    @Published private(set) var loopEnd: Double?
    @Published private(set) var lastSeekPosition: Double?
    @Published private(set) var resolutionText = "Analyzing…"
    @Published private(set) var playbackStatus = "Preparing stream"
    @Published private(set) var lastHTTPStatus: Int?
    @Published private(set) var diagnosticEvents: [String] = []

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var sleepTask: Task<Void, Never>?
    private var nextEpisodeTask: Task<Void, Never>?
    private var temporaryCaptionsTask: Task<Void, Never>?

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
    /// AVPlayer's asynchronous seek may not finish before another +10s tap.
    /// Keep the requested destination separate from the last observed frame.
    private weak var pendingSeekItem: AVPlayerItem?
    private var pendingSeekTarget: Double?
    private var seekRevision = 0
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
    private var completedItemID: ObjectIdentifier?
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
                    KinetiqRecoveryStore.shared.record(
                        phase: .resolution, outcome: .failed,
                        code: "MODULE_RESOLUTION_FAILED",
                        source: self.session.sourceName,
                        episode: self.session.currentEpisode?.number ?? "Unknown"
                    )
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

                if !self.isRestoringPosition, let start = self.loopStart,
                   let end = self.loopEnd, end > start + 0.5,
                   seconds >= end, seconds < end + 1.5 {
                    self.seek(to: start)
                }

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
            do { try await Task.sleep(for: .milliseconds(250)) }
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

    private func load(_ stream: ModuleResolvedStream, bridge: NativeHLSSubtitleBridge? = nil) {
        guard !hasStopped,
              lastStreamID != stream.id || bridge != nil || nativeBridge != nil else {
            return
        }
        cancelNextEpisodeCountdown()
        pendingSeekTarget = nil
        pendingSeekItem = nil
        seekRevision += 1
        completedItemID = nil
        if bridge == nil {
            nativeBridgeTask?.cancel()
            nativeBridgeTask = nil
            isPreparingNativeBridge = false
        }
        nativeBridge = bridge

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
        if previousEpisodeID != session.currentEpisode?.id {
            clearLoop()
            lastSeekPosition = nil
            temporaryCaptionsTask?.cancel()
        }

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
        if bridge != nil {
            externalSubtitles.suspendForNativeBridge()
        }

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
            url: bridge?.playbackURL ?? stream.url,
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

                let completedID = ObjectIdentifier(item)
                guard self.completedItemID != completedID else { return }
                self.completedItemID = completedID
                self.savePlaybackProgress(force: true, finished: true)
                self.player.pause()
                self.wantsToPlay = false
                guard self.shouldAdvanceAfterEpisode() else {
                    self.playbackStatus = "Episode finished · Autoplay off or Binge Guard paused"
                    return
                }
                self.beginNextEpisodeCountdown(for: item)
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

        // An experimental localhost rendition must never count as a
        // provider/server failure. Restore the proven original playback.
        if nativeBridge != nil {
            nativeBridgeStatus = "Native PiP presentation failed; restored original video and external subtitles."
            note("Native subtitle rendition failed; reverting without penalizing the source")
            load(stream)
            return
        }

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
        KinetiqRecoveryStore.shared.record(
            phase: .playback, outcome: .failed, code: failureCode,
            source: session.sourceName,
            episode: session.currentEpisode?.number ?? "Unknown",
            httpStatus: lastHTTPStatus
        )

        // Exactly one automatic retry per server. If the server rejects
        // authorization, move directly to a different available server.
        let authorizationRejected = lastHTTPStatus == 401 || lastHTTPStatus == 403
        if !authorizationRejected,
           automaticRetriedIDs.insert(stream.id).inserted {
            playbackStatus = "Retrying \(stream.label)"
            note("Automatic retry: \(stream.label)")
            KinetiqRecoveryStore.shared.record(
                phase: .playback, outcome: .retrying,
                code: "AUTOMATIC_SERVER_RETRY", source: session.sourceName,
                episode: session.currentEpisode?.number ?? "Unknown",
                httpStatus: lastHTTPStatus
            )
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

        guard ModuleServerPreferenceStore.shared.isAutomaticFallbackEnabled(
            sourceID: session.sourceID, sourceName: session.sourceName,
            mediaID: session.animeItem?.id ?? session.animeTitle,
            language: session.selectedLanguage
        ) else {
            playbackStatus = "Playback failed"
            errorMessage = "Automatic server fallback is disabled for this title. Open Servers to choose another host or retry manually."
            note("Automatic server fallback disabled by the user")
            return
        }
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
            KinetiqRecoveryStore.shared.record(
                phase: .playback, outcome: .switching,
                code: "SERVER_FALLBACK", source: session.sourceName,
                episode: session.currentEpisode?.number ?? "Unknown",
                httpStatus: lastHTTPStatus
            )
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
        // Late HLS renditions: retry native legible group after ready.
        let audio: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        var subtitles: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        if subtitles?.options.isEmpty != false {
            for delay in [420, 900] {
                do { try await Task.sleep(for: .milliseconds(delay)) }
                catch { return }
                guard !Task.isCancelled, player.currentItem === item else { return }
                let retry: AVMediaSelectionGroup? = try? await item.asset.loadMediaSelectionGroup(for: .legible)
                if let retry, !retry.options.isEmpty { subtitles = retry; break }
            }
        }
        guard !Task.isCancelled, player.currentItem === item else { return }
        audioGroup = audio
        subtitleGroup = subtitles
        audioOptions = audio?.options ?? []
        subtitleOptions = subtitles?.options ?? []
        selectedAudio = audio.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
        subtitleOptionsItem = item
        if !subtitleOptions.isEmpty { note("Native subtitle tracks: \(subtitleOptions.count)") }
        if nativeBridge != nil {
            guard let group = subtitles,
                  let native = group.options.first(where: {
                      $0.displayName.contains(NativeHLSSubtitleManifest.trackName)
                  }) else {
                nativeBridgeStatus = "The native caption track was not exposed by iOS; restored the original stream."
                if let stream = session.currentStream { load(stream) }
                return
            }
            player.appliesMediaSelectionCriteriaAutomatically = false
            item.select(native, in: group)
            selectedSubtitle = native
            captionChoice = .source
            externalSubtitles.suspendForNativeBridge()
            nativeBridgeStatus = "Native caption track selected. Start PiP to check iOS subtitle rendering."
            note("Native HLS subtitle option selected for PiP validation")
            return
        }
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
        if nativeBridge != nil {
            nativeBridgeStatus = "Switched subtitle source; returned to original video."
            externalSubtitles.select(track)
            if let stream = session.currentStream { load(stream) }
            // The original item's track loader will restore this newly saved
            // preference. Do not select on the soon-to-be-replaced item.
            return
        }
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
        if nativeBridge != nil {
            guard let group = subtitleGroup,
                  let native = subtitleOptions.first(where: {
                      $0.displayName.contains(NativeHLSSubtitleManifest.trackName)
                  }) else { return }
            player.appliesMediaSelectionCriteriaAutomatically = false
            if captionChoice == .off {
                item.select(nil, in: group)
                selectedSubtitle = nil
            } else {
                item.select(native, in: group)
                selectedSubtitle = native
                externalSubtitles.suspendForNativeBridge()
            }
            return
        }
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

    var sceneAnchor: KinetiqSceneAnchor? {
        guard let source = session.sourceID, let anime = session.animeItem,
              let episode = session.currentEpisode,
              duration.isFinite && duration > 5, currentTime.isFinite,
              currentTime >= 0 else { return nil }
        let mediaID = String(source.utf8.count) + ":" + source + anime.id
        return KinetiqSceneAnchor(mediaID: mediaID, sourceName: session.sourceName,
            episodeID: episode.id, episodeNumber: episode.number,
            language: session.selectedLanguage,
            seconds: min(currentTime, duration), duration: duration)
    }

    var canUseTemporaryCaptions: Bool {
        !subtitleOptions.isEmpty && player.currentItem != nil && duration > 0
    }

    func rewindWithTemporaryCaptions() {
        guard canUseTemporaryCaptions else { return }
        temporaryCaptionsTask?.cancel()
        let previous = selectedSubtitle
        let temporary = previous ?? subtitleOptions[0]
        if previous == nil { selectSubtitle(temporary) }
        seek(by: -10)
        temporaryCaptionsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.selectedSubtitle == temporary,
                  previous == nil else { return }
            self.selectSubtitle(nil)
        }
    }

    func markLoopStart() {
        guard duration > 0 else { return }
        loopStart = min(max(currentTime, 0), duration)
        loopEnd = nil
    }

    func markLoopEnd() {
        guard let start = loopStart, currentTime > start + 0.5,
              currentTime <= duration else { return }
        loopEnd = currentTime
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
    }

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
        let base = pendingSeekItem === player.currentItem
            ? (pendingSeekTarget ?? currentTime) : currentTime
        seek(to: base + seconds)
    }

    func undoLastSeek() {
        guard let previous = lastSeekPosition else { return }
        lastSeekPosition = nil
        seek(to: previous)
        lastSeekPosition = nil
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0,
              let item = player.currentItem else { return }

        let target = min(max(seconds, 0), duration)
        let previous = pendingSeekItem === item
            ? (pendingSeekTarget ?? currentTime) : currentTime
        if previous.isFinite && abs(previous - target) > 0.5 {
            lastSeekPosition = previous
        }
        let time = CMTime(seconds: target, preferredTimescale: 600)
        pendingSeekItem = item
        pendingSeekTarget = target
        seekRevision += 1
        let revision = seekRevision

        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item,
                      self.seekRevision == revision else { return }
                self.pendingSeekTarget = nil
                self.pendingSeekItem = nil
                guard finished else { return }
                let actual = self.player.currentTime().seconds
                if actual.isFinite, actual >= 0 {
                    self.currentTime = actual
                    if !self.isScrubbing { self.scrubPosition = actual }
                }
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
        cancelNextEpisodeCountdown()
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
        cancelNextEpisodeCountdown()
        Task {
            await session.playNext()

            if let message = session.playbackError,
               !message.isEmpty {
                errorMessage = message
            }
        }
    }

    func playPrevious() {
        cancelNextEpisodeCountdown()
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
        KinetiqRecoveryStore.shared.record(
            phase: .playback, outcome: .retrying,
            code: "MANUAL_SERVER_RETRY", source: session.sourceName,
            episode: session.currentEpisode?.number ?? "Unknown"
        )
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
                self.wantsToPlay = false
                self.player.pause()
                self.sleepTimerMinutes = nil
            } catch {
                // The timer was cancelled or changed.
            }
        }
    }

    func setPauseAfterEpisodes(_ count: Int?) {
        guard let count, (1...20).contains(count) else {
            episodesUntilPause = nil
            return
        }
        episodesUntilPause = count
    }

    /// Runs only after AVPlayer confirms that this exact video item finished.
    /// Never advances during a source retry, a long seek, PiP transition, or
    /// while a different episode is resolving. Cancel is session-only.
    private func beginNextEpisodeCountdown(for item: AVPlayerItem) {
        cancelNextEpisodeCountdown()
        let hasNext = session.upcomingEpisodes.contains { episode in
            session.supports("sub", for: episode) || session.supports("dub", for: episode)
        }
        guard hasNext else {
            playbackStatus = "Episode finished · No next playable episode"
            return
        }
        let key = "kinetiq.player.nextEpisodeCountdown.v1"
        let enabled = UserDefaults.standard.object(forKey: key) == nil
            ? true : UserDefaults.standard.bool(forKey: key)
        // There is no visible countdown UI in background audio/PiP. Continue
        // normally rather than scheduling an invisible cancelable prompt.
        guard enabled, UIApplication.shared.applicationState == .active else {
            playNext()
            return
        }
        let finishedEpisodeID = session.currentEpisode?.id
        let finishedEpisodeIndex = session.currentEpisodeIndex
        nextEpisodeCountdown = 10
        playbackStatus = "Episode finished · Next episode in 10 seconds"
        nextEpisodeTask = Task { @MainActor [weak self, weak item] in
            for remaining in stride(from: 9, through: 0, by: -1) {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled, let self, let item,
                      !self.hasStopped, self.player.currentItem === item,
                      self.session.currentEpisode?.id == finishedEpisodeID,
                      self.session.currentEpisodeIndex == finishedEpisodeIndex,
                      !self.session.isResolving else { return }
                if remaining > 0 {
                    self.nextEpisodeCountdown = remaining
                    self.playbackStatus = "Episode finished · Next episode in \(remaining) seconds"
                } else {
                    self.nextEpisodeCountdown = nil
                    self.nextEpisodeTask = nil
                    self.playNext()
                }
            }
        }
    }

    func cancelNextEpisodeCountdown() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
        if player.currentItem != nil, !hasStopped,
           player.currentTime().seconds >= duration - 1 {
            playbackStatus = "Next episode cancelled · Replay or choose Next to continue"
        }
    }

    private func shouldAdvanceAfterEpisode() -> Bool {
        let key = "kinetiq.player.autoplayNext.v1"
        let autoplay = UserDefaults.standard.object(forKey: key) == nil
            ? true : UserDefaults.standard.bool(forKey: key)
        let decision = KinetiqBingeGuardPolicy.completedEpisode(
            remaining: episodesUntilPause, autoplay: autoplay
        )
        episodesUntilPause = decision.remaining
        return decision.advance
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
        let mediaID = String(sourceID.utf8.count) + ":" + sourceID + anime.id
        KinetiqContinuityStore.shared.record(KinetiqSceneAnchor(
            mediaID: mediaID, sourceName: session.sourceName,
            episodeID: episode.id, episodeNumber: episode.number,
            language: lastLoadedLanguage, seconds: min(position, length),
            duration: length))
        lastSavedProgressAt = now
    }

    func stop() {
        guard !hasStopped else { return }
        cancelNextEpisodeCountdown()
        pendingSeekTarget = nil
        pendingSeekItem = nil
        seekRevision += 1
        savePlaybackProgress(force: true)
        hasStopped = true

        nativeBridgeTask?.cancel()
        nativeBridgeTask = nil
        nativeBridge = nil

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
        temporaryCaptionsTask?.cancel()
        temporaryCaptionsTask = nil
        clearLoop()
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
enum KinetiqModuleNativeCaptionStyle {
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
            case .extraLarge: target = 9.0
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
    @State private var expandedConsole = false

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

    // When the module player first appears, its video view ignores the safe
    // area but the iPhone clock and Dynamic Island are still visible.
    // Measure the actual window inset, not a hard-coded device model.
    private var windowSafeInsets: UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.safeAreaInsets
            ?? windows.first?.safeAreaInsets
            ?? .zero
    }

    private func safeLoadingTop(_ geometry: GeometryProxy) -> CGFloat {
        let inset = max(geometry.safeAreaInsets.top, windowSafeInsets.top)
        let safe = inset > 0 ? inset :
            (UIDevice.current.userInterfaceIdiom == .phone ? 59 : 24)
        return safe + 18
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
                                Text(theme == .cinema ? "PREPARING YOUR SCREENING" :
                                     theme == .anime ? "YOUR NEXT EPISODE AWAITS" :
                                     theme == .aurora ? "PREPARING YOUR EXPERIENCE" :
                                     theme == .nocturne ? "FOCUSING ON YOUR STORY" :
                                     "GETTING YOUR STREAM READY")
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
                .padding(.top, safeLoadingTop(geometry))
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, windowSafeInsets.bottom))
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
