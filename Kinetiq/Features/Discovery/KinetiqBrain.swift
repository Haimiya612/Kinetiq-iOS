import SwiftUI
import UIKit
import Foundation
import Security

/// Grounded private inventory tools and opt-in, device-gated conversation.
/// Public catalog matches remain separately attributed to AniList.
@MainActor
struct KinetiqBrainView: View {
    private struct Message: Identifiable, Codable {
        var id = UUID()
        let user: Bool
        let text: String
        let source: String?
        var references: [ResearchCard]? = nil
    }

    private struct ResearchCard: Identifiable, Codable, Sendable {
        let title: String
        let detail: String
        let cover: String?
        let link: String
        var id: String { link }
    }

    private struct ChatThread: Identifiable, Codable {
        var id: UUID
        var title: String
        var updatedAt: Date
        var messages: [Message]
    }

    private enum ChatTitle {
        static func suggested(for question: String) -> String {
            let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            let prefix: String
            if lower.contains("download") || lower.contains("offline") { prefix = "📥 Offline & Downloads" }
            else if lower.contains("favorite") || lower.contains("watchlist") { prefix = "⭐ My Watchlist" }
            else if lower.contains("storage") || lower.contains("space") { prefix = "🗂️ Library Storage" }
            else if lower.contains("anime") || lower.hasPrefix("find ") { prefix = "🎬 Anime Discovery" }
            else { prefix = "✦ " + String(text.prefix(44)) }
            return String(prefix.prefix(60))
        }
    }

    /// Transcript only. Never replay a stored thread into Apple Intelligence;
    /// switching threads always resets the model's live, private context.
    private enum TranscriptStore {
        static var directory: URL? {
            FileManager.default.urls(for: .applicationSupportDirectory,
                                     in: .userDomainMask).first?
                .appendingPathComponent("KinetiqBrain", isDirectory: true)
        }

        static var file: URL? { directory?.appendingPathComponent("thread-library.json") }
        static var oldFile: URL? { directory?.appendingPathComponent("local-chat.json") }

        static func load() -> [ChatThread]? {
            guard let file,
                  let data = try? Data(contentsOf: file), data.count <= 3_500_000,
                  let threads = try? JSONDecoder().decode([ChatThread].self, from: data)
            else {
                // M05A users keep their existing chat when enabling M05B.
                guard let oldFile, let data = try? Data(contentsOf: oldFile),
                      data.count <= 750_000,
                      let messages = try? JSONDecoder().decode([Message].self, from: data),
                      !messages.isEmpty else { return nil }
                return [ChatThread(id: UUID(), title: "✦ Previous Conversation",
                                   updatedAt: Date(), messages: Array(messages.suffix(180)))]
            }
            return Array(threads.prefix(50))
        }

