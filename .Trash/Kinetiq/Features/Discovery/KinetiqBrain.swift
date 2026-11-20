import SwiftUI
import UIKit
import Foundation

/// Grounded private inventory tools and opt-in, device-gated conversation.
/// Public catalog matches remain separately attributed to AniList.
@MainActor
struct KinetiqBrainView: View {
    private struct Message: Identifiable {
        let id = UUID()
        let user: Bool
        let text: String
        let source: String?
    }

    @StateObject private var downloads = KinetiqOfflineDownloadStore.shared
    @StateObject private var favorites = ModuleAnimeCollectionStore.shared
    @StateObject private var history = PlaybackHistoryStore.shared
    @StateObject private var nativeBrain = KinetiqNativeBrain.shared
    @AppStorage("kinetiq.brain.nativeAI.v1") private var nativeConversation = false
    @State private var messages: [Message] = [
        Message(user: false, text: "Ask about your unwatched imports, finished shows, downloaded episodes, storage, or public anime. I can refine searches across multiple messages. I only inspect Kinetiq's imported media and saved records.", source: "Local guide")
    ]
    @State private var question = ""
    @State private var busy = false
    @State private var priorIntent: KinetiqDiscoveryIntent?
    @State private var lastCatalogTitles: [KinetiqCatalogSuggestion] = []
    @State private var showCompass = false
    @State private var work: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("KINETIQ BRAIN · LOCAL FIRST", systemImage: "brain.head.profile")
                                .font(.caption.weight(.bold)).foregroundStyle(KinetiqPalette.accent)
                            Text("Your personal media copilot")
                                .font(.title2.bold())
                            Text("Your library, downloads and favorites are answered by local tools. Public catalog filters go only to AniList. Optional Apple Intelligence chat sees the question you type but never a dump of your local library, history or credentials.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)

                        VStack(alignment: .leading, spacing: 7) {
                            Toggle("Conversational AI · on device", isOn: $nativeConversation)
                                .font(.subheadline.weight(.medium))
                                .disabled(!nativeBrain.isAvailable)
                            Text(nativeBrain.availabilityDescription)
                                .font(.caption).foregroundStyle(.secondary)
                            if nativeConversation {
                                Button("Start a fresh AI conversation", systemImage: "arrow.counterclockwise") {
                                    work?.cancel()
                                    busy = false
                                    nativeBrain.resetConversation()
                                    messages.append(Message(user: false,
                                        text: "New on-device conversation started. Private inventory tools are unchanged.",
                                        source: "Kinetiq local control"))
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                        ForEach(messages) { message in
                            HStack(alignment: .top) {
                                if message.user { Spacer(minLength: 35) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(message.text)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                    if let source = message.source {
                                        Label(source, systemImage: "checkmark.shield")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(13)
                                .background(message.user ? KinetiqPalette.accent.opacity(0.20) : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 15))
                                if !message.user { Spacer(minLength: 35) }
                            }
                            .id(message.id)
                        }
                        if busy { ProgressView("Checking permitted sources…") }
                        if !lastCatalogTitles.isEmpty {
                            Button("Open these results in Compass", systemImage: "square.stack.3d.up") {
                                showCompass = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask Kinetiq…", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Send question")
                .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .navigationTitle("Kinetiq Brain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(["What have I not watched?", "Which episodes are ready offline?",
                             "How much space are my downloads using?", "Find finished romance under 13 episodes"], id: \.self) { prompt in
                        Button(prompt) { question = prompt; send() }
                    }
                } label: {
                    Label("Suggested questions", systemImage: "lightbulb")
                }
            }
        }
        .sheet(isPresented: $showCompass) { KinetiqSmartDiscoveryView() }
        .onDisappear { work?.cancel() }
    }

    private func send() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        let text = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !text.isEmpty, !busy else { return }
        question = ""
        messages.append(Message(user: true, text: text, source: nil))
        busy = true
        work?.cancel()
        work = Task {
            let answer = await answer(text)
            guard !Task.isCancelled else { return }
            messages.append(Message(user: false, text: answer.0, source: answer.1))
            busy = false
        }
    }

