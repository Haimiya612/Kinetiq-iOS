import SwiftUI

enum KinetiqSpoilerDepth: Int, CaseIterable, Identifiable {
    case off = 0
    case unwatched = 1
    case strict = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .unwatched: "Unwatched"
        case .strict: "Strict"
        }
    }

    var explanation: String {
        switch self {
        case .off:
            "Show episode artwork, titles and summaries normally."
        case .unwatched:
            "Hide episode artwork, titles and summaries until that episode is watched or temporarily revealed."
        case .strict:
            "Hide metadata for every episode, including watched ones. Also protect About, Trailers and Related until explicitly revealed."
        }
    }
}

enum KinetiqSpoilerShieldPolicy {
    static let storageKey = "kinetiq.discovery.spoilerShield.depth.v1"

    static func shouldHideEpisode(
        watched: Bool,
        depth: KinetiqSpoilerDepth,
        revealed: Bool
    ) -> Bool {
        guard !revealed else { return false }
        switch depth {
        case .off: return false
        case .unwatched: return !watched
        case .strict: return true
        }
    }

    static func shouldProtectExtraSection(
        depth: KinetiqSpoilerDepth,
        explicitlyRevealed: Bool
    ) -> Bool {
        depth == .strict && !explicitlyRevealed
    }
}

struct KinetiqSpoilerShieldSettingsView: View {
    @AppStorage(KinetiqSpoilerShieldPolicy.storageKey) private var depthRaw = 0

    private var depth: KinetiqSpoilerDepth {
        KinetiqSpoilerDepth(rawValue: depthRaw) ?? .off
    }

    var body: some View {
        Form {
            Section("Episode spoiler protection") {
                Picker("Protection level", selection: $depthRaw) {
                    ForEach(KinetiqSpoilerDepth.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(depth.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("How it works") {
                Label("Episode numbers, play and download controls stay visible.", systemImage: "play.circle")
                Label("Hidden cards cannot accidentally expose future episode stills.", systemImage: "eye.slash")
                Label("Reveal a single card for this visit when you choose.", systemImage: "hand.tap")
                Label("Watching an episode updates its protection in Unwatched mode.", systemImage: "checkmark.circle")
            }
            .font(.subheadline)

            Section {
                Text("Spoiler Shield uses the existing module watch history on this device. It does not infer what you have seen on other platforms, filter content on external websites, or modify your Discord presence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spoiler Shield")
    }
}
