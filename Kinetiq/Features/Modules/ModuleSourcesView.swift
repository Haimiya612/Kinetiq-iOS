import SwiftUI
import Foundation
import UIKit

// MARK: - Repository Models

struct ModuleRepositoryDocument: Decodable {
    let schemaVersion: Int?
    let repositoryId: String?
    let name: String?
    let enabled: Bool?
    let modules: [ModuleRepositoryModule]?
    let defaultModules: [String: String]?
    let defaultModulesSignature: String?
    let signature: String?
}

struct ModuleRepositoryPresentation: Codable, Hashable {
    let category: String?
    let purpose: String?
    let recommended: Bool?
    let language: String?
    let languages: [String]?
    let iconUrl: String?
}

struct ModuleRepositoryModule: Codable, Hashable, Identifiable {
    let moduleId: String
    let moduleFamilyId: String?
    let moduleIdentity: String?
    let moduleIdentityNumber: Int?
    let contentType: String?
    let version: String?
    let minAppVersion: String?
    let packageUrl: String?
    let packagePath: String?
    let sha256: String?
    let signature: String?
    let publishedAtMs: Int64?
    let changelog: [String]?
    let presentation: ModuleRepositoryPresentation?

    var id: String {
        moduleId
    }

    private var packageName: String? {
        guard let packageLocation = packageUrl ?? packagePath else {
            return nil
        }

        let filename = URL(string: packageLocation)?.lastPathComponent
            ?? URL(fileURLWithPath: packageLocation).lastPathComponent

        let withoutExtension = filename.replacingOccurrences(
            of: #"\.zip$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let withoutVersion = withoutExtension.replacingOccurrences(
            of: #"[-_ ]v?\d+(?:\.\d+){1,3}(?:-[A-Za-z0-9.-]+)?$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return withoutVersion.isEmpty ? nil : withoutVersion
    }

    private var identityNameKey: String {
        let components = (moduleIdentity ?? "").split(separator: "-")
        let suffix = components.count > 3
            ? components.dropFirst(3).joined()
            : moduleId

        return suffix
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    var displayName: String {
        // The current Synthetiq catalogue does not define a separate
        // per-module "name" field. Use stable identity and the package
        // filename so the source's original branding is not rewritten.
        let canonicalNames: [String: String] = [
            "synthetiqanime": "Synthetiq Anime",
            "animedirect": "Synthetiq Flux",
            "synthetiqone": "Synthetiq One",
            "anipm": "AniPM",
            "anikoto": "AniKoto",
            "anikage": "AniKage",
            "yflix": "YFlix",
            "dramacool": "DramaCool",
            "dramadirect": "Drama Direct",
            "onepace": "One Pace",
            "animeheaven": "AnimeHeaven",
            "xstream": "X-Stream",
            "miruro": "Miruro",
            "animesama": "Anime-Sama",
            "an1me": "An1me",
            "animeav1": "AnimeAV1",
            "kartoons": "Kartoons",
            "dramafun": "DramaFun",
            "toontales": "ToonTales",
            "aniworld": "AniWorld",
            "megakino": "MegaKino",
            "weebcentral": "WeebCentral",
            "synthetiqmanga": "Synthetiq Manga",
            "atsu": "Atsu",
            "synthetiqmusichub": "Synthetiq Music Hub",
            "animeunity": "AnimeUnity",
            "kickassanime": "KickAssAnime",
            "shahiid": "Shahiid",
            "mugiwara": "Mugiwara",
            "justanime": "JustAnime",
            "streamingunity": "StreamingUnity",
            "mangakatana": "MangaKatana",
            "mgreadlikemanga": "MGRead Like Manga",
            "colorizedmanga": "ColorizedManga",
            "alphamovies": "Alpha Movies",
            "moviedb": "MovieDB",
            "cimaclub": "CimaClub",
            "anime4up": "Anime4up"
        ]

        if let canonicalName = canonicalNames[identityNameKey] {
            return canonicalName
        }

        if let packageName {
            return packageName.replacingOccurrences(
                of: "_",
                with: " "
            )
        }

        return moduleId.replacingOccurrences(
            of: #"(?i)-v\d+(?:\.\d+)*$"#,
            with: "",
            options: .regularExpression
        )
    }

    var displaySubtitle: String {
        let languageModes = presentation?.languages?
            .map { $0.uppercased() }
            .joined(separator: " / ")

        return [
            presentation?.category,
            presentation?.language,
            languageModes,
            version.map { "v\($0)" }
        ]
        .compactMap { value in
            guard let value,
                  !value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                return nil
            }

            return value
        }
        .joined(separator: " • ")
    }

    var displayPurpose: String? {
        let value = presentation?.purpose?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value?.isEmpty == false ? value : nil
    }

    var displayType: String {
        (contentType ?? "Module").capitalized
    }

    var publishedDate: Date? {
        guard let publishedAtMs else {
            return nil
        }

        return Date(
            timeIntervalSince1970: TimeInterval(publishedAtMs) / 1_000
        )
    }
}

struct ModuleRepositoryRecord: Identifiable, Codable {
    let url: URL
    var repositoryId: String?
    var name: String
    var modules: [ModuleRepositoryModule]
    var lastRefreshed: Date?
    var refreshError: String?
    var schemaVersion: Int? = nil
    var enabled: Bool? = nil
    var defaultModules: [String: String]? = nil
    var defaultModulesSignature: String? = nil
    var signature: String? = nil

