import SwiftUI
import Foundation

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

struct ModuleRepositoryPresentation: Decodable, Hashable {
    let category: String?
    let purpose: String?
    let recommended: Bool?
    let language: String?
    let languages: [String]?
    let iconUrl: String?
}

struct ModuleRepositoryModule: Decodable, Hashable, Identifiable {
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

struct ModuleRepositoryRecord: Identifiable {
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

    @Published private(set) var repositories: [ModuleRepositoryRecord] = []

    @Published private(set) var selectedSourceID: String

    @Published private(set) var isRefreshing = false

    private var hasLoadedSavedRepositories = false

    private init() {
        selectedSourceID =
            UserDefaults.standard.string(forKey: Self.selectedSourceKey)
            ?? Self.localLibraryID
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
    }

    func addRepository(from rawValue: String) async throws {
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

        saveRepositoryURLs(
            savedURLs + [url.absoluteString]
        )
    }

    func removeRepository(_ repository: ModuleRepositoryRecord) {
        repositories.removeAll {
            $0.id == repository.id
        }

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

        repositories = refreshedRepositories

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