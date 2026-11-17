import Combine
import Foundation
import SwiftUI

/// The pinned deck holds action identifiers, never closures or player instances.
/// This makes it independent of module/source changes and safe across launches.
enum KinetiqQuickDeckPolicy {
    static let maximumPins = 8
    static let storageKey = "kinetiq.player.quickDeck.pins.v1"
    static let defaults: [KinetiqPlayerAction] = [
        .playPause, .seekBack10, .seekForward10,
        .rateNormal, .bookmarkScene, .replayDialogue
    ]

    static func normalized(_ rawValues: [String]) -> [KinetiqPlayerAction] {
        var encountered = Set<String>()
        return Array(rawValues.compactMap { raw -> KinetiqPlayerAction? in
            guard encountered.insert(raw).inserted else { return nil }
            return KinetiqPlayerAction(rawValue: raw)
        }.prefix(maximumPins))
    }
}

@MainActor
final class KinetiqPlayerQuickDeckStore: ObservableObject {
    static let shared = KinetiqPlayerQuickDeckStore()

    @Published private(set) var pinned: [KinetiqPlayerAction]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: KinetiqQuickDeckPolicy.storageKey) {
            pinned = KinetiqQuickDeckPolicy.normalized(saved)
        } else {
            pinned = KinetiqQuickDeckPolicy.defaults
        }
    }

    func isPinned(_ action: KinetiqPlayerAction) -> Bool {
        pinned.contains(action)
    }

    @discardableResult
    func add(_ action: KinetiqPlayerAction) -> Bool {
        guard !pinned.contains(action), pinned.count < KinetiqQuickDeckPolicy.maximumPins else {
            return false
        }
        pinned.append(action)
        save()
        return true
    }

    func remove(_ action: KinetiqPlayerAction) {
        pinned.removeAll { $0 == action }
        save()
    }

    func move(_ action: KinetiqPlayerAction, direction: Int) {
        guard direction == -1 || direction == 1,
              let index = pinned.firstIndex(of: action),
              pinned.indices.contains(index + direction) else { return }
        pinned.swapAt(index, index + direction)
        save()
    }

    func restoreDefaults() {
        pinned = KinetiqQuickDeckPolicy.defaults
        save()
    }

    private func save() {
        defaults.set(pinned.map(\.rawValue), forKey: KinetiqQuickDeckPolicy.storageKey)
    }
}

/// User-owned, accessible ordering controls avoid relying exclusively on drag.
@MainActor
struct KinetiqPlayerQuickDeckEditorView: View {
    @ObservedObject private var store = KinetiqPlayerQuickDeckStore.shared
    @State private var search = ""

    private var available: [KinetiqPlayerAction] {
        KinetiqPlayerAction.allCases.filter {
            !store.isPinned($0) && (search.isEmpty ||
                $0.title.localizedStandardContains(search) ||
                $0.category.localizedStandardContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                if store.pinned.isEmpty {
                    Text("Pin any action below to create your Quick Deck.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.pinned) { action in
                    HStack(spacing: 12) {
                        Label(action.title, systemImage: action.symbol)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let index = store.pinned.firstIndex(of: action) ?? 0
                        Button { store.move(action, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(action.title) earlier")
                        Button { store.move(action, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == store.pinned.count - 1)
                        .accessibilityLabel("Move \(action.title) later")
                        Button { store.remove(action) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Unpin \(action.title)")
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Pinned actions · \(store.pinned.count)/\(KinetiqQuickDeckPolicy.maximumPins)")
            } footer: {
                Text("The deck follows you between module episodes. Unsupported actions are disabled during playback, never silently executed.")
            }

            Section("Other player actions") {
                ForEach(available) { action in
                    Button {
                        _ = store.add(action)
                    } label: {
                        HStack {
                            Label(action.title, systemImage: action.symbol)
                            Spacer()
                            Image(systemName: "plus.circle")
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(store.pinned.count >= KinetiqQuickDeckPolicy.maximumPins)
                }
            }

            Section {
                Button("Restore recommended Quick Deck", systemImage: "arrow.counterclockwise") {
                    store.restoreDefaults()
                }
            }
        }
        .searchable(text: $search, prompt: "Search available controls")
        .navigationTitle("Player Quick Deck")
    }
}
