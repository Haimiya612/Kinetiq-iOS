import SwiftUI
import AVFoundation
import UIKit
import Foundation
import CryptoKit
import UserNotifications

/// App-owned orientation decision. Each full-screen player takes one lease.
/// iOS 16+ scene geometry requests rotate the full UI instead of faking the
/// landscape look with a rotated SwiftUI view.
@MainActor
enum KinetiqPlaybackPresentation {
    private(set) static var orientationMask: UIInterfaceOrientationMask = .portrait
    private static var playerLeases = 0

    static func enterPlayer() {
        playerLeases += 1
        activatePlaybackAudioSession()
        if playerLeases == 1 {
            orientationMask = .landscape
            request(.landscapeRight)
        }
    }

    static func leavePlayer() {
        playerLeases = max(0, playerLeases - 1)
        if playerLeases == 0 {
            orientationMask = .portrait
            request(.portrait)
        }
    }

    static func preparePlayer(_ player: AVPlayer) {
        activatePlaybackAudioSession()
        if #available(iOS 26.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
    }

    static func activatePlaybackAudioSession() {
        // Playback, not ambient audio: required for PiP and for continuing
        // media audio when the app transitions to the background.
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .moviePlayback)
            try audio.setActive(true)
        } catch {
            #if DEBUG
            print("Kinetiq audio session configuration: \(error.localizedDescription)")
            #endif
        }
    }

    private static func request(_ orientation: UIInterfaceOrientationMask) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard scene.activationState == .foregroundActive ||
                  scene.activationState == .foregroundInactive else { continue }
            scene.windows.forEach {
                $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)
            ) { error in
                #if DEBUG
                print("Kinetiq orientation request: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

@MainActor
final class KinetiqPlaybackAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = KinetiqOfflineDownloadStore.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        KinetiqOfflineDownloadStore.shared.handleBackgroundEvents(
            identifier: identifier, completion: completionHandler
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let data = response.notification.request.content.userInfo
        Task { @MainActor in
            KinetiqEpisodeAlerts.receiveResponse(userInfo: data)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let info = content.userInfo
        Task { @MainActor in
            if let route = KinetiqEpisodeAlerts.route(from: info), !route.animeTitle.isEmpty {
                // Show the familiar in-app banner with the episode artwork
                // and search action, avoiding a duplicate native banner.
                KinetiqNoticeCenter.shared.post(
                    .information, title: content.title,
                    message: [content.subtitle, content.body]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    groupKey: notification.request.identifier,
                    artworkURL: info["artworkURL"] as? String,
                    animeTitle: route.animeTitle
                )
                completionHandler([])
            } else {
                completionHandler([.banner, .sound])
            }
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        KinetiqPlaybackPresentation.orientationMask
    }
}

@main
@MainActor
struct KinetiqApp: App {
    @UIApplicationDelegateAdaptor(KinetiqPlaybackAppDelegate.self)
    private var playbackAppDelegate

    @StateObject private var taglineStore: LaunchTaglineStore
    @StateObject private var whatsNewStore = WhatsNewStore()
    @StateObject private var moduleUpdates: KinetiqModuleUpdateCenterStore

    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var visualThemeRawValue = KinetiqVisualTheme.signature.rawValue

    @State private var showingWhatsNew = false
    @State private var showingModuleUpdates = false
    @State private var checkedForUpdates = false

    init() {
        // Must run before ModulePackageStore.shared reads its installed index.
        // Recovery never modifies favorites, downloads or history.
        KinetiqModuleRollbackVault.restorePendingOnLaunch()
        _taglineStore = StateObject(wrappedValue: LaunchTaglineStore())
        _moduleUpdates = StateObject(wrappedValue: KinetiqModuleUpdateCenterStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(tagline: taglineStore.tagline)
                // A separate pass-through foreground window keeps notices
                // above fullscreen players and sheets instead of behind them.
                .background(KinetiqForegroundNoticeInstaller()
                    .frame(width: 0, height: 0))
                .preferredColorScheme(
                    visualThemeRawValue == KinetiqVisualTheme.signature.rawValue
                        ? AppAppearance(rawValue: appearanceRawValue)?.colorScheme
                        : .dark
                )
                .task {
                    guard !checkedForUpdates else { return }
                    checkedForUpdates = true
                    await whatsNewStore.load()
                    guard !Task.isCancelled else { return }
                    if whatsNewStore.hasUnseenReleases {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        showingWhatsNew = true
                    } else {
                        await checkModuleUpdates()
                    }
                }
                .sheet(
                    isPresented: $showingWhatsNew,
                    onDismiss: {
                        whatsNewStore.markLatestAsSeen()
                        Task { await checkModuleUpdates() }
                    }
                ) {
                    WhatsNewView(releases: whatsNewStore.unseenReleases)
                }
                .fullScreenCover(isPresented: $showingModuleUpdates) {
                    KinetiqModuleUpdateCenterView()
                }
        }
    }

    @MainActor
    private func checkModuleUpdates() async {
        guard !showingWhatsNew, !showingModuleUpdates else { return }
        let shouldPresent = await moduleUpdates.checkForUpdatesOnLaunch()
        guard !Task.isCancelled, shouldPresent else { return }
        showingModuleUpdates = true
    }
}

// MARK: - M04 foreground notice presentation

/// Never creates a second notice center. This is one visual host for the
/// existing deduplicated queue, rendered above the app's modal layers.
@MainActor
private struct KinetiqForegroundNoticeInstaller: UIViewRepresentable {
    final class AnchorView: UIView {
        var sceneDidChange: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            sceneDidChange?(window?.windowScene)
        }
    }

    @MainActor
    final class Coordinator {
        private var noticeWindow: KinetiqPassThroughNoticeWindow?

        func updateScene(_ scene: UIWindowScene?) {
            guard let scene else {
                noticeWindow?.isHidden = true
                noticeWindow = nil
                return
            }
            if noticeWindow?.windowScene === scene { return }
            noticeWindow?.isHidden = true
            let window = KinetiqPassThroughNoticeWindow(windowScene: scene)
            window.windowLevel = .normal + 5
            window.backgroundColor = .clear
            let host = UIHostingController(rootView:
                KinetiqNoticeBannerHost()
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .top)
                    .background(Color.clear)
            )
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            noticeWindow = window
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let anchor = AnchorView(frame: .zero)
        anchor.isUserInteractionEnabled = false
        anchor.sceneDidChange = { [weak coordinator = context.coordinator] scene in
            coordinator?.updateScene(scene)
        }
        return anchor
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        if let scene = uiView.window?.windowScene {
            context.coordinator.updateScene(scene)
        }
    }
}

/// Transparent portions of the foreground window must not block video taps,
/// menus or gestures underneath the notice. A presented history sheet remains
/// fully interactive until dismissed.
@MainActor
private final class KinetiqPassThroughNoticeWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard KinetiqNoticeCenter.shared.current != nil else { return nil }
        if rootViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        let bannerWidth = min(bounds.width - 30, 560)
        let isWithinBanner = point.y <= safeAreaInsets.top + 150 &&
            abs(point.x - bounds.midX) <= bannerWidth / 2 + 4
        return isWithinBanner ? super.hitTest(point, with: event) : nil
    }
}