    var id: String {
        url.absoluteString
    }
}

struct ModuleSourceOption: Identifiable {
    let repositoryURL: URL
    let repositoryName: String
    let module: ModuleRepositoryModule

    var id: String {
        "\(repositoryURL.absoluteString)|\(module.moduleId)"
    }

    @MainActor
    var title: String {
        if let installed = ModulePackageStore.shared.installedModule(for: self),
           installed.version == module.version,
           let expectedChecksum = module.sha256,
           installed.packageSHA256.lowercased() == expectedChecksum.lowercased() {
            return installed.name
        }

        return module.displayName
    }

    var subtitle: String {
        module.displaySubtitle.isEmpty
            ? module.displayType
            : module.displaySubtitle
    }

    var packageURL: URL? {
        if let packageUrl = module.packageUrl,
           let url = URL(string: packageUrl),
           url.scheme?.lowercased() == "https",
           url.host != nil {
            return url
        }

        guard let packagePath = module.packagePath else {
            return nil
        }

        if let absoluteURL = URL(string: packagePath),
           absoluteURL.scheme?.lowercased() == "https",
           absoluteURL.host != nil {
            return absoluteURL
        }

        // Synthetiq's packagePath values are GitHub release paths, while
        // its repository.json is hosted on raw.githubusercontent.com.
        if repositoryURL.host?.lowercased() == "raw.githubusercontent.com",
           packagePath.hasPrefix("/") {
            var components = URLComponents(
                url: repositoryURL,
                resolvingAgainstBaseURL: false
            )
            components?.host = "github.com"
            components?.path = packagePath
            components?.query = nil
            components?.fragment = nil
            return components?.url
        }

        return URL(
            string: packagePath,
            relativeTo: repositoryURL
        )?.absoluteURL
    }

    var iconURL: URL? {
        guard let rawValue = module.presentation?.iconUrl,
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https" else {
            return nil
        }

        return url
    }

    var symbol: String {
        switch module.contentType?.lowercased() {
        case "video":
            return "play.rectangle.fill"
        case "image":
            return "photo.fill"
        case "music":
            return "music.note"
        case "text":
            return "doc.text.fill"
        default:
            return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Repository Errors

private enum ModuleRepositoryError: LocalizedError {
    case invalidURL
    case duplicate
    case operationInProgress
    case invalidResponse
    case responseTooLarge
    case invalidDocument
    case unsupportedSchema(Int)
    case disabledRepository

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTPS repository.json URL."

        case .duplicate:
            return "This repository has already been added."

        case .operationInProgress:
            return "A repository operation is already running. Try again when it finishes."

        case .invalidResponse:
            return "The server did not return a successful response."

        case .responseTooLarge:
            return "The repository response is larger than the allowed limit."

        case .invalidDocument:
            return "The JSON file does not contain a valid module repository."

        case .unsupportedSchema(let version):
            return "Repository schema version \(version) is not supported."

        case .disabledRepository:
            return "This repository is currently disabled."
        }
    }
}

// MARK: - Shared Module Source Store

@MainActor
final class ModuleSourceStore: ObservableObject {

    static let shared = ModuleSourceStore()

    static let localLibraryID = "kinetiq.local-library"

    static let synthetiqRepositoryURL =
        "https://raw.githubusercontent.com/kas021/Synthetiq-Modules/main/repository.json"

    private static let repositoriesKey =
        "kinetiq.modules.repositoryURLs"

    private static let selectedSourceKey =
        "kinetiq.modules.selectedSource"

