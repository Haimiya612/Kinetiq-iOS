import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence is an optional *on-device* assistant. Kinetiq's own
/// grounded inventory and public catalog searches remain usable without it.
/// Never put media filenames, source credentials or watch history into this
/// model's instructions. The user explicitly selects conversational mode.
@MainActor
final class KinetiqNativeBrain: ObservableObject {
    static let shared = KinetiqNativeBrain()

    // The stored session is intentionally type-erased so iOS 17 installations
    // never need to instantiate a framework introduced in iOS 26.
    private var retainedSession: AnyObject?

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    var availabilityDescription: String {
        isAvailable
            ? "Apple Intelligence is available on this device. Conversation stays on device."
            : "The system language model is unavailable on this device, iOS version, or Apple Intelligence configuration. Grounded local tools and AniList search still work."
    }

    func resetConversation() {
        retainedSession = nil
    }

    /// A retained LanguageModelSession provides multi-turn context. It sees only
    /// the message typed into conversational mode, never a generated dump of
    /// the user's private library or source/module configuration.
    func respond(to question: String) async -> String? {
        guard !Task.isCancelled, isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session: LanguageModelSession
                if let existing = retainedSession as? LanguageModelSession {
                    session = existing
                } else {
                    session = LanguageModelSession(instructions: "You are Kinetiq Brain, a concise and honest entertainment companion. Discuss titles, viewing habits, technical video concepts and recommendations. You do not have access to the user's files, private watch history, streaming sources, or current web. Do not invent playable links, specific availability, watched episode counts or citations. If asked for device-specific data, tell them to switch to Kinetiq's grounded inventory tools. Do not spoil plot events unless requested.")
                    retainedSession = session
                }
                let response = try await session.respond(to: String(question.prefix(240)))
                guard !Task.isCancelled else { return nil }
                return String(response.content.prefix(5_000))
            } catch {
                // Context windows can fill up. A reset is recoverable and does
                // not lose any grounded watch or download records.
                retainedSession = nil
                return nil
            }
        }
        #endif
        return nil
    }
}
