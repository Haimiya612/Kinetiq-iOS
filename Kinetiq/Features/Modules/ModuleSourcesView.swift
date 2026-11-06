import SwiftUI
import Foundation

// MARK: - Repository Models

struct ModuleRepositoryDocument: Decodable {
    let schemaVersion: Int?
    let repositoryId: String?
    let name: String?
    let enabled: Bool?
    let modules: [ModuleRepositoryModule]?
}

struct ModuleRepositoryPresentation: Decodable, Hashable {
    let category: String?
    let purpose: String?
    let language: String?
    let iconUrl: String?
}

struct ModuleRepositoryModule: Decodable, Hashable, Identifiable {
    let moduleId: String
    let contentType: String?
    let version: String?
    let minAppVersion: String?
    let packageUrl: String?
    let sha256: String?
    let signature: String?
    let presentation: ModuleRepositoryPresentation?

    var id: String {
        moduleId
    }

    var displayName: String {
        let packageFilename = packageUrl
            .flatMap { URL(string: $0)?.deletingPathExtension().lastPathComponent }

        let fallbackID = moduleId.replacingOccurrences(
            of: #"(?i)-v\d+(?:\.\d+)*$"#,
            with: "",
            options: .regularExpression
        )

        let rawName = (packageFilename?.isEmpty == false
            ? packageFilename
            : fallbackID) ?? moduleId

        let cleanedName = rawName.replacingOccurrences(
            of: #"(?i)[-_ ]v?\d+(?:\.\d+){0,3}$"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"([a-z])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"[-_]+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let key = cleanedName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        let canonicalNames: [String: String] = [
            "aniworld": "AniWorld",
            "anipm": "AniPM",
            "anikoto": "AniKoto",
            "anikage": "AniKage"
        ]

        if let canonicalName = canonicalNames[key] {
            return canonicalName
        }

        return cleanedName
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var displaySubtitle: String {
        [
            presentation?.category,
            presentation?.language,
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

    var displayType: String {
        (contentType ?? "Module").capitalized
    }
}

struct ModuleRepositoryRecord: Identifiable {
    let url: URL
    var repositoryId: String?
    var name: String
    var modules: [ModuleRepositoryModule]
    var lastRefreshed: Date?
    var refreshError: String?

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

    var title: String {
        module.displayName
    }

    var subtitle: String {
        module.displaySubtitle.isEmpty
            ? module.displayType
            : module.displaySubtitle
    }

    var symbol: String {
        switch module.contentType?.lowercased() {
        case "video":
            return "play.rectangle.fill"
        case "image":
            return "photo.fill"
        case "music":
            return "music.note"
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
        activeSource?.title ?? "Local Library"
    }

    var activeSourceSubtitle: String {
        guard let activeSource else {
            return "Personal media on this device"
        }

        return "\(activeSource.repositoryName) • \(activeSource.subtitle)"
    }

    var activeSourceSymbol: String {
        activeSource?.symbol ?? "iphone"
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
                        refreshError: error.localizedDescription
                    )
                )
            }
        }

        repositories = refreshedRepositories

        if
            !isLocalLibrarySelected,
            !availableSources.contains(where: {
                $0.id == selectedSourceID
            })
        {
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
            refreshError: nil
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
                if store.repositories.isEmpty {
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
                                Text(refreshError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
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