    private static let repositoryCacheKey =
        "kinetiq.modules.repositoryCache.v1"

    private static let maximumRepositoryCacheBytes = 2_000_000

    @Published private(set) var repositories: [ModuleRepositoryRecord] = []

    @Published private(set) var selectedSourceID: String

    @Published private(set) var isRefreshing = false

    private var hasLoadedSavedRepositories = false

    private init() {
        selectedSourceID =
            UserDefaults.standard.string(forKey: Self.selectedSourceKey)
            ?? Self.localLibraryID

        // Restore catalogue and icons immediately. Network refresh happens
        // afterwards; temporary outages must not erase usable module metadata.
        if let data = UserDefaults.standard.data(forKey: Self.repositoryCacheKey),
           data.count <= Self.maximumRepositoryCacheBytes,
           let cached = try? JSONDecoder().decode([ModuleRepositoryRecord].self, from: data) {
            let savedURLs = Set(UserDefaults.standard.stringArray(
                forKey: Self.repositoriesKey
            ) ?? [])
            repositories = cached.filter { savedURLs.contains($0.url.absoluteString) }
        }
    }

    private func persistRepositoryCache() {
        guard let data = try? JSONEncoder().encode(repositories),
              data.count <= Self.maximumRepositoryCacheBytes else { return }
        UserDefaults.standard.set(data, forKey: Self.repositoryCacheKey)
    }

    // MARK: Available Sources

    var availableSources: [ModuleSourceOption] {
        repositories.flatMap {
            sources(in: $0)
        }
    }

    var activeSource: ModuleSourceOption? {
        availableSources.first {
            $0.id == selectedSourceID
        }
    }

    var isLocalLibrarySelected: Bool {
        selectedSourceID == Self.localLibraryID
    }

    var activeSourceTitle: String {
        if isLocalLibrarySelected { return "Local Library" }
        return activeSource?.title ?? "Source Unavailable"
    }

    var activeSourceSubtitle: String {
        guard let activeSource else {
            return isLocalLibrarySelected
                ? "Personal media on this device"
                : "Refresh repositories to reconnect"
        }
        return "\(activeSource.repositoryName) • \(activeSource.subtitle)"
    }

    var activeSourceSymbol: String {
        activeSource?.symbol
            ?? (isLocalLibrarySelected ? "iphone" : "exclamationmark.triangle")
    }

    func sources(
        in repository: ModuleRepositoryRecord
    ) -> [ModuleSourceOption] {
        repository.modules.map {
            ModuleSourceOption(
                repositoryURL: repository.url,
                repositoryName: repository.name,
                module: $0
            )
        }
    }

    func isSelected(_ sourceID: String) -> Bool {
        selectedSourceID == sourceID
    }

    // MARK: Source Selection

    func selectSource(_ sourceID: String) {
        guard
            sourceID == Self.localLibraryID
            || availableSources.contains(where: { $0.id == sourceID })
        else {
            return
        }

        selectedSourceID = sourceID

        UserDefaults.standard.set(
            sourceID,
            forKey: Self.selectedSourceKey
        )
    }

    func selectLocalLibrary() {
        selectSource(Self.localLibraryID)
    }

    // MARK: Saved Repositories

    func loadSavedRepositoriesIfNeeded() async {
        guard !hasLoadedSavedRepositories else {
            return
        }

        hasLoadedSavedRepositories = true
        await refreshAll()
        if Task.isCancelled {
            // A cancelled first launch must retry on the next Home appearance.
            hasLoadedSavedRepositories = false
        }
    }

