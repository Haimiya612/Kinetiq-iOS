import SwiftUI
import AVFoundation
import UIKit

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
struct KinetiqApp: App {
    @UIApplicationDelegateAdaptor(KinetiqPlaybackAppDelegate.self)
    private var playbackAppDelegate

    @StateObject private var taglineStore: LaunchTaglineStore
    @StateObject private var whatsNewStore = WhatsNewStore()

    @AppStorage(AppStorageKey.appearance)
    private var appearanceRawValue = AppAppearance.system.rawValue

    @State private var showingWhatsNew = false
    @State private var checkedForUpdates = false

    init() {
        _taglineStore = StateObject(wrappedValue: LaunchTaglineStore())
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(tagline: taglineStore.tagline)
                .preferredColorScheme(
                    AppAppearance(rawValue: appearanceRawValue)?.colorScheme
                )
                .task {
                    guard !checkedForUpdates else { return }
                    checkedForUpdates = true

                    await whatsNewStore.load()

                    guard
                        !Task.isCancelled,
                        whatsNewStore.hasUnseenReleases
                    else {
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(450))

                    guard !Task.isCancelled else { return }
                    showingWhatsNew = true
                }
                .sheet(
                    isPresented: $showingWhatsNew,
                    onDismiss: {
                        whatsNewStore.markLatestAsSeen()
                    }
                ) {
                    WhatsNewView(
                        releases: whatsNewStore.unseenReleases
                    )
                }
        }
    }
}
