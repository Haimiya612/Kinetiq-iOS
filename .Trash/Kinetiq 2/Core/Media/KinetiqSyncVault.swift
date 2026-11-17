import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// Portable encrypted transport can be added later. This first transport is
/// explicitly manual: user-controlled Files / AirDrop exchange, no server,
/// account, stream credentials, Discord tokens, or media payloads.
struct KinetiqSyncTitleRecord: Codable {
    let sourceID: String
    let sourceName: String
    let animeID: String
    let title: String
    let favorite: Bool
    let savedAt: Date
    let episodes: [ModuleEpisodeProgress]
}

struct KinetiqSyncArchive: Codable {
    let schema: Int
    let generatedAt: Date
    let titles: [KinetiqSyncTitleRecord]
    let anchors: [KinetiqSceneAnchor]
    let bookmarks: [KinetiqSceneBookmark]
    let connections: [KinetiqMediaConnection]
    let theme: String?
    // Optional for backward compatibility with Sync Vault v1 exports.
    var watchPlans: [KinetiqWatchPlan]? = nil

    @MainActor
    static func current(includeTheme: Bool) -> KinetiqSyncArchive {
        let collection = ModuleAnimeCollectionStore.shared
        return KinetiqSyncArchive(schema: 1, generatedAt: Date(), titles:
            collection.entries.map {
                KinetiqSyncTitleRecord(sourceID: $0.sourceID,
                    sourceName: $0.sourceName, animeID: $0.animeID,
                    title: $0.title, favorite: $0.isFavorite,
                    savedAt: $0.savedAt, episodes: $0.episodeProgress ?? [])
            },
            anchors: KinetiqContinuityStore.shared.anchors,
            bookmarks: KinetiqContinuityStore.shared.bookmarks,
            connections: KinetiqMediaConnectionStore.shared.connections,
            theme: includeTheme ? UserDefaults.standard.string(forKey: KinetiqVisualTheme.storageKey) : nil,
            watchPlans: KinetiqWatchPlanStore.shared.plans)
    }

    var isValid: Bool {
        schema == 1 && titles.count <= 400 && anchors.count <= 2_000 &&
        bookmarks.count <= 1_000 && connections.count <= 500 &&
        (watchPlans?.count ?? 0) <= 100 &&
        titles.allSatisfy { !$0.sourceID.isEmpty && $0.sourceID.count <= 1_200 &&
            !$0.animeID.isEmpty && $0.animeID.count <= 1_500 &&
            !$0.title.isEmpty && $0.title.count <= 400 && $0.episodes.count <= 1_000 }
    }
}

struct KinetiqSyncDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var archive: KinetiqSyncArchive

    init(archive: KinetiqSyncArchive) { self.archive = archive }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents,
              contents.count <= 4_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try JSONDecoder().decode(KinetiqSyncArchive.self, from: contents)
        guard archive.isValid else { throw CocoaError(.fileReadCorruptFile) }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(archive))
    }
}

@MainActor
struct KinetiqSyncVaultView: View {
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument: KinetiqSyncDocument?
    @State private var pending: KinetiqSyncArchive?
    @State private var status: String?
    @State private var includeTheme = true
    @State private var importTheme = false

    var body: some View {
        Form {
            Section {
                Label("Your media state, in your hands", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.headline)
                Text("Export and import a portable, readable backup through Files or AirDrop. This is an actual manual cross-device transfer, not cloud auto-sync. Media files, module secrets, Discord RPC credentials and stream URLs are excluded.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Export") {
                Toggle("Include app theme", isOn: $includeTheme)
                Button("Export portable sync file", systemImage: "square.and.arrow.up") {
                    exportDocument = KinetiqSyncDocument(archive: .current(includeTheme: includeTheme))
                    exporting = true
                }
                Text("Includes saved titles, per-episode watch history, approved Source Passport links, scene anchors, bookmarks and watch plans. Existing entries are never deleted during import.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Import") {
                Toggle("Apply theme from imported backup", isOn: $importTheme)
                Button("Choose a Kinetiq sync file", systemImage: "square.and.arrow.down") {
                    importing = true
                }
                if let pending {
                    LabeledContent("Saved titles", value: "\(pending.titles.count)")
                    LabeledContent("Scene anchors", value: "\(pending.anchors.count)")
                    LabeledContent("Confirmed media connections", value: "\(pending.connections.count)")
                    LabeledContent("Watch plans", value: "\(pending.watchPlans?.count ?? 0)")
                    Button("Merge into this device", systemImage: "checkmark.shield") {
                        apply(pending)
                        self.pending = nil
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Discard preview", role: .cancel) { self.pending = nil }
                }
                Text("Conflicts are resolved per saved episode by newer progress dates; favorites are retained if either device saved them. This import never erases local media or credentials.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let status { Section("Status") { Text(status).font(.subheadline) } }
        }
        .navigationTitle("Sync Vault")
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .json, defaultFilename: "Kinetiq-Sync-Vault") { result in
            switch result {
            case .success: status = "Sync snapshot exported. Send the JSON file only to a device you trust."
            case .failure: status = "The sync file could not be exported."
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= 4_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                    let decoded = try JSONDecoder().decode(KinetiqSyncArchive.self, from: data)
                    guard decoded.isValid else { throw CocoaError(.fileReadCorruptFile) }
                    pending = decoded
                    status = "Backup validated. Review the item counts and confirm the merge."
                } catch { status = "This is not a valid supported Kinetiq sync archive." }
            case .failure: status = "No sync file was imported."
            }
        }
    }

    private func apply(_ archive: KinetiqSyncArchive) {
        guard archive.isValid else { status = "Invalid sync data."; return }
        ModuleAnimeCollectionStore.shared.mergeSyncTitles(archive.titles)
        KinetiqContinuityStore.shared.merge(anchors: archive.anchors, bookmarks: archive.bookmarks)
        for link in archive.connections {
            KinetiqMediaConnectionStore.shared.setLinked(true, link.first, link.second)
        }
        KinetiqWatchPlanStore.shared.merge(archive.watchPlans ?? [])
        if importTheme, let raw = archive.theme,
           KinetiqVisualTheme(rawValue: raw) != nil {
            UserDefaults.standard.set(raw, forKey: KinetiqVisualTheme.storageKey)
        }
        status = "Merged \(archive.titles.count) title records and \(archive.anchors.count) scene anchors. Reopen the app to refresh any cached views. Module availability must be verified on this device."
    }
}