        static func save(_ threads: [ChatThread]) {
            guard let file else { return }
            let safe = Array(threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(50)).map {
                ChatThread(id: $0.id, title: String($0.title.prefix(80)),
                           updatedAt: $0.updatedAt, messages: Array($0.messages.suffix(180)))
            }
            guard let data = try? JSONEncoder().encode(safe), data.count <= 3_500_000 else { return }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: file, options: [.atomic, .completeFileProtection])
            } catch {
                // A denied/unavailable protected-storage write should never
                // block the conversation itself.
            }
        }

        static func delete() {
            guard let file else { return }
            try? FileManager.default.removeItem(at: file)
            if let oldFile { try? FileManager.default.removeItem(at: oldFile) }
        }
    }

    @StateObject private var downloads = KinetiqOfflineDownloadStore.shared
    @StateObject private var favorites = ModuleAnimeCollectionStore.shared
    @StateObject private var history = PlaybackHistoryStore.shared
    @StateObject private var nativeBrain = KinetiqNativeBrain.shared
    @AppStorage("kinetiq.brain.nativeAI.v1") private var nativeConversation = false
    @AppStorage("kinetiq.brain.m05.keepLocalChat") private var keepLocalChat = false
    @State private var messages: [Message] = [
        Message(user: false, text: "Ask about your unwatched imports, finished shows, downloaded episodes, storage, or public anime. I can refine searches across multiple messages. I only inspect Kinetiq's imported media and saved records.", source: "Local guide")
    ]
    @State private var question = ""
    @State private var busy = false
    @State private var priorIntent: KinetiqDiscoveryIntent?
    @State private var lastCatalogTitles: [KinetiqCatalogSuggestion] = []
    @State private var latestResearchCards: [ResearchCard] = []
    @State private var showCompass = false
    @State private var work: Task<Void, Never>?
    @State private var showingClearChatConfirmation = false
    @State private var threads: [ChatThread] = []
    @State private var activeThreadID = UUID()
    @State private var showingChatLibrary = false
    @State private var showingRenameChat = false
    @State private var renameText = ""
    @State private var didRestore = false
    @State private var showingResearchSettings = false
    @State private var webSearchKeyDraft = ""
    @State private var webSearchKeySaved = false
    @State private var webSearchNotice = ""

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
                            HStack(spacing: 8) {
                                Button("New chat", systemImage: "plus.bubble") { startNewChat() }
                                    .buttonStyle(.borderedProminent)
                                Button("Chat library", systemImage: "books.vertical") {
                                    persistThread()
                                    showingChatLibrary = true
                                }
                                .buttonStyle(.bordered)
                            }
                            if let current = threads.first(where: { $0.id == activeThreadID }) {
                                Text(current.title).font(.caption.weight(.bold))
                                    .foregroundStyle(KinetiqPalette.accent)
                            }
                            Toggle("Conversational AI · on device", isOn: $nativeConversation)
                                .font(.subheadline.weight(.medium))
                                .disabled(!nativeBrain.isAvailable)
                            Text(nativeBrain.availabilityDescription)
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("Save chats on this iPhone", isOn: $keepLocalChat)
                                .font(.subheadline.weight(.medium))
                            Text("Opt in to storing up to 50 conversations, each with 180 recent messages, in protected app storage. Not synced or uploaded. Model context starts fresh on opening a chat.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if keepLocalChat {
                                Button("Delete all saved conversations", role: .destructive) {
                                    showingClearChatConfirmation = true
                                }
                                .font(.caption)
                            }
                            Button("Web research settings", systemImage: "globe.americas.fill") {
                                webSearchKeySaved = KinetiqBrainWebSearchCredentials.token() != nil
                                showingResearchSettings = true
                            }
                            .font(.subheadline)
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
                                    if let cards = message.references, !cards.isEmpty {
                                        ForEach(cards) { card in
                                            if let link = URL(string: card.link), link.scheme == "https" {
                                                Link(destination: link) {
                                                    HStack(spacing: 10) {
                                                        if let raw = card.cover,
                                                           let url = URL(string: raw), url.scheme == "https" {
                                                            AsyncImage(url: url) { image in
                                                                image.resizable().scaledToFill()
                                                            } placeholder: {
                                                                Image(systemName: "photo").foregroundStyle(.secondary)
                                                            }
                                                            .frame(width: 48, height: 66).clipped()
                                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                        }
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(card.title).font(.caption.weight(.semibold))
                                                                .foregroundStyle(.primary)
                                                                .multilineTextAlignment(.leading)
                                                            Text(card.detail).font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .multilineTextAlignment(.leading)
                                                                .lineLimit(3)
                                                        }
                                                        Spacer(minLength: 0)
                                                        Image(systemName: "arrow.up.right.square")
                                                    }
                                                    .padding(8)
                                                    .background(Color.secondary.opacity(0.12),
                                                        in: RoundedRectangle(cornerRadius: 9))
                                                }
                                            }
                                        }
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
            ToolbarItem(placement: .topBarLeading) {
                Button { showingChatLibrary = true } label: {
                    Label("Chat library", systemImage: "sidebar.left")
                }
            }
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
        .sheet(isPresented: $showingChatLibrary) { chatLibrary }
        .sheet(isPresented: $showingResearchSettings) { webResearchSettings }
        .onAppear {
            KinetiqDiscordPresenceManager.shared.recordScene(.brain)
            guard !didRestore else { return }
            didRestore = true
            if keepLocalChat, let saved = TranscriptStore.load(), !saved.isEmpty {
                threads = saved
                activeThreadID = saved[0].id
                messages = saved[0].messages
            } else { seedCurrentThread() }
        }
        .onChange(of: keepLocalChat) { _, enabled in
            if enabled {
                persistThread()
            }
        }
        .alert("Rename conversation", isPresented: $showingRenameChat) {
            TextField("Conversation title", text: $renameText)
            Button("Save") { renameCurrentThread() }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete all saved Brain conversations?", isPresented: $showingClearChatConfirmation) {
            Button("Delete All Conversations", role: .destructive) {
                work?.cancel()
                busy = false
                nativeBrain.resetConversation()
                TranscriptStore.delete()
                threads.removeAll()
                messages = [Message(user: false,
                    text: "Chat cleared. Ask a new question to get started.",
                    source: "Local guide")]
                seedCurrentThread()
            }
        } message: {
            Text("This permanently removes all Brain conversation transcripts from this iPhone. Favorites and watch history are untouched.")
        }
        .onDisappear {
            work?.cancel()
            KinetiqDiscordPresenceManager.shared.recordScene(.home)
        }
    }

    private var chatLibrary: some View {
        NavigationStack {
            List {
                Section {
                    Button("Start a new conversation", systemImage: "plus.bubble.fill") {
                        startNewChat()
                        showingChatLibrary = false
                    }
                }
                Section("Your conversations") {
                    ForEach(threads.sorted { $0.updatedAt > $1.updatedAt }) { thread in
                        HStack(spacing: 8) {
                            Button {
                                openThread(thread.id)
                                showingChatLibrary = false
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(thread.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(thread.messages.count) messages · \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 43)
                            }
                            .buttonStyle(.plain)
                            if thread.id == activeThreadID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(KinetiqPalette.accent)
                            }
                            Button(role: .destructive) { deleteThread(thread.id) } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(thread.title)")
                        }
                    }
                }
                Section {
                    Text("Saved conversations remain on this iPhone when storage is enabled. Opening an old transcript starts a fresh Apple Intelligence model context; it does not silently resend your old messages.")
                        .font(.caption)
                }
            }
            .navigationTitle("Brain conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename current") {
                        renameText = threads.first(where: { $0.id == activeThreadID })?.title ?? ""
                        showingChatLibrary = false
                        showingRenameChat = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingChatLibrary = false }
                }
            }
        }
    }

    private var webResearchSettings: some View {
        NavigationStack {
            Form {
                Section("Search the actual web") {
                    Text("Brave Web Search searches the open web. Unlike the previous limited Wikipedia lookup, results can come from anime sites, news, guides and other websites. A personal Brave Search API key is required.")
                        .font(.subheadline)
                    SecureField("Personal Brave Search API key", text: $webSearchKeyDraft)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    Button("Save key on this iPhone") {
                        let key = webSearchKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        webSearchKeySaved = KinetiqBrainWebSearchCredentials.save(key)
                        webSearchNotice = webSearchKeySaved ? "Saved securely in iOS Keychain." : "Could not save the key."
                        if webSearchKeySaved { webSearchKeyDraft = "" }
                    }
                    .disabled(webSearchKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved web search key", role: .destructive) {
                        webSearchKeySaved = false
                        _ = KinetiqBrainWebSearchCredentials.save(nil)
                        webSearchNotice = "Web search key removed."
                    }
                    .disabled(!webSearchKeySaved)
                    LabeledContent("Current key", value: webSearchKeySaved ? "Saved securely" : "Not configured")
                    if !webSearchNotice.isEmpty { Text(webSearchNotice).font(.caption) }
                }
                Section("Privacy and limitations") {
                    Text("Only the search words you type are sent to Brave Search. Links and snippets display with source names. No personal library or saved chat is uploaded. This is a search tool, not a remotely hosted ChatGPT-level model. Search provider plans and usage may require payment.")
                        .font(.caption)
                    Link("Brave Search API documentation", destination:
                         URL(string: "https://api-dashboard.search.brave.com/api-reference/web/search/get")!)
                }
            }
            .navigationTitle("Brain web research")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingResearchSettings = false }
                }
            }
        }
    }

    private func seedCurrentThread() {
        let id = UUID()
        activeThreadID = id
        threads.insert(ChatThread(id: id, title: "✦ New Conversation",
                                  updatedAt: Date(), messages: messages), at: 0)
    }

    private func persistThread() {
        if let index = threads.firstIndex(where: { $0.id == activeThreadID }) {
            threads[index].messages = Array(messages.suffix(180))
            threads[index].updatedAt = Date()
        } else { seedCurrentThread() }
        if keepLocalChat { TranscriptStore.save(threads) }
    }

    private func prepareForThreadChange() {
        work?.cancel()
        work = nil
        busy = false
        question = ""
        priorIntent = nil
        lastCatalogTitles = []
        latestResearchCards = []
        nativeBrain.resetConversation()
    }

    private func startNewChat() {
        persistThread()
        prepareForThreadChange()
        messages = [Message(user: false,
            text: "New conversation. Ask me about your library, anime, or public metadata.",
            source: "Kinetiq local guide")]
        seedCurrentThread()
        persistThread()
    }

    private func openThread(_ id: UUID) {
        guard id != activeThreadID,
              let thread = threads.first(where: { $0.id == id }) else { return }
        persistThread()
        prepareForThreadChange()
        activeThreadID = thread.id
        messages = thread.messages
    }

    private func renameCurrentThread() {
        let title = String(renameText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty,
              let index = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        threads[index].title = title
        persistThread()
    }

    private func deleteThread(_ id: UUID) {
        threads.removeAll { $0.id == id }
        if id == activeThreadID {
            prepareForThreadChange()
            if let first = threads.first {
                activeThreadID = first.id
                messages = first.messages
            } else {
                messages = [Message(user: false, text: "New conversation.", source: "Local guide")]
                seedCurrentThread()
            }
        }
        if keepLocalChat { TranscriptStore.save(threads) }
    }

    private func send() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        let text = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !text.isEmpty, !busy else { return }
        question = ""
        latestResearchCards = []
        messages.append(Message(user: true, text: text, source: nil))
        if let index = threads.firstIndex(where: { $0.id == activeThreadID }),
           !threads[index].messages.contains(where: { $0.user }) {
            threads[index].title = ChatTitle.suggested(for: text)
        }
        persistThread()
        busy = true
        work?.cancel()
        work = Task {
            let answer = await answer(text)
            guard !Task.isCancelled else { return }
            let cards: [ResearchCard] = answer.1.hasPrefix("AniList public metadata") ?
                lastCatalogTitles.prefix(12).compactMap { item in
                    guard let url = item.anilistURL else { return nil }
                    let score = item.averageScore.map { " · \($0)% AniList" } ?? ""
                    return ResearchCard(title: item.displayTitle,
                        detail: "\(item.episodes.map(String.init) ?? "?") episodes\(score) · \(item.status ?? "Unknown")",
                        cover: item.coverURL?.absoluteString,
                        link: url.absoluteString)
                } : latestResearchCards
            messages.append(Message(user: false, text: answer.0, source: answer.1,
                                    references: cards.isEmpty ? nil : cards))
            persistThread()
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

        // Research is opt-in per question. Only the typed search term leaves
        // this device; library entries, downloads and previous chats never do.
        if let research = KinetiqBrainPublicResearch.parse(question) {
            switch research.source {
            case .web:
                guard let key = KinetiqBrainWebSearchCredentials.token() else {
                    return ("Real web search is available through Brave Search, but needs your own API key. Open Web research settings in Kinetiq Brain to configure it. Wikipedia is a separate encyclopedia source and will not be mislabelled as web search.",
                            "Brave Web Search · setup required")
                }
                let result = await KinetiqBrainPublicResearch.web(research.query, token: key)
                latestResearchCards = result.cards
                guard !result.cards.isEmpty else {
                    return (result.error ?? "The web search returned no results. Try a different query.",
                            "Brave Web Search · no results")
                }
                return ("I found \(result.cards.count) web results for ‘\(research.query)’. Read the source cards below; they contain search snippets and original links, not invented summaries of pages I haven't read.",
                        "Brave Web Search · independent search index")
            case .wikipedia:
                let cards = await KinetiqBrainPublicResearch.wikipedia(research.query)
                latestResearchCards = cards
                guard !cards.isEmpty else {
                    return ("Wikipedia didn't return a verifiable public article. Try a more specific search phrase.",
                            "Wikipedia public lookup · no results")
                }
                return ("I found \(cards.count) encyclopedia articles for ‘\(research.query)’. Tap a source card below to read the original. Wikipedia is not general web search.",
                        "Wikipedia public article lookup")
            case .tmdb:
                guard let token = KinetiqTMDBCredentials.token(), !token.isEmpty else {
                    return ("TMDB research needs your personal API Read Access Token. Add it under Settings → Metadata Enrichment. Kinetiq does not include or upload a shared key.",
                            "TMDB · credential not configured")
                }
                // Titles often arrive under their nickname or Japanese name.
                // AniList supplies alternative titles; TMDB is then queried
                // with an actual official name instead of only the shorthand.
                let lookup = KinetiqDiscoveryIntent(
                    original: "Find \(research.query)", catalogSearch: research.query,
                    genre: nil, finishedOnly: false, maximumEpisodes: nil, asksForLocal: false)
                let aliases: [String]
                if let page = try? await KinetiqPublicAnimeSearch.shared.search(lookup),
                   let matched = page.titles.first {
                    aliases = [matched.title.english, matched.title.romaji,
                               matched.title.userPreferred].compactMap { $0 }
                } else { aliases = [] }
                let cards = await KinetiqBrainPublicResearch.tmdb(research.query,
                                                                   aliases: aliases, token: token)
                latestResearchCards = cards
                guard !cards.isEmpty else {
                    return ("TMDB found no reliable matches for ‘\(research.query)’ or its AniList title aliases. Try the full English series/movie title.",
                            "TMDB public metadata · no verified title")
                }
                return ("TMDB found \(cards.count) possible title matches. Open the source cards to check ratings, editions and seasons. Ratings are TMDB user averages; TMDB does not endorse Kinetiq.",
                        "TMDB public metadata · user-authorized lookup")
            case .anilist:
                let intent = KinetiqDiscoveryIntent(
                    original: "Find \(research.query)", catalogSearch: research.query,
                    genre: nil, finishedOnly: false, maximumEpisodes: nil, asksForLocal: false)
                do {
                    let results = try await KinetiqPublicAnimeSearch.shared.search(intent)
                    lastCatalogTitles = results.titles
                    return (results.titles.isEmpty ? "AniList found no matching title." :
                        "AniList found \(results.titles.count) titles. Browse the posters and ratings below. Scores are AniList community averages, not Kinetiq reviews.",
                        "AniList public metadata (live search)")
                } catch {
                    return ("AniList is temporarily unavailable.", "AniList public lookup failed")
                }
            }
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
                "• \($0.displayTitle) [AniList #\($0.id)] — \($0.episodes.map(String.init) ?? "?") episodes, \($0.status ?? "unknown status")\($0.averageScore.map { " · \($0)% AniList" } ?? "")"
            }
            return ((["AniList returned these public catalog matches:"] + lines +
                ["This does not verify that any installed module can play them. Open Compass to search sources. Ask ‘only finished’ or ‘only romance’ to refine."]).joined(separator: "\n"), "AniList public metadata (live search)")
        } catch is CancellationError {
            return ("Search canceled.", "Local")
        } catch {
            return ("AniList could not be reached right now. Your local files and history were not uploaded. Try again or open Compass.", "Public metadata request failed")
        }
    }

    /// Explicit, bounded public lookups. No hidden scraping, open-web promises,
    /// local-library uploads, fabricated scores, or inferred media matches.
    private enum KinetiqBrainPublicResearch {
        enum Source { case web, wikipedia, tmdb, anilist }
        struct Query {
            let source: Source
            let query: String
        }

        static func parse(_ original: String) -> Query? {
            let value = original.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefixes: [(String, Source)] = [
                ("search the web for ", .web), ("web search ", .web),
                ("search the web ", .web), ("web ", .web),
                ("look up online ", .web), ("search online ", .web),
                ("wikipedia ", .wikipedia),
                ("tmdb ", .tmdb), ("movie rating ", .tmdb),
                ("anilist ", .anilist), ("anime rating ", .anilist),
                ("rating ", .anilist), ("tell me about ", .anilist)
            ]
            if let selected = prefixes.first(where: { value.lowercased().hasPrefix($0.0) }) {
                let text = String(value.dropFirst(selected.0.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard (2...120).contains(text.count) else { return nil }
                return Query(source: selected.1, query: text)
            }
            // Everyday natural-language research should not require a magic
            // command prefix. Keep follow-up catalogue filters on their
            // original local/AniList route.
            let lower = value.lowercased()
            let webQuestion = ["who ", "why ", "how ", "when ", "where ",
                               "what is ", "what are ", "latest ", "news about "]
                .contains(where: { lower.hasPrefix($0) })
            guard webQuestion, (4...120).contains(value.count) else { return nil }
            return Query(source: .web, query: value)
        }

        private struct BraveEnvelope: Decodable {
            let web: Web?
            struct Web: Decodable { let results: [Page]? }
            struct Page: Decodable {
                let title: String?
                let description: String?
                let url: String?
                let thumbnail: Thumbnail?
            }
            struct Thumbnail: Decodable { let src: String? }
        }

        struct WebResult {
            let cards: [ResearchCard]
            let error: String?
        }

        static func web(_ text: String, token: String) async -> WebResult {
            var parts = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
            parts?.queryItems = [
                .init(name: "q", value: text),
                .init(name: "count", value: "10"),
                .init(name: "safesearch", value: "moderate")
            ]
            guard let url = parts?.url else { return WebResult(cards: [], error: "Invalid search words.") }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(token, forHTTPHeaderField: "X-Subscription-Token")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return WebResult(cards: [], error: "The search service did not return an HTTP response.")
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    return WebResult(cards: [], error: "Brave refused the search key. Check your account plan and key in Web research settings.")
                }
                if http.statusCode == 429 {
                    return WebResult(cards: [], error: "Brave's search quota or rate limit was reached. Please try again later.")
                }
                guard http.statusCode == 200, data.count <= 1_000_000,
                      let decoded = try? JSONDecoder().decode(BraveEnvelope.self, from: data)
                else { return WebResult(cards: [], error: "Brave search is temporarily unavailable.") }
                var seen = Set<String>()
                let cards = (decoded.web?.results ?? []).compactMap { item -> ResearchCard? in
                    guard let title = item.title, let originalURL = item.url,
                          let url = URL(string: originalURL), url.scheme == "https",
                          let host = url.host, !host.isEmpty,
                          seen.insert(originalURL).inserted else { return nil }
                    let cover = item.thumbnail?.src.flatMap { URL(string: $0) }
                    return ResearchCard(title: String(title.prefix(140)),
                        detail: String((item.description ?? host).prefix(350)),
                        cover: cover?.scheme == "https" ? cover?.absoluteString : nil,
                        link: originalURL)
                }
                return WebResult(cards: Array(cards.prefix(10)), error: nil)
            } catch {
                return WebResult(cards: [], error: "Could not reach Brave Search. Check your connection and try again.")
            }
        }

        private struct WikiEnvelope: Decodable {
            let query: WikiQuery?
            struct WikiQuery: Decodable { let pages: [Page]? }
            struct Page: Decodable {
                let pageid: Int?
                let title: String
                let extract: String?
                let thumbnail: Thumbnail?
            }
            struct Thumbnail: Decodable { let source: String? }
        }

        static func wikipedia(_ text: String) async -> [ResearchCard] {
            var url = URLComponents(string: "https://en.wikipedia.org/w/api.php")
            url?.queryItems = [
                .init(name: "action", value: "query"),
                .init(name: "format", value: "json"),
                .init(name: "formatversion", value: "2"),
                .init(name: "generator", value: "prefixsearch"),
                .init(name: "gpssearch", value: text),
                .init(name: "gpslimit", value: "6"),
                .init(name: "prop", value: "pageimages|extracts"),
                .init(name: "piprop", value: "thumbnail"),
                .init(name: "pithumbsize", value: "180"),
                .init(name: "exintro", value: "1"),
                .init(name: "explaintext", value: "1"),
                .init(name: "exsentences", value: "2")
            ]
            guard let endpoint = url?.url else { return [] }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 12
            request.setValue("Kinetiq-iOS/0.3 (https://github.com/Haimiya612/Kinetiq-iOS)",
                             forHTTPHeaderField: "User-Agent")
            guard let fetched = try? await URLSession.shared.data(for: request),
                  (fetched.1 as? HTTPURLResponse)?.statusCode == 200,
                  fetched.0.count <= 600_000,
                  let result = try? JSONDecoder().decode(WikiEnvelope.self, from: fetched.0)
            else { return [] }
            return (result.query?.pages ?? []).compactMap { page in
                guard let id = page.pageid, id > 0 else { return nil }
                let cover = page.thumbnail?.source.flatMap { URL(string: $0) }
                return ResearchCard(title: page.title,
                    detail: String((page.extract ?? "Public encyclopedia article").prefix(280)),
                    cover: cover?.scheme == "https" ? cover?.absoluteString : nil,
                    link: "https://en.wikipedia.org/?curid=\(id)")
            }
        }

        private struct TMDBEnvelope: Decodable {
            let results: [Media]
            struct Media: Decodable {
                let id: Int
                let name: String?
                let title: String?
                let vote_average: Double?
                let vote_count: Int?
                let poster_path: String?
                let overview: String?
                var displayTitle: String { name ?? title ?? "" }
            }
        }

        static func tmdb(_ text: String, aliases: [String], token: String) async -> [ResearchCard] {
            let terms = Array(([text] + aliases).filter { !$0.isEmpty }.prefix(4))
            let normalizedTerms = Set(terms.map(KinetiqEpisodeMetadataMatching.normalized))
            guard !normalizedTerms.isEmpty else { return [] }
            var matches: [ResearchCard] = []
            var seen = Set<String>()
            for term in terms.prefix(3) {
              for type in ["tv", "movie"] {
                var url = URLComponents(string: "https://api.themoviedb.org/3/search/\(type)")
                url?.queryItems = [
                    .init(name: "query", value: term),
                    .init(name: "language", value: "en-US"),
                    .init(name: "include_adult", value: "false")
                ]
                guard let endpoint = url?.url else { continue }
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 12
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                guard let fetched = try? await URLSession.shared.data(for: request),
                      (fetched.1 as? HTTPURLResponse)?.statusCode == 200,
                      fetched.0.count <= 600_000,
                      let result = try? JSONDecoder().decode(TMDBEnvelope.self, from: fetched.0)
                else { continue }
                for media in result.results.prefix(12) {
                    let titleKey = KinetiqEpisodeMetadataMatching.normalized(media.displayTitle)
                    let matchesTitle = normalizedTerms.contains(titleKey) ||
                        normalizedTerms.contains(where: { candidate in
                            candidate.count >= 6 && titleKey.hasPrefix(candidate + " ")
                        })
                    guard matchesTitle, seen.insert("\(type)-\(media.id)").inserted else { continue }
                    let rating = media.vote_average.map { String(format: "%.1f/10", $0) }
                    let votes = media.vote_count.map { "(\($0) votes)" } ?? ""
                    let score = rating.map { "TMDB \($0) \(votes)" } ?? "No TMDB rating"
                    let overview = String((media.overview ?? "").prefix(150))
                    let art = media.poster_path.flatMap { path -> String? in
                        guard path.hasPrefix("/"), !path.contains("..") else { return nil }
                        return "https://image.tmdb.org/t/p/w342\(path)"
                    }
                    matches.append(ResearchCard(title: media.displayTitle,
                        detail: "\(score) · \(overview) · Verify season/edition", cover: art,
                        link: "https://www.themoviedb.org/\(type)/\(media.id)"))
                    if matches.count >= 6 { return matches }
                }
              }
            }
            return matches
        }
    }
}

/// A user-supplied search credential is never stored in UserDefaults,
/// transcripts or the repository. All requests originate from this device.
private enum KinetiqBrainWebSearchCredentials {
    private static let service = "com.kinetiq.brain.web-search"
    private static let account = "personalBraveSearchKey"

    static func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String?) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        guard let data = key.data(using: .utf8) else { return false }
        var attributes = query
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
