import SwiftUI
import Foundation
import UniformTypeIdentifiers

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

@MainActor
struct KinetiqTravelVaultView: View {
    @StateObject private var store = KinetiqOfflineDownloadStore.shared
    @State private var lastChecked = Date()
    @State private var includeNamesInExport = true
    @State private var exporting = false
    @State private var exportDocument: KinetiqTravelManifestDocument?
    @State private var exportStatus: String?

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
}
