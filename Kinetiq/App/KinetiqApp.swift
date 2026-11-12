import SwiftUI
import AVFoundation
import UIKit
import Foundation
import CryptoKit

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
final class KinetiqPlaybackAppDelegate: UIResponder, UIApplicationDelegate {
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
                .overlay(alignment: .top) { KinetiqNoticeBannerHost() }
                .preferredColorScheme(
                    AppAppearance(rawValue: appearanceRawValue)?.colorScheme
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
              groupKey: String, details: String? = nil) {
        let safeTitle = KinetiqNoticeRedaction.safe(title, maximumLength: 90)
        let safeMessage = KinetiqNoticeRedaction.safe(message, maximumLength: 220)
        let safeDetails = details.map { KinetiqNoticeRedaction.safe($0) }
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
            duplicate.occurrences += 1
            history.insert(duplicate, at: 0)
            if current?.id == duplicate.id { current = duplicate }
            persist()
            return
        }

        let notice = KinetiqNotice(id: UUID(), level: level,
            title: safeTitle, message: safeMessage, details: safeDetails,
            groupKey: safeGroupKey, date: date, occurrences: 1)
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
            Image(systemName: notice.level.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(notice.level.color)
                .frame(width: 28)
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
        .onTapGesture { showingHistory = true }
        .gesture(DragGesture(minimumDistance: 18).onEnded { gesture in
            if gesture.translation.height < -18 { center.dismissCurrent() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.title). \(notice.message)")
        .accessibilityHint("Tap to open notification history, or swipe up to dismiss")
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
                        Image(systemName: notice.level.symbol)
                            .foregroundStyle(notice.level.color)
                            .frame(width: 24)
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