// MARK: - Batch 05P-D: Native, nonblocking app notifications
// Kept in an existing compile-target source file. No project.pbxproj changes.

/// Routine feedback only. Permission decisions, publisher trust and playback
/// diagnostics deliberately continue using their own explicit interfaces.
enum KinetiqNoticeLevel: String, Codable {
    case success, information, warning, failure

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .information: KinetiqPalette.accent
        case .warning: .orange
        case .failure: .red
        }
    }

    var displaySeconds: UInt64 {
        switch self {
        case .success: 3
        case .information: 4
        case .warning, .failure: 6
        }
    }
}

struct KinetiqNotice: Codable, Identifiable, Equatable {
    let id: UUID
    let level: KinetiqNoticeLevel
    let title: String
    var message: String
    var details: String?
    let groupKey: String
    var date: Date
    var occurrences: Int
    // Optional to preserve decoding of existing on-device notice history.
    var artworkURL: String? = nil
    var animeTitle: String? = nil
}

/// Protect history and copy actions from persisting source URLs, query tokens,
/// response headers and other secrets which may appear in third-party errors.
enum KinetiqNoticeRedaction {
    static func safe(_ input: String, maximumLength: Int = 1200) -> String {
        var value = input.replacingOccurrences(
            of: #"(?i)\b(?:https?|wss?)://[^\s\]\)<>\"']+"#,
            with: "[URL redacted]", options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\b(?:authorization|set-cookie|cookie|api[_-]?key|access[_-]?token|secret)\s*[:=]\s*[^\r\n;]+"#,
            with: "[credential redacted]", options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\b(?:token|signature|sig|key|password)\s*[:=]\s*[^\s&;,]+"#,
            with: "[credential redacted]", options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+"#,
            with: "[credential redacted]", options: .regularExpression
        )
        value = value.replacingOccurrences(of: #"[\u0000-\u0008\u000B\u000E-\u001F]"#,
                                          with: " ", options: .regularExpression)
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(max(0, maximumLength)))
    }
}

