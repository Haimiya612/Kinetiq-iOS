import SwiftUI
import AVFoundation
import AVKit

// MARK: - Episode download flow

struct KinetiqEpisodeDownloadSheet: View {
    let anime: ModuleAnimeItem
    let episode: ModuleAnimeEpisode
    let sourceID: String
    let sourceName: String
    let runtime: SynthetiqModuleRuntime

    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloads = KinetiqOfflineDownloadStore.shared

    @State private var language = "sub"
    @State private var resolving = false
    @State private var resolvedStreams: [ModuleResolvedStream] = []
    @State private var streamIndex = 0
    @State private var variants: [ModuleVideoQualityOption] = []
    @State private var failure: String?
    @State private var started = false
    @State private var enqueuing = false
    @State private var requestID = UUID()

    @AppStorage("kinetiq.offline.defaultQuality")
    private var qualityRaw = KinetiqOfflineQuality.original.rawValue
    @AppStorage("kinetiq.offline.customVariant")
    private var customVariantID = ""
    @AppStorage("kinetiq.offline.wifiOnly")
    private var wifiOnly = true

    private var quality: KinetiqOfflineQuality {
        KinetiqOfflineQuality(rawValue: qualityRaw) ?? .original
    }
    private var selectedVariant: ModuleVideoQualityOption? {
        KinetiqOfflineEligibility.selectedVariant(variants, quality: quality,
            customID: customVariantID)
    }
    private var selectedStream: ModuleResolvedStream? {
        resolvedStreams.indices.contains(streamIndex) ? resolvedStreams[streamIndex] : nil
    }
    private var alreadyQueued: Bool {
        downloads.entry(sourceID: sourceID, animeID: anime.id,
                        episodeID: episode.id, language: language)
            .map { $0.state != .failed } ?? false
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ModuleAnimeArtworkView(url: anime.imageURL)
                            .frame(width: 98, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(anime.title)
                                .font(.headline).lineLimit(2)
                            Text("Episode \(episode.number)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Label(sourceName, systemImage: "play.rectangle.on.rectangle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }

                Section("Episode language") {
                    Picker("Version", selection: $language) {
                        if episode.subAvailable { Text("Sub").tag("sub") }
                        if episode.dubAvailable { Text("Dub").tag("dub") }
                    }
                    .pickerStyle(.segmented)
                }

                if resolving {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Checking playable offline versions…")
                        }
                    }
                } else if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Retry source check") { Task { await resolve() } }
                    }
                } else if !resolvedStreams.isEmpty {
                    Section("Offline source") {
                        if resolvedStreams.count > 1 {
                            Picker("Server", selection: $streamIndex) {
                                ForEach(Array(resolvedStreams.enumerated()), id: \.offset) { index, stream in
                                    Text(stream.label).tag(index)
                                }
                            }
                        } else if let selectedStream {
                            LabeledContent("Server", value: selectedStream.label)
                        }
                        Text("Direct MP4 and HLS streams from your selected module are listed here. Web embeds without a direct video URL cannot be saved using AVFoundation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Video quality") {
                        Picker("Quality", selection: $qualityRaw) {
                            ForEach(variants.isEmpty
                                    ? [KinetiqOfflineQuality.original]
                                    : KinetiqOfflineQuality.allCases) { option in
                                Text(option.rawValue).tag(option.rawValue)
                            }
                        }
                        if quality == .custom {
                            Picker("Maximum resolution", selection: $customVariantID) {
                                ForEach(variants) { variant in
                                    Text(variant.detail).tag(variant.id)
                                }
                            }
                        }
                        if let selectedVariant {
                            LabeledContent("Selected", value: selectedVariant.title)
                        } else {
                            Text(variants.isEmpty
                                 ? "The stream exposes no selectable resolutions. The original version will be saved."
                                 : "Original selects the source's default offline rendition.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Offline subtitles") {
                        Label(selectedStream?.subtitles.isEmpty == false
                              ? "Save all \(selectedStream?.subtitles.count ?? 0) source subtitle tracks"
                              : "All included audio and subtitle tracks",
                              systemImage: "captions.bubble")
                        Text("All available external SRT/WebVTT tracks must download successfully. HLS also requests all advertised audio and caption selections. No tracks are silently skipped.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Network") {
                        Toggle("Wi-Fi only", isOn: $wifiOnly)
                        Text("Cellular transfers are disabled by default. Background transfers can continue while the app is suspended.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("No eligible video",
                        systemImage: "video.slash",
                        description: Text("This episode did not return a direct MP4 or HLS video. Try another episode or server."))
                }

                Section {
                    if alreadyQueued {
                        Label("This episode is already in Downloads",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            beginDownload()
                        } label: {
                            HStack {
                                Spacer()
                                Label(enqueuing ? "Saving all subtitles…" :
                                      (started ? "Added to Downloads" : "Download Episode \(episode.number)"),
                                      systemImage: started ? "checkmark" : "arrow.down.circle.fill")
                                    .font(.headline)
                                if enqueuing { ProgressView().padding(.leading, 6) }
                                Spacer()
                            }
                        }
                        .disabled(resolving || enqueuing || selectedStream == nil || started)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinetiqExperienceBackground())
            .navigationTitle("Download Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: language) { await resolve() }
            .onChange(of: streamIndex) { _, _ in
                Task { await loadVariants() }
            }
            .onChange(of: variants.map(\.id)) { _, options in
                if !options.contains(customVariantID) { customVariantID = options.first ?? "" }
            }
        }
        .presentationDetents([.large])
    }

    @MainActor
    private func resolve() async {
        let id = UUID()
        requestID = id
        resolvedStreams = []
        variants = []
        streamIndex = 0
        failure = nil
        resolving = true
        defer { if requestID == id { resolving = false } }
        let session = ModuleEpisodePlaybackSession(
            animeTitle: anime.title, episodes: [episode], runtime: runtime,
            sourceID: sourceID, animeItem: anime
        )
        let success = await session.play(episode: episode, language: language)
        guard requestID == id, !Task.isCancelled else { return }
        guard success else {
            failure = session.playbackError ?? "The source couldn't resolve this episode."
            return
        }
        resolvedStreams = session.availableStreams.filter {
            KinetiqOfflineEligibility.format(for: $0) != nil
        }
        if resolvedStreams.isEmpty {
            failure = "This module did not return a directly downloadable MP4 or HLS stream."
            return
        }
        await loadVariants()
    }

    @MainActor
    private func loadVariants() async {
        variants = []
        guard let stream = selectedStream,
              KinetiqOfflineEligibility.format(for: stream) == .hls else { return }
        do {
            let asset = KinetiqOfflineEligibility.hlsAsset(for: stream)
            let choices = try await asset.load(.variants)
            guard !Task.isCancelled else { return }
            variants = ModuleVideoQualityCatalog.options(from:
                choices.prefix(ModuleVideoQualityCatalog.maximumVariants).compactMap { variant in
                    guard let video = variant.videoAttributes else { return nil }
                    return ModuleVideoQualityVariant(
                        width: Double(video.presentationSize.width),
                        height: Double(video.presentationSize.height),
                        peakBitRate: variant.peakBitRate
                    )
                }
            )
        } catch {
            variants = []
        }
    }

    private func beginDownload() {
        guard let stream = selectedStream else { return }
        enqueuing = true
        Task { @MainActor in
            defer { enqueuing = false }
            do {
                try await downloads.enqueue(KinetiqOfflineRequest(
                    sourceID: sourceID, sourceName: sourceName,
                    anime: anime, episode: episode, language: language,
                    stream: stream, quality: quality, variant: selectedVariant,
                    wifiOnly: wifiOnly
                ))
                started = true
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Offline tab

private enum KinetiqOfflineFilter: String, CaseIterable, Identifiable {
    case all = "All", downloading = "Active", ready = "Ready", failed = "Failed"
    var id: String { rawValue }
}

struct KinetiqOfflineDownloadsView: View {
    @StateObject private var store = KinetiqOfflineDownloadStore.shared
    @State private var filter: KinetiqOfflineFilter = .all
    @State private var showingSettings = false
    @State private var playback: KinetiqOfflineEntry?
    @AppStorage(KinetiqVisualTheme.storageKey)
    private var themeRaw = KinetiqVisualTheme.signature.rawValue
    private var theme: KinetiqVisualTheme {
        KinetiqVisualTheme(rawValue: themeRaw) ?? .signature
    }

    private var visible: [KinetiqOfflineEntry] {
        store.entries.filter { item in
            switch filter {
            case .all: true
            case .downloading: [.queued, .downloading, .paused].contains(item.state)
            case .ready: item.state == .ready
            case .failed: item.state == .failed
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summary
                    filterPicker
                    if visible.isEmpty {
                        ContentUnavailableView(
                            filter == .all ? "Nothing Downloaded Yet" : "No Matching Downloads",
                            systemImage: "arrow.down.circle",
                            description: Text(filter == .all
                                ? "Episodes you download from your installed streaming modules will appear here."
                                : "Choose another filter to view your episodes.")
                        )
                        .frame(minHeight: 250)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visible) { entry in
                                episodeCard(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(KinetiqExperienceBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                KinetiqOfflinePreferencesView()
            }
            .fullScreenCover(item: $playback) { entry in
                if let url = store.playbackURL(for: entry) {
                    KinetiqOfflinePlayerDestination(entry: entry, url: url,
                        subtitleTracks: store.subtitleTracks(for: entry))
                        .preferredColorScheme(.dark)
                } else {
                    ContentUnavailableView("Download Missing", systemImage: "exclamationmark.triangle",
                        description: Text("The offline file is no longer available."))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(theme == .cinema ? "OFFLINE SCREENING ROOM" : "Downloads")
                    .font(theme == .cinema ? .system(size: 26, weight: .bold, design: .serif) : .largeTitle.bold())
                Text("Your episodes, even without a connection.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(theme.cardBackground, in: Circle())
            }
            .accessibilityLabel("Download settings")
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Label("\(store.entries.filter { $0.state == .ready }.count) offline",
                  systemImage: "checkmark.circle.fill")
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(14)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KinetiqOfflineFilter.allCases) { option in
                    Button(option.rawValue) { filter = option }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(filter == option ? Color.black : Color.primary)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(filter == option ? theme.accent : theme.cardBackground,
                                    in: Capsule())
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
        }
    }

    private func episodeCard(_ entry: KinetiqOfflineEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.accent.opacity(0.15))
                if let text = entry.artworkURL, let url = URL(string: text),
                   url.scheme?.lowercased() == "https" {
                    ModuleAnimeArtworkView(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: entry.state == .ready ? "play.rectangle.fill" : "film")
                        .font(.title2).foregroundStyle(theme.accent)
                }
            }
            .frame(width: 88, height: 102)
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.animeTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Episode \(entry.episodeNumber) · \(entry.language.uppercased())")
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.sourceName + " · " + entry.quality)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                if entry.state == .downloading {
                    ProgressView(value: entry.progress).tint(theme.accent)
                    Text("\(Int(entry.progress * 100))% downloaded").font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label(statusDescription(entry), systemImage: statusSymbol(entry))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(entry.state == .ready ? Color.green : Color.secondary)
                }
                if let error = entry.error, entry.state == .failed {
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3)
                }
                actions(for: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: theme.cardCornerRadius))
    }

    private func statusDescription(_ entry: KinetiqOfflineEntry) -> String {
        switch entry.state {
        case .queued: "Waiting in queue"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .ready:
            "Ready · " + ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
        case .failed: "Unavailable"
        }
    }

    private func statusSymbol(_ entry: KinetiqOfflineEntry) -> String {
        switch entry.state {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .paused: "pause.circle"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func actions(for entry: KinetiqOfflineEntry) -> some View {
        HStack(spacing: 12) {
            if entry.state == .ready {
                Button("Play", systemImage: "play.fill") { playback = entry }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
            }
            if entry.state == .downloading {
                Button("Pause", systemImage: "pause.fill") { store.pause(entry.id) }
                    .buttonStyle(.bordered)
            }
            if entry.state == .paused {
                Button("Resume", systemImage: "play.fill") { store.resume(entry.id) }
                    .buttonStyle(.bordered)
            }
            if entry.state == .failed && store.canRetry(entry.id) {
                Button("Retry", systemImage: "arrow.clockwise") { store.retry(entry.id) }
                    .buttonStyle(.bordered)
            } else if entry.state == .failed {
                Text("Reopen the episode to retry")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                store.remove(entry.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 35, height: 35)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove \(entry.animeTitle), Episode \(entry.episodeNumber)")
        }
        .controlSize(.small)
    }
}

private struct KinetiqOfflinePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("kinetiq.offline.wifiOnly") private var wifiOnly = true
    @AppStorage("kinetiq.offline.concurrent") private var concurrency = 2
    @AppStorage("kinetiq.offline.storageLimitGB") private var storageLimit = 20
    @AppStorage("kinetiq.offline.defaultQuality") private var quality = KinetiqOfflineQuality.original.rawValue
    @AppStorage("kinetiq.offline.notifyCompletion") private var notify = true
    @State private var confirmCleanup = false
    @StateObject private var store = KinetiqOfflineDownloadStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer preferences") {
                    Toggle("Wi-Fi only", isOn: $wifiOnly)
                    Picker("Default quality", selection: $quality) {
                        ForEach(KinetiqOfflineQuality.allCases.filter { $0 != .custom }) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    Picker("Simultaneous episodes", selection: $concurrency) {
                        ForEach(1...4, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                }
                Section("Storage") {
                    Picker("Kinetiq storage limit", selection: $storageLimit) {
                        ForEach([2, 5, 10, 20, 50, 100], id: \.self) { value in
                            Text("\(value) GB").tag(value)
                        }
                    }
                    LabeledContent("Offline video storage",
                        value: ByteCountFormatter.string(fromByteCount: store.totalBytes,
                            countStyle: .file))
                    Button("Delete all completed downloads", role: .destructive) {
                        confirmCleanup = true
                    }
                    .disabled(!store.entries.contains(where: { $0.state == .ready }))
                }
                Section("Notifications") {
                    Toggle("Notify when episode is ready", isOn: $notify)
                }
                Section {
                    Text("Save direct MP4 and HLS episodes from your installed modules. If one server only returns a web page, choose another server with a direct video stream. Your Downloads stay separate from Local Library, and the original Kinetiq player is used offline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Download Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove all completed downloads?",
                isPresented: $confirmCleanup) {
                Button("Delete Downloaded Videos", role: .destructive) {
                    store.removeCompleted()
                }
            } message: {
                Text("Your Local Library imports, favorites and watch history are not affected.")
            }
        }
    }
}

// MARK: - Offline playback: the exact existing Kinetiq module player

@MainActor
private struct KinetiqOfflinePlayerDestination: View {
    @StateObject private var session: ModuleEpisodePlaybackSession

    init(entry: KinetiqOfflineEntry, url: URL,
         subtitleTracks: [ModuleRemoteSubtitleTrack]) {
        _session = StateObject(wrappedValue:
            ModuleEpisodePlaybackSession(offline: entry, url: url,
                                         subtitleTracks: subtitleTracks))
    }

    var body: some View {
        KinetiqModulePlayerView(session: session)
    }
}