    func addRepository(from rawValue: String) async throws {
        guard !isRefreshing else { throw ModuleRepositoryError.operationInProgress }
        let url = try validatedRepositoryURL(rawValue)

        let savedURLs =
            UserDefaults.standard.stringArray(forKey: Self.repositoriesKey)
            ?? []

        guard
            !savedURLs.contains(url.absoluteString),
            !repositories.contains(where: { $0.url == url })
        else {
            throw ModuleRepositoryError.duplicate
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let repository = try await fetchRepository(from: url)

        repositories.append(repository)
        persistRepositoryCache()

        saveRepositoryURLs(
            savedURLs + [url.absoluteString]
        )
    }

    func removeRepository(_ repository: ModuleRepositoryRecord) {
        repositories.removeAll {
            $0.id == repository.id
        }
        persistRepositoryCache()

        let savedURLs =
            UserDefaults.standard.stringArray(forKey: Self.repositoriesKey)
            ?? []

        saveRepositoryURLs(
            savedURLs.filter {
                $0 != repository.url.absoluteString
            }
        )

        let removedSourcePrefix =
            repository.url.absoluteString + "|"

        if selectedSourceID.hasPrefix(removedSourcePrefix) {
            selectLocalLibrary()
        }
    }

    // MARK: Refresh

    /// A failed repository may have no cached modules after app relaunch.
    /// Preserve the user's choice until a successful response proves it gone.
    static func selectionBelongsToFailedRepository(
        _ selectedSourceID: String,
        in repositories: [ModuleRepositoryRecord]
    ) -> Bool {
        guard selectedSourceID != localLibraryID else { return false }
        return repositories.contains {
            $0.refreshError != nil &&
            selectedSourceID.hasPrefix($0.url.absoluteString + "|")
        }
    }

    func refreshAll() async {
        // Multiple tabs and pull-to-refresh can request the same refresh.
        // Avoid an older request overwriting a newer catalogue.
        guard !isRefreshing else { return }

        let savedURLs =
            UserDefaults.standard.stringArray(forKey: Self.repositoriesKey)
            ?? []

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        var refreshedRepositories: [ModuleRepositoryRecord] = []

        for rawURL in savedURLs {
            guard let url = URL(string: rawURL) else {
                continue
            }

            do {
                let repository = try await fetchRepository(from: url)
                guard !Task.isCancelled else { return }
                refreshedRepositories.append(repository)
            } catch {
                let previous = repositories.first {
                    $0.url == url
                }

                refreshedRepositories.append(
                    ModuleRepositoryRecord(
                        url: url,
                        repositoryId: previous?.repositoryId,
                        name: previous?.name ?? url.host ?? "Repository",
                        modules: previous?.modules ?? [],
                        lastRefreshed: previous?.lastRefreshed,
                        refreshError: error.localizedDescription,
                        schemaVersion: previous?.schemaVersion,
                        enabled: previous?.enabled,
                        defaultModules: previous?.defaultModules,
                        defaultModulesSignature: previous?.defaultModulesSignature,
                        signature: previous?.signature
                    )
                )
            }
        }

        guard !Task.isCancelled else { return }
        repositories = refreshedRepositories
        persistRepositoryCache()

        if
            !isLocalLibrarySelected,
            !availableSources.contains(where: {
                $0.id == selectedSourceID
            }),
            !Self.selectionBelongsToFailedRepository(
                selectedSourceID,
                in: refreshedRepositories
            )
        {
            // Only drop an obsolete selection after a successful refresh.
            selectLocalLibrary()
        }
    }

    // MARK: Repository Download and Validation

    private func validatedRepositoryURL(
        _ rawValue: String
    ) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            let url = components.url
        else {
            throw ModuleRepositoryError.invalidURL
        }

        return url
    }

    private func fetchRepository(
        from url: URL
    ) async throws -> ModuleRepositoryRecord {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw ModuleRepositoryError.invalidResponse
        }

        guard data.count <= 8_000_000 else {
            throw ModuleRepositoryError.responseTooLarge
        }

        let document = try JSONDecoder().decode(
            ModuleRepositoryDocument.self,
            from: data
        )

        if let schemaVersion = document.schemaVersion,
           schemaVersion != 1 {
            throw ModuleRepositoryError.unsupportedSchema(
                schemaVersion
            )
        }

        guard document.enabled != false else {
            throw ModuleRepositoryError.disabledRepository
        }

        guard let modules = document.modules else {
            throw ModuleRepositoryError.invalidDocument
        }

        let repositoryName =
            document.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ModuleRepositoryRecord(
            url: url,
            repositoryId: document.repositoryId,
            name: repositoryName?.isEmpty == false
                ? repositoryName!
                : (url.host ?? "Module Repository"),
            modules: modules,
            lastRefreshed: Date(),
            refreshError: nil,
            schemaVersion: document.schemaVersion,
            enabled: document.enabled,
            defaultModules: document.defaultModules,
            defaultModulesSignature: document.defaultModulesSignature,
            signature: document.signature
        )
    }

    private func saveRepositoryURLs(_ urls: [String]) {
        UserDefaults.standard.set(
            urls,
            forKey: Self.repositoriesKey
        )
    }
}

// MARK: - Module Sources Screen

struct ModuleSourcesView: View {

    @StateObject private var store = ModuleSourceStore.shared
    @StateObject private var packageStore = ModulePackageStore.shared