@MainActor
final class KinetiqNoticeCenter: ObservableObject {
    static let shared = KinetiqNoticeCenter()

    @Published private(set) var current: KinetiqNotice?
    @Published private(set) var history: [KinetiqNotice] = []

    private let defaults: UserDefaults
    private let schedulesAutoDismiss: Bool
    private let storageKey = "kinetiq.notifications.history.05PD.v1"
    private var waiting: [KinetiqNotice] = []
    private var dismissTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private let maximumHistory = 150
    private let maximumPending = 8

    init(defaults: UserDefaults = .standard, schedulesAutoDismiss: Bool = true) {
        self.defaults = defaults
        self.schedulesAutoDismiss = schedulesAutoDismiss
        if let saved = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([KinetiqNotice].self, from: saved) {
            history = Array(decoded.prefix(maximumHistory))
        }
    }

    var pendingCount: Int { waiting.count }

    /// Posting is intentionally fire-and-forget. Failure notifications never
    /// block a module batch or require an alert's OK button.
    func post(_ level: KinetiqNoticeLevel, title: String, message: String,
              groupKey: String, details: String? = nil,
              artworkURL: String? = nil, animeTitle: String? = nil) {
        let safeTitle = KinetiqNoticeRedaction.safe(title, maximumLength: 90)
        let safeMessage = KinetiqNoticeRedaction.safe(message, maximumLength: 220)
        let safeDetails = details.map { KinetiqNoticeRedaction.safe($0) }
        // Keep only plain public HTTPS artwork links (no credentials/queries).
        let safeArtwork: String? = artworkURL.flatMap { raw in
            guard let url = URL(string: raw), url.scheme == "https",
                  url.user == nil, url.password == nil, url.query == nil,
                  url.fragment == nil else { return nil }
            return url.absoluteString
        }
        let safeAnimeTitle = animeTitle.map {
            KinetiqNoticeRedaction.safe($0, maximumLength: 110)
        }
        // Source identifiers can contain a repository URL with query secrets.
        // Store only its opaque digest, never the original URL/key in history.
        let safeGroupKey = groupKey.isEmpty ? "" : SHA256.hash(data: Data(groupKey.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let date = Date()

        // Suppress repeated failures from one broken source (e.g. DramaFun),
        // but retain a counter and the latest message in notification history.
        if !safeGroupKey.isEmpty,
           let index = history.firstIndex(where: {
               $0.groupKey == safeGroupKey && $0.level == level &&
               date.timeIntervalSince($0.date) < 15
           }) {
            var duplicate = history.remove(at: index)
            duplicate.date = date
            duplicate.message = safeMessage
            duplicate.details = safeDetails
            duplicate.artworkURL = safeArtwork
            duplicate.animeTitle = safeAnimeTitle
            duplicate.occurrences += 1
            history.insert(duplicate, at: 0)
            if current?.id == duplicate.id { current = duplicate }
            // A duplicate in the pending queue must remain one banner,
            // with the newest text and an incremented history counter.
            if let waitingIndex = waiting.firstIndex(where: { $0.id == duplicate.id }) {
                waiting[waitingIndex] = duplicate
            }
            persist()
            return
        }

        var notice = KinetiqNotice(id: UUID(), level: level,
            title: safeTitle, message: safeMessage, details: safeDetails,
            groupKey: safeGroupKey, date: date, occurrences: 1)
        notice.artworkURL = safeArtwork
        notice.animeTitle = safeAnimeTitle
        history.insert(notice, at: 0)
        if history.count > maximumHistory { history.removeLast(history.count - maximumHistory) }
        persist()

        if waiting.count >= maximumPending { waiting.removeFirst() }
        waiting.append(notice)
        presentNextIfNeeded()
    }

    func dismissCurrent() {
        guard current != nil else { return }
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(210))
            guard !Task.isCancelled else { return }
            self?.presentNextIfNeeded()
        }
    }

