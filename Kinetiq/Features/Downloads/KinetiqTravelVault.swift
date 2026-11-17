import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation

/// A user-exported offline inventory. It deliberately contains neither local
/// filesystem paths nor remote stream URLs, cookies, headers or credentials.
struct KinetiqTravelManifest: Codable {
    struct Episode: Codable {
        let title: String
        let source: String
        let episode: String
        let language: String
        let quality: String
        let format: String
        let bytes: Int64
        let subtitleCount: Int
        let ready: Bool
    }

    let schema: Int
    let createdAt: Date
    let episodes: [Episode]

    init(results: [KinetiqTravelAudit.Result], includeNames: Bool) {
        schema = 1
        createdAt = Date()
        episodes = results.map { result in
            Episode(
                title: includeNames ? result.entry.animeTitle : "Hidden title",
                source: includeNames ? result.entry.sourceName : "Hidden source",
                episode: result.entry.episodeNumber,
                language: result.entry.language,
                quality: result.entry.quality,
                format: result.entry.format.rawValue,
                bytes: max(0, result.entry.bytes),
                subtitleCount: result.entry.subtitleTracks.count,
                ready: result.fileReady
            )
        }
    }
}

struct KinetiqTravelManifestDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var manifest: KinetiqTravelManifest

    init(manifest: KinetiqTravelManifest) { self.manifest = manifest }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        manifest = try JSONDecoder().decode(KinetiqTravelManifest.self, from: data)
        guard manifest.schema == 1 else { throw CocoaError(.fileReadCorruptFile) }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(manifest))
    }
}

/// Offline preflight checks the actual saved payloads, not merely a queue's
/// optimistic `ready` flag. Native playback still requires an Airplane Mode
/// device test; no network request is made by this screen.
enum KinetiqTravelAudit {
    struct Result: Identifiable {
        let entry: KinetiqOfflineEntry
        let failure: String?
        var id: String { entry.id }
        var fileReady: Bool { entry.state == .ready && failure == nil }
    }

    static func inspect(_ entries: [KinetiqOfflineEntry]) -> [Result] {
        entries.map { entry in
            Result(entry: entry, failure: entry.state == .ready ?
                KinetiqOfflineFileAudit.failureReason(for: entry) :
                "This episode has not finished downloading.")
        }
    }
}

/// On-device playback preflight. A successful file check is not enough:
/// decode a real frame for MP4 and check local asset playability for HLS.
/// HLS status remains qualified because some renderers cannot produce stills.
enum KinetiqTravelPlaybackCheck: String {
    case decoded = "A real video frame decoded from this local file"
    case metadata = "Local HLS asset is recognized (full playback still needs Airplane Mode testing)"
    case failed = "The local asset could not be verified for playback"

    static func run(entry: KinetiqOfflineEntry) async -> KinetiqTravelPlaybackCheck {
        guard entry.state == .ready,
              KinetiqOfflineFileAudit.failureReason(for: entry) == nil,
              let path = entry.localPath else { return .failed }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard (try? await asset.load(.isPlayable)) == true else { return .failed }
        if entry.format == .hls { return .metadata }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        do {
            _ = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            return .decoded
        } catch {
            return .failed
        }
    }
}

@MainActor
struct KinetiqTravelVaultView: View {
    @StateObject private var store = KinetiqOfflineDownloadStore.shared
    @State private var lastChecked = Date()
    @State private var includeNamesInExport = true
    @State private var exporting = false
    @State private var exportDocument: KinetiqTravelManifestDocument?
    @State private var exportStatus: String?
    @State private var playbackChecks: [String: KinetiqTravelPlaybackCheck] = [:]
    @State private var playbackCheckedCount = 0
    @State private var playbackTesting = false
    @State private var playbackTask: Task<Void, Never>?

    private struct TravelGroup: Identifiable {
        let title: String
        let results: [KinetiqTravelAudit.Result]
        var id: String { title }
    }