    private func answer(_ question: String) async -> (String, String) {
        let normalized = question.lowercased()
        let ready = downloads.entries.filter { $0.state == .ready &&
            KinetiqOfflineFileAudit.failureReason(for: $0) == nil }

        if normalized.contains("duplicate") || normalized.contains("library doctor") ||
           normalized.contains("identical file") {
            return ("Open Settings → Kinetiq Power Center → Library Doctor. It scans only your KinetiqMedia imports, confirms duplicates by hashing the entire content, reports possible storage savings, and never deletes anything. Scanning large files starts only when you open it.",
                    "Kinetiq Library Doctor · on-device tool")
        }

        if normalized.contains("storage") || normalized.contains("space") || normalized.contains("size") {
            let bytes = ready.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
            let imports = KinetiqPrivateLibraryScanner.importedVideos()
            let importedBytes = imports.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
            return ("\(ready.count) verified downloaded episodes use \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Separately, \(imports.count) imported videos use \(ByteCountFormatter.string(fromByteCount: importedBytes, countStyle: .file)). This excludes caches and other apps. Travel Vault checks offline downloads; Library Doctor audits imported video duplicates.",
                    "Kinetiq download ledger + imported KinetiqMedia")
        }

        if normalized.contains("offline") || normalized.contains("downloaded") || normalized.contains("downloads") {
            if ready.isEmpty { return ("No downloaded episodes currently pass the file integrity preflight. Open Downloads → Travel Vault for the reason.", "Kinetiq download ledger") }
            let titles = Dictionary(grouping: ready, by: \.animeTitle)
            let lines = titles.keys.sorted().prefix(16).map { title in
                "• \(title): \(titles[title]?.count ?? 0) ready episode(s)"
            }
            return ((["Ready offline:"] + lines + ["These are actual local-file checks, not promises that every codec has been device-tested."]).joined(separator: "\n"), "Kinetiq download ledger + file audit")
        }

        if normalized.contains("unwatched") || normalized.contains("haven't watched") || normalized.contains("not watched") || normalized.contains("backlog") {
            let files = KinetiqPrivateLibraryScanner.importedVideos().filter {
                history.entry(for: $0.id) == nil && !history.hasCompleted(mediaID: $0.id)
            }
            let saved = favorites.favorites.filter { $0.lastPlaybackDate == nil && $0.latestEpisodeID == nil }
            let names = files.prefix(12).map { "• \($0.title) (imported)" }
            let savedNames = saved.prefix(12).map { "• \($0.title) (saved in \($0.sourceName))" }
            let lines = names + savedNames
            return (lines.isEmpty ? "Everything currently imported or saved has a watch record—or the library is empty. I cannot scan files outside Kinetiq without permission." :
                (["\(files.count) imported files and \(saved.count) saved shows have no recorded playback:"] + lines + ["‘Unwatched’ means no Kinetiq progress record; it does not prove you never watched elsewhere."]).joined(separator: "\n"), "Imported KinetiqMedia folder + saved favorites")
        }

        if normalized.contains("favorite") || normalized.contains("watchlist") {
            let titles = favorites.favorites.prefix(20).map { "• \($0.title) — \($0.sourceName)" }
            return (titles.isEmpty ? "You haven't saved any favorites yet." :
                (["Your saved list (\(favorites.favorites.count) titles):"] + titles).joined(separator: "\n"), "Kinetiq Favorites")
        }

        // Local inventory requests above always take precedence. When the user
        // opts in, ordinary open-ended questions use the retained on-device
        // conversation. Explicit catalog/refinement requests still use the
        // live public search below, with actual result IDs and provenance.
        let catalogRequest = normalized.hasPrefix("find ") ||
            normalized.hasPrefix("search ") || normalized.hasPrefix("only ") ||
            normalized.hasPrefix("and ") || normalized.hasPrefix("show me ")
        if nativeConversation && !catalogRequest {
            if let response = await nativeBrain.respond(to: question) {
                return (response + "\n\nThis is an AI-generated conversational response, not a verified catalog, stream or watch-history result.",
                        "Apple Intelligence · on-device conversation")
            }
            return ("The system language model could not answer this turn. Turn off Conversational AI to use the public anime catalog search, or try a shorter question. No watch history was sent.",
                    "On-device model unavailable")
        }

        // Public search uses only the catalog query and genre filters. A
        // follow-up without a new title refines the previous query locally.
        let parsed = KinetiqDiscoveryIntent.interpret(question)
        let refinement = normalized.hasPrefix("only ") || normalized.hasPrefix("and ") ||
                         normalized.hasPrefix("what about ")
        let intent: KinetiqDiscoveryIntent
        if refinement, let previous = priorIntent {
            intent = KinetiqDiscoveryIntent(original: parsed.original,
                catalogSearch: parsed.catalogSearch ?? previous.catalogSearch,
                genre: parsed.genre ?? previous.genre,
                finishedOnly: parsed.finishedOnly || previous.finishedOnly,
                maximumEpisodes: parsed.maximumEpisodes ?? previous.maximumEpisodes,
                asksForLocal: parsed.asksForLocal || previous.asksForLocal)
        } else {
            intent = parsed
        }
        priorIntent = intent
        do {
            let result = try await KinetiqPublicAnimeSearch.shared.search(intent)
            lastCatalogTitles = result.titles
            guard !result.titles.isEmpty else {
                return ("AniList returned no matching anime for this query. Try another title, genre or episode limit in Compass.", "AniList public metadata · no results")
            }
            let lines = result.titles.prefix(9).map {
                "• \($0.displayTitle) [AniList #\($0.id)] — \($0.episodes.map(String.init) ?? "?") episodes, \($0.status ?? "unknown status")"
            }
            return ((["AniList returned these public catalog matches:"] + lines +
                ["This does not verify that any installed module can play them. Open Compass to search sources. Ask ‘only finished’ or ‘only romance’ to refine."]).joined(separator: "\n"), "AniList public metadata (live search)")
        } catch is CancellationError {
            return ("Search canceled.", "Local")
        } catch {
            return ("AniList could not be reached right now. Your local files and history were not uploaded. Try again or open Compass.", "Public metadata request failed")
        }
    }
}