    // One repository at a time. Each module uses the existing package installer:
    // HTTPS ZIP, exact SHA-256, manifest and JavaScript handler validation.
    @State private var pendingBatchRepositoryID: String?
    @State private var showingBatchConfirmation = false
    @State private var activeBatchRepositoryID: String?
    @State private var batchTask: Task<Void, Never>?
    @State private var batchInstalled = 0
    @State private var batchProcessed = 0
    @State private var batchTotal = 0
    @State private var batchSkipped = 0
    @State private var batchFailures: [String] = []
    @State private var batchCurrentModule = ""
    @State private var batchReport: String?
    @State private var showingBatchReport = false

    @State private var repositoryURL =
        ModuleSourceStore.synthetiqRepositoryURL

    @State private var isAddingRepository = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // MARK: Add Repository

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        "Paste repository.json URL",
                        text: $repositoryURL,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        Task {
                            await addRepository()
                        }
                    } label: {
                        HStack {
                            if isAddingRepository {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }

                            Text("Add Repository")
                                .fontWeight(.semibold)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        isAddingRepository
                        || store.isRefreshing
                        || repositoryURL.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )

                    if let errorMessage {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                }
                .padding(.vertical, 5)
            } header: {
                Text("Add a Source")
            } footer: {
                Text(
                    "Paste a repository.json link. Kinetiq will retrieve its catalogue and make its modules available in the Home source dropdown."
                )
            }

            // MARK: Connected Repositories

            Section {
                if store.repositories.isEmpty && store.isRefreshing {
                    KinetiqAsyncStateView(
                        kind: .loading,
                        title: "Refreshing Repositories",
                        message: "Retrieving your saved module catalogues."
                    )
                } else if store.repositories.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "square.stack.3d.up",
                        description: Text(
                            "Add a repository.json URL above to discover modules."
                        )
                    )
                } else {
                    ForEach(store.repositories) { repository in
                        DisclosureGroup {
                            if !repository.modules.isEmpty {
                                batchControls(for: repository)
                            }

                            if repository.modules.isEmpty {
                                Text(
                                    repository.refreshError
                                    ?? "This repository does not contain any modules."
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            } else {
                                ForEach(store.sources(in: repository)) { source in
                                    ModuleSourceListRow(
                                        source: source,
                                        isSelected: store.isSelected(source.id)
                                    ) {
                                        store.selectSource(source.id)
                                    }
                                }
                            }

                            if let refreshError = repository.refreshError {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(refreshError)
                                        .font(.caption)
                                        .foregroundStyle(.red)

                                    Button("Retry Repository Refresh") {
                                        Task { await store.refreshAll() }
                                    }
                                    .disabled(store.isRefreshing)
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(repository.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(
                                        "\(repository.modules.count) modules"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if store.isRefreshing {
                                    ProgressView()
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.removeRepository(repository)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Connected Repositories")
            }

            // MARK: Active Source

            Section {
                HStack {
                    Image(systemName: store.activeSourceSymbol)
                        .foregroundStyle(KinetiqPalette.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active Source")
                            .font(.subheadline.weight(.semibold))

                        Text(store.activeSourceTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if store.isLocalLibrarySelected {
                        Text("LOCAL")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(KinetiqPalette.accent)
                    }
                }

                Text(
                    "\(store.availableSources.count) selectable modules are available across your connected repositories."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Source Selection")
            } footer: {
                Text(
                    "Selecting a module changes the active source in Home. Supported video modules run through Kinetiq's JavaScript runtime, and resolved streams use Kinetiq's native player. Image and music modules are listed but are not supported yet."
                )
            }
        }
        .confirmationDialog(
            "Install all supported modules?",
            isPresented: $showingBatchConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingBatchRepositoryID,
               let repository = store.repositories.first(where: { $0.id == pendingBatchRepositoryID }) {
                Button("Install \(pendingCount(for: repository)) Modules") {
                    beginInstallAll(in: repository)
                }
            }
            Button("Cancel", role: .cancel) { pendingBatchRepositoryID = nil }
        } message: {
            Text("Kinetiq installs missing or outdated VIDEO modules one at a time. Every ZIP must match the repository SHA-256 and pass manifest/handler checks. Publisher signatures are NOT independently authenticated without a trusted publisher key and signing specification. Non-video modules are skipped. Keep Kinetiq open during installation.")
        }
        .alert("Repository Installation Report", isPresented: $showingBatchReport) {
            Button("Copy Report") {
                UIPasteboard.general.string = batchReport ?? ""
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(batchReport ?? "No installation report was recorded.")
        }
        .navigationTitle("Module Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.refreshAll()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(
                    store.repositories.isEmpty
                    || store.isRefreshing
                )
                .accessibilityLabel("Refresh repositories")
            }
        }
        .task {
            await store.loadSavedRepositoriesIfNeeded()
        }
        .refreshable {
            await store.refreshAll()
        }
    }

    // MARK: - Install All (supported modules only)

    private func installableSources(in repository: ModuleRepositoryRecord) -> [ModuleSourceOption] {
        store.sources(in: repository).filter { source in
            guard source.module.contentType?.lowercased() == "video",
                  source.packageURL != nil,
                  let hash = source.module.sha256 else { return false }
            return hash.count == 64 && hash.allSatisfy(\.isHexDigit)
        }
    }

    private func pendingCount(for repository: ModuleRepositoryRecord) -> Int {
        installableSources(in: repository).filter { !packageStore.isInstalled($0) }.count
    }

    @ViewBuilder
    private func batchControls(for repository: ModuleRepositoryRecord) -> some View {
        let total = installableSources(in: repository).count
        let pending = pendingCount(for: repository)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Repository Installer")
                        .font(.subheadline.weight(.semibold))
                    Text("\(pending) to install or update · \(total) supported video modules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if activeBatchRepositoryID == repository.id {
                    Button("Stop") {
                        // Cancellation is checked between packages. An in-flight
                        // URLSession download may finish before it takes effect.
                        batchTask?.cancel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else {
                    Button {
                        pendingBatchRepositoryID = repository.id
                        showingBatchConfirmation = true
                    } label: {
                        Label("Install All", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KinetiqPalette.accent)
                    .disabled(pending == 0 || activeBatchRepositoryID != nil || store.isRefreshing)
                }
            }
            if activeBatchRepositoryID == repository.id {
                ProgressView(value: Double(batchProcessed), total: Double(max(1, batchTotal)))
                Text("\(batchProcessed)/\(batchTotal) · \(batchCurrentModule)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(
                "SHA-256 package integrity is checked. Publisher authenticity is not independently verified.",
                systemImage: "checkmark.shield"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if total < repository.modules.count {
                Text("Unsupported, incomplete or non-video catalogue entries are not bulk-installed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    @MainActor
    private func beginInstallAll(in repository: ModuleRepositoryRecord) {
        guard activeBatchRepositoryID == nil else { return }
        let eligible = installableSources(in: repository)
        let pending = eligible.filter { !packageStore.isInstalled($0) }
        guard !pending.isEmpty else { return }

        batchInstalled = 0
        batchProcessed = 0
        batchSkipped = eligible.count - pending.count
        batchTotal = pending.count
        batchFailures = []
        batchCurrentModule = "Starting…"
        activeBatchRepositoryID = repository.id
        pendingBatchRepositoryID = nil

        batchTask = Task { @MainActor in
            for source in pending {
                if Task.isCancelled { break }
                batchCurrentModule = source.module.displayName
                // A user can install the same entry separately while bulk
                // installation is running; skip it rather than reinstall.
                if packageStore.isInstalled(source) {
                    batchSkipped += 1
                } else {
                    do {
                        try await packageStore.install(source)
                        batchInstalled += 1
                    } catch is CancellationError {
                        break
                    } catch {
                        let label = String(source.module.displayName.prefix(65))
                        let reason = String(error.localizedDescription.prefix(180))
                        batchFailures.append("\(label): \(reason)")
                    }
                }
                batchProcessed += 1
            }
            let interrupted = Task.isCancelled
            let summary = [
                "Repository: \(repository.name)",
                "Installed/updated: \(batchInstalled)",
                "Already installed/skipped: \(batchSkipped)",
                "Failed: \(batchFailures.count)",
                "Cancelled: \(interrupted ? "Yes" : "No")",
                "Security: HTTPS downloads, ZIP SHA-256 and manifest validation. Publisher signature unverified."
            ]
            batchReport = (summary + batchFailures.prefix(12)).joined(separator: "\n")
            batchTask = nil
            activeBatchRepositoryID = nil
            batchCurrentModule = ""
            showingBatchReport = true
        }
    }

    // MARK: Add Repository Action

    @MainActor
    private func addRepository() async {
        isAddingRepository = true
        errorMessage = nil

        defer {
            isAddingRepository = false
        }

        do {
            try await store.addRepository(from: repositoryURL)
            repositoryURL = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}