    private var audit: [KinetiqTravelAudit.Result] {
        KinetiqTravelAudit.inspect(store.entries)
    }
    private var readyCount: Int { audit.filter(\.fileReady).count }
    private var verifiedBytes: Int64 {
        audit.filter(\.fileReady).reduce(Int64(0)) { sum, result in
            sum + max(0, result.entry.bytes)
        }
    }
    private var grouped: [TravelGroup] {
        let groups = Dictionary(grouping: audit) {
            "\($0.entry.animeTitle)|\($0.entry.sourceName)"
        }
        return groups.keys.sorted().compactMap { key in
            guard let records = groups[key], let first = records.first else { return nil }
            return TravelGroup(title: "\(first.entry.animeTitle) · \(first.entry.sourceName)",
                    results: records.sorted {
                        ($0.entry.episodeNumber.localizedStandardCompare($1.entry.episodeNumber)) == .orderedAscending
                    })
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    Label("TRAVEL VAULT", systemImage: "airplane")
                        .font(.caption.weight(.heavy)).foregroundStyle(KinetiqPalette.accent)
                    Text("Check before you leave")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(readyCount) of \(audit.count) episodes passed local file checks")
                        .font(.subheadline)
                    Text("\(ByteCountFormatter.string(fromByteCount: verifiedBytes, countStyle: .file)) recorded for ready downloads")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(readyCount), total: Double(max(audit.count, 1)))
                        .tint(KinetiqPalette.accent)
                    Button("Check downloads again", systemImage: "arrow.clockwise") {
                        lastChecked = Date()
                    }
                    .buttonStyle(.bordered)
                    Text("Last checked \(lastChecked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if grouped.isEmpty {
                Section {
                    ContentUnavailableView("Nothing to check", systemImage: "externaldrive",
                        description: Text("Download an authorized episode or season, then return before travelling."))
                }
            }

            ForEach(grouped) { group in
                Section {
                    ForEach(group.results) { result in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: result.fileReady ? "checkmark.shield.fill" :
                                  "exclamationmark.triangle.fill")
                                .foregroundStyle(result.fileReady ? Color.green : Color.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Episode \(result.entry.episodeNumber) · \(result.entry.language.uppercased())")
                                    .font(.subheadline.weight(.medium))
                                Text(result.entry.quality)
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let check = playbackChecks[result.id] {
                                    Label(check.rawValue, systemImage: check == .decoded ?
                                          "checkmark.circle.fill" : "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(check == .failed ? Color.orange : Color.secondary)
                                }
                                if let failure = result.failure {
                                    Text(failure).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Label("Video present; \(result.entry.subtitleTracks.count) external subtitle track(s) checked",
                                          systemImage: "checkmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text("\(group.results.filter(\.fileReady).count) / \(group.results.count) local files passed")
                }
            }

            Section("Playback verification (on this iPhone)") {
                Text("\(playbackCheckedCount) checked · \(playbackChecks.values.filter { $0 == .decoded }.count) decoded frames")
                    .font(.subheadline)
                if playbackTesting {
                    ProgressView(value: Double(playbackCheckedCount),
                                 total: Double(max(1, min(60, readyCount))))
                    Button("Stop playback checks", role: .cancel) {
                        playbackTask?.cancel()
                    }
                } else {
                    Button("Test saved video playback", systemImage: "play.rectangle.on.rectangle") {
                        beginPlaybackChecks()
                    }
                    .disabled(readyCount == 0)
                }
                Text("Reads at most 60 completed files per run. MP4 receives an actual video-frame decode test; downloaded HLS receives a local AVFoundation compatibility check. Neither proves the entire episode, audio, subtitles, or restart playback succeeds.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Offline acceptance") {
                Label("Saved video exists and contains media data", systemImage: "checkmark.circle")
                Label("Saved external subtitle files exist", systemImage: "captions.bubble")
                Label("Airplane Mode and post-restart playback require iPhone testing", systemImage: "iphone.gen3.radiowaves.left.and.right")
                Text("Passing the file preflight is not proof the decoder can play every HLS rendition offline. Streaming URLs, private cookies and user history are never included in this report.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Portable offline manifest") {
                Toggle("Include anime and source names", isOn: $includeNamesInExport)
                Button("Export verified episode inventory", systemImage: "square.and.arrow.up.on.square") {
                    exportDocument = KinetiqTravelManifestDocument(manifest:
                        KinetiqTravelManifest(results: audit, includeNames: includeNamesInExport))
                    exporting = true
                }
                Text("Exports a standalone JSON checklist with episode, language, quality, local-file readiness, size and subtitle count. Stream links, local paths, cookies, tokens and Discord credentials are never included. This is a report, not a media backup.")
                    .font(.caption).foregroundStyle(.secondary)
                if let exportStatus { Text(exportStatus).font(.caption) }
            }
        }
        .onDisappear { playbackTask?.cancel() }
        .navigationTitle("Travel Vault")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .json, defaultFilename: "Kinetiq-Offline-Manifest") { result in
            switch result {
            case .success: exportStatus = "Manifest exported. It contains metadata only, not video files."
            case .failure: exportStatus = "The manifest could not be exported. Your downloads are unchanged."
            }
        }
    }

    private func beginPlaybackChecks() {
        guard !playbackTesting else { return }
        playbackTask?.cancel()
        playbackChecks = [:]
        playbackCheckedCount = 0
        playbackTesting = true
        let candidates = Array(audit.filter(\.fileReady).prefix(60))
        playbackTask = Task { @MainActor in
            for item in candidates {
                if Task.isCancelled { break }
                let outcome = await KinetiqTravelPlaybackCheck.run(entry: item.entry)
                if Task.isCancelled { break }
                playbackChecks[item.id] = outcome
                playbackCheckedCount += 1
            }
            playbackTesting = false
        }
    }
}