    func remove(_ record: KinetiqNotice) {
        history.removeAll { $0.id == record.id }
        waiting.removeAll { $0.id == record.id }
        if current?.id == record.id { dismissCurrent() }
        persist()
    }

    func clearHistory() {
        history.removeAll()
        waiting.removeAll()
        if current != nil { dismissCurrent() }
        persist()
    }

    private func presentNextIfNeeded() {
        guard current == nil, !waiting.isEmpty else { return }
        let notice = waiting.removeFirst()
        current = notice
        guard schedulesAutoDismiss else { return }
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: notice.level.displaySeconds * 1_000_000_000) }
            catch { return }
            guard !Task.isCancelled, self?.current?.id == notice.id else { return }
            self?.dismissCurrent()
        }
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(history) else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}

struct KinetiqNoticeBannerHost: View {
    @ObservedObject private var center = KinetiqNoticeCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingHistory = false

    var body: some View {
        ZStack(alignment: .top) {
            if let current = center.current {
                banner(current)
                    .id(current.id)
                    .transition(reduceMotion ? .opacity :
                        .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) :
            .spring(response: 0.43, dampingFraction: 0.84),
            value: center.current?.id)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 15)
        .padding(.top, 7)
        .allowsHitTesting(center.current != nil)
        .sheet(isPresented: $showingHistory) {
            NavigationStack { KinetiqNoticeHistoryView() }
        }
    }

    private func banner(_ notice: KinetiqNotice) -> some View {
        HStack(spacing: 12) {
            if notice.animeTitle != nil {
                KinetiqNoticeArtworkView(notice: notice, width: 48, height: 62)
            } else {
                Image(systemName: notice.level.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(notice.level.color)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(notice.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if notice.occurrences > 1 {
                        Text("×\(notice.occurrences)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 3)
            Button { center.dismissCurrent() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 29, height: 29)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.15), radius: 17, x: 0, y: 8)
        .frame(maxWidth: 560)
        .contentShape(RoundedRectangle(cornerRadius: 19))
        .onTapGesture {
            if let animeTitle = notice.animeTitle, !animeTitle.isEmpty {
                KinetiqEpisodeAlerts.openAnime(animeTitle)
                center.dismissCurrent()
            } else {
                showingHistory = true
            }
        }
        .gesture(DragGesture(minimumDistance: 18).onEnded { gesture in
            if gesture.translation.height < -18 { center.dismissCurrent() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.title). \(notice.message)")
        .accessibilityHint(notice.animeTitle == nil
                           ? "Tap to open notification history, or swipe up to dismiss"
                           : "Tap to find this anime across all sources, or swipe up to dismiss")
    }
}

private struct KinetiqNoticeArtworkView: View {
    let notice: KinetiqNotice
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let raw = notice.artworkURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                fallback
                    .frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: notice.animeTitle == nil ? notice.level.symbol : "play.rectangle.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(notice.level.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(notice.level.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

struct KinetiqNoticeHistoryView: View {
    @ObservedObject private var center = KinetiqNoticeCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false

    var body: some View {
        List {
            if center.history.isEmpty {
                ContentUnavailableView("No Notifications", systemImage: "bell.slash",
                    description: Text("Installation, update and general app messages will appear here."))
            } else {
                ForEach(center.history) { notice in
                    HStack(alignment: .top, spacing: 12) {
                        if notice.animeTitle != nil {
                            KinetiqNoticeArtworkView(notice: notice, width: 46, height: 60)
                        } else {
                            Image(systemName: notice.level.symbol)
                                .foregroundStyle(notice.level.color)
                                .frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(notice.title).font(.subheadline.weight(.semibold))
                                if notice.occurrences > 1 {
                                    Text("×\(notice.occurrences)").font(.caption2)
                                }
                            }
                            Text(notice.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(notice.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let animeTitle = notice.animeTitle, !animeTitle.isEmpty {
                                Button {
                                    dismiss()
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        KinetiqEpisodeAlerts.openAnime(animeTitle)
                                    }
                                } label: {
                                    Label("Find anime in all sources", systemImage: "magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                            }
                            if let details = notice.details, !details.isEmpty {
                                Button {
                                    UIPasteboard.general.string = details
                                } label: {
                                    Label("Copy Details", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                    .swipeActions {
                        Button(role: .destructive) { center.remove(notice) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !center.history.isEmpty {
                    Button("Clear") { confirmingClear = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Clear notification history?", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { center.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clearing notifications does not delete modules or playback data.")
        }
    }
}
