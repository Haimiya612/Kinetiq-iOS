import SwiftUI
import Foundation
import CryptoKit
import ZIPFoundation

// MARK: - Package Limits

private enum ModulePackageLimits {
    static let maximumArchiveBytes = 20 * 1024 * 1024
    static let maximumUncompressedBytes = 10 * 1024 * 1024
    static let maximumFileCount = 50
    static let maximumManifestBytes = 512 * 1024
    static let maximumJavaScriptBytes = 9 * 1024 * 1024
}

// MARK: - Installed Module Record

struct InstalledModuleRecord: Codable, Identifiable {
    let sourceID: String
    let repositoryURL: String
    let repositoryName: String
    let moduleID: String
    let name: String
    let version: String
    let contentType: String
    let packageSHA256: String
    let installedAt: Date
    let directoryPath: String
    let manifestPath: String
    let entryScriptPath: String

    var id: String {
        sourceID
    }

    var manifestURL: URL {
        URL(fileURLWithPath: manifestPath)
    }

    var entryScriptURL: URL {
        URL(fileURLWithPath: entryScriptPath)
    }
}

// MARK: - Manifest Models

private struct ModulePackageManifest: Decodable {
    let id: String?
    let moduleId: String?
    let name: String?
    let moduleName: String?
    let displayName: String?

    let contentType: String?
    let contractVersion: Int?
    let formatVersion: Int?

    let moduleVersion: String?
    let version: String?
    let releaseTrack: String?

    let moduleFamilyId: String?
    let moduleIdentity: String?
    let moduleIdentityNumber: Int?

    let scriptUrl: String?
    let config: ModulePackageConfiguration?
}

private struct ModulePackageConfiguration: Decodable {
    let runtime: ModulePackageRuntime?
    let caps: ModulePackageCaps?
    let baseUrl: String?
    let scriptUrl: String?
}

private struct ModulePackageRuntime: Decodable {
    let entry: String?
    let mode: String?
}

private struct ModulePackageCaps: Decodable {
    let homeMaxResults: Int?
    let maxResponseBytes: Int?
    let timeoutMs: Int?
    let maxConcurrentRequests: Int?
}

// MARK: - Validated Package

fileprivate struct ValidatedModulePackage {
    let manifestData: Data
    let scriptData: Data
    let name: String
    let version: String
    let contentType: String
}

// MARK: - Package Errors

enum ModulePackageError: LocalizedError {
    case missingPackageURL
    case invalidPackageURL
    case missingChecksum
    case invalidChecksum
    case downloadFailed
    case archiveTooLarge
    case checksumMismatch
    case invalidArchive
    case tooManyFiles
    case unsafeArchiveEntry
    case uncompressedDataTooLarge
    case invalidManifest(String)
    case unsupportedContentType
    case moduleIdentityMismatch
    case moduleVersionMismatch
    case missingRuntimeEntry
    case missingHandler(String)
    case installationFailed
    case alreadyInstalling

    var errorDescription: String? {
        switch self {
        case .missingPackageURL:
            return "This repository entry does not provide a module package URL."

        case .invalidPackageURL:
            return "The module package URL must be a valid HTTPS URL."

        case .missingChecksum:
            return "The repository does not provide a SHA-256 checksum."

        case .invalidChecksum:
            return "The repository's SHA-256 checksum is malformed."

        case .downloadFailed:
            return "The module package could not be downloaded."

        case .archiveTooLarge:
            return "The downloaded package exceeds Kinetiq's archive size limit."

        case .checksumMismatch:
            return "The downloaded package does not match the repository's SHA-256 checksum."

        case .invalidArchive:
            return "The downloaded file is not a valid module ZIP archive."

        case .tooManyFiles:
            return "The module archive contains too many files."

        case .unsafeArchiveEntry:
            return "The module archive contains an unsafe or unsupported ZIP entry."

        case .uncompressedDataTooLarge:
            return "The uncompressed module exceeds Kinetiq's size limit."

        case .invalidManifest(let reason):
            return "The module manifest is invalid: \(reason)"

        case .unsupportedContentType:
            return "This installation milestone supports video modules only."

        case .moduleIdentityMismatch:
            return "The package identity does not match the repository entry."

        case .moduleVersionMismatch:
            return "The package version does not match the repository entry."

        case .missingRuntimeEntry:
            return "The package does not contain its declared JavaScript entry point."

        case .missingHandler(let handler):
            return "The video module is missing the required handler: \(handler)."

        case .installationFailed:
            return "Kinetiq could not store the verified module package."

        case .alreadyInstalling:
            return "This module is already being installed."
        }
    }
}

// MARK: - Package Validator

enum ModulePackageValidator {

    fileprivate static func validateArchive(
        at archiveURL: URL,
        for source: ModuleSourceOption
    ) throws -> ValidatedModulePackage {
        let archive: Archive

        do {
            archive = try Archive(
                url: archiveURL,
                accessMode: .read,
                pathEncoding: .utf8
            )
        } catch {
            throw ModulePackageError.invalidArchive
        }

        let allEntries = Array(archive)
        let fileEntries = allEntries.filter {
            $0.type == .file
        }

        guard fileEntries.count <= ModulePackageLimits.maximumFileCount else {
            throw ModulePackageError.tooManyFiles
        }

        if allEntries.contains(where: { $0.type == .symlink }) {
            throw ModulePackageError.unsafeArchiveEntry
        }

        var totalUncompressedBytes: UInt64 = 0
        let maximumTotal = UInt64(
            ModulePackageLimits.maximumUncompressedBytes
        )

        for entry in allEntries {
            let path = entry.path

            if
                path.hasPrefix("/")
                || path.contains("\\")
                || path.split(separator: "/").contains("..")
            {
                throw ModulePackageError.unsafeArchiveEntry
            }

            guard entry.type == .file || entry.type == .directory else {
                throw ModulePackageError.unsafeArchiveEntry
            }

            if entry.type == .file {
                guard
                    entry.uncompressedSize <= maximumTotal,
                    totalUncompressedBytes <= maximumTotal - entry.uncompressedSize
                else {
                    throw ModulePackageError.uncompressedDataTooLarge
                }

                totalUncompressedBytes += entry.uncompressedSize
            }
        }

        let manifestEntries = fileEntries.filter {
            $0.path.lowercased().hasSuffix(".json")
        }

        guard manifestEntries.count == 1 else {
            throw ModulePackageError.invalidManifest(
                "Expected exactly one JSON manifest."
            )
        }

        let manifestData = try readEntry(
            manifestEntries[0],
            from: archive,
            maximumBytes: ModulePackageLimits.maximumManifestBytes
        )

        let manifest: ModulePackageManifest

        do {
            manifest = try JSONDecoder().decode(
                ModulePackageManifest.self,
                from: manifestData
            )
        } catch {
            throw ModulePackageError.invalidManifest(
                error.localizedDescription
            )
        }

        let validated = try validateManifest(
            manifest,
            source: source
        )

        guard
            let entryName = manifest.config?.runtime?.entry,
            !entryName.isEmpty,
            !entryName.hasPrefix("/"),
            !entryName.contains("\\"),
            !entryName.split(separator: "/").contains("..")
        else {
            throw ModulePackageError.missingRuntimeEntry
        }

        let scriptEntries = fileEntries.filter {
            $0.path.lowercased().hasSuffix(".js")
        }

        guard let scriptEntry = scriptEntries.first(where: {
            $0.path == entryName || $0.path.hasSuffix("/" + entryName)
        }) else {
            throw ModulePackageError.missingRuntimeEntry
        }

        let scriptData = try readEntry(
            scriptEntry,
            from: archive,
            maximumBytes: ModulePackageLimits.maximumJavaScriptBytes
        )

        guard let script = String(
            data: scriptData,
            encoding: .utf8
        ) else {
            throw ModulePackageError.invalidArchive
        }

        try validateVideoHandlers(in: script)

        return ValidatedModulePackage(
            manifestData: manifestData,
            scriptData: scriptData,
            name: validated.name,
            version: validated.version,
            contentType: validated.contentType
        )
    }

    private static func readEntry(
        _ entry: Entry,
        from archive: Archive,
        maximumBytes: Int
    ) throws -> Data {
        guard entry.uncompressedSize <= UInt64(maximumBytes) else {
            throw ModulePackageError.uncompressedDataTooLarge
        }

        var output = Data()

        do {
            _ = try archive.extract(
                entry,
                consumer: { chunk in
                    guard chunk.count <= maximumBytes - output.count else {
                        throw ModulePackageError.uncompressedDataTooLarge
                    }

                    output.append(chunk)
                }
            )
        } catch let error as ModulePackageError {
            throw error
        } catch {
            throw ModulePackageError.invalidArchive
        }

        return output
    }

    private static func validateManifest(
        _ manifest: ModulePackageManifest,
        source: ModuleSourceOption
    ) throws -> (
        name: String,
        version: String,
        contentType: String
    ) {
        guard
            let manifestID = manifest.id ?? manifest.moduleId,
            manifestID == source.module.moduleId
        else {
            throw ModulePackageError.moduleIdentityMismatch
        }

        guard
            let name = manifest.name
                ?? manifest.moduleName
                ?? manifest.displayName,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ModulePackageError.invalidManifest(
                "A module name is required."
            )
        }

        guard
            let contentType = manifest.contentType?.lowercased(),
            contentType == "video",
            source.module.contentType?.lowercased() == "video"
        else {
            throw ModulePackageError.unsupportedContentType
        }

        let contractVersion =
            manifest.contractVersion ?? manifest.formatVersion ?? 0

        guard contractVersion >= 3 else {
            throw ModulePackageError.invalidManifest(
                "The module must use contract version 3 or later."
            )
        }

        guard
            let releaseTrack = manifest.releaseTrack?.lowercased(),
            ["stable", "beta", "nightly"].contains(releaseTrack)
        else {
            throw ModulePackageError.invalidManifest(
                "A valid releaseTrack is required."
            )
        }

        guard
            let familyID = manifest.moduleFamilyId,
            !familyID.isEmpty,
            let identity = manifest.moduleIdentity,
            !identity.isEmpty,
            let identityNumber = manifest.moduleIdentityNumber,
            identityNumber > 0
        else {
            throw ModulePackageError.invalidManifest(
                "The module identity fields are incomplete."
            )
        }

        if let expectedFamilyID = source.module.moduleFamilyId,
           familyID != expectedFamilyID {
            throw ModulePackageError.moduleIdentityMismatch
        }

        if let expectedIdentity = source.module.moduleIdentity,
           identity != expectedIdentity {
            throw ModulePackageError.moduleIdentityMismatch
        }

        if let expectedIdentityNumber = source.module.moduleIdentityNumber,
           identityNumber != expectedIdentityNumber {
            throw ModulePackageError.moduleIdentityMismatch
        }

        guard
            manifest.scriptUrl == nil,
            manifest.config?.scriptUrl == nil
        else {
            throw ModulePackageError.invalidManifest(
                "Remote JavaScript entry points are not allowed."
            )
        }

        guard
            let runtime = manifest.config?.runtime,
            runtime.mode == "local",
            let entry = runtime.entry,
            entry == "index.js"
        else {
            throw ModulePackageError.invalidManifest(
                "The V3 runtime must declare a local index.js entry point."
            )
        }

        guard
            let baseURLString = manifest.config?.baseUrl,
            let baseURL = URL(string: baseURLString),
            baseURL.scheme?.lowercased() == "https",
            baseURL.host != nil
        else {
            throw ModulePackageError.invalidManifest(
                "A valid HTTPS baseUrl is required."
            )
        }

        guard let caps = manifest.config?.caps else {
            throw ModulePackageError.invalidManifest(
                "Runtime limits are missing."
            )
        }

        guard
            let timeout = caps.timeoutMs,
            (500...30_000).contains(timeout),
            let responseLimit = caps.maxResponseBytes,
            (1...8_000_000).contains(responseLimit),
            let homeLimit = caps.homeMaxResults,
            (1...100).contains(homeLimit),
            let concurrency = caps.maxConcurrentRequests,
            (1...12).contains(concurrency)
        else {
            throw ModulePackageError.invalidManifest(
                "One or more runtime limits are outside the supported range."
            )
        }

        guard
            let version = manifest.moduleVersion ?? manifest.version,
            !version.isEmpty
        else {
            throw ModulePackageError.invalidManifest(
                "A module version is required."
            )
        }

        if
            let repositoryVersion = source.module.version,
            repositoryVersion != version
        {
            throw ModulePackageError.moduleVersionMismatch
        }

        return (
            name: name,
            version: version,
            contentType: contentType
        )
    }

    private static func validateVideoHandlers(
        in source: String
    ) throws {
        let requiredHandlers = [
            "searchResults",
            "extractDetails",
            "extractEpisodes",
            "extractStreamUrl"
        ]

        for handler in requiredHandlers {
            let escaped = NSRegularExpression.escapedPattern(
                for: handler
            )

            let pattern =
                #"globalThis\.\#(escaped)\s*=\s*(?:async\s+)?(?:function|\(|[A-Za-z_$])"#

            guard source.range(
                of: pattern,
                options: .regularExpression
            ) != nil else {
                throw ModulePackageError.missingHandler(handler)
            }
        }
    }
}

// MARK: - Package Installer

actor ModulePackageInstaller {

    static let shared = ModulePackageInstaller()

    private let fileManager = FileManager.default

    private init() {}

    func install(
        source: ModuleSourceOption
    ) async throws -> InstalledModuleRecord {
        guard let packageURL = source.packageURL else {
            throw ModulePackageError.missingPackageURL
        }

        guard
            packageURL.scheme?.lowercased() == "https",
            packageURL.host != nil,
            packageURL.user == nil,
            packageURL.password == nil
        else {
            throw ModulePackageError.invalidPackageURL
        }

        guard let expectedChecksum = source.module.sha256 else {
            throw ModulePackageError.missingChecksum
        }

        let normalizedChecksum = expectedChecksum.lowercased()

        guard
            normalizedChecksum.count == 64,
            normalizedChecksum.allSatisfy({
                $0.isHexDigit
            })
        else {
            throw ModulePackageError.invalidChecksum
        }

        var request = URLRequest(url: packageURL)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/zip,application/octet-stream,*/*",
            forHTTPHeaderField: "Accept"
        )

        let downloadedURL: URL
        let response: URLResponse

        do {
            (downloadedURL, response) = try await URLSession.shared.download(
                for: request
            )
        } catch {
            throw ModulePackageError.downloadFailed
        }

        defer {
            try? fileManager.removeItem(at: downloadedURL)
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            httpResponse.url?.scheme?.lowercased() == "https"
        else {
            throw ModulePackageError.downloadFailed
        }

        let attributes = try fileManager.attributesOfItem(
            atPath: downloadedURL.path
        )

        let archiveSize =
            (attributes[.size] as? NSNumber)?.intValue ?? 0

        guard
            archiveSize > 0,
            archiveSize <= ModulePackageLimits.maximumArchiveBytes
        else {
            throw ModulePackageError.archiveTooLarge
        }

        let archiveData = try Data(contentsOf: downloadedURL)

        let actualChecksum = SHA256.hash(
            data: archiveData
        )
        .map {
            String(format: "%02x", $0)
        }
        .joined()

        guard actualChecksum == normalizedChecksum else {
            throw ModulePackageError.checksumMismatch
        }

        let validatedPackage = try ModulePackageValidator.validateArchive(
            at: downloadedURL,
            for: source
        )

        let rootURL = try modulesRootURL()
        let folderName = storageFolderName(for: source)
        let destinationURL = rootURL.appendingPathComponent(
            folderName,
            isDirectory: true
        )

        let stagingURL = rootURL.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true
        )

        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        let manifestURL = stagingURL.appendingPathComponent(
            "manifest.json"
        )

        let scriptURL = stagingURL.appendingPathComponent(
            "index.js"
        )

        try validatedPackage.manifestData.write(
            to: manifestURL,
            options: .atomic
        )

        try validatedPackage.scriptData.write(
            to: scriptURL,
            options: .atomic
        )

        let backupURL = rootURL.appendingPathComponent(
            ".backup-\(UUID().uuidString)",
            isDirectory: true
        )

        let hadPreviousInstallation = fileManager.fileExists(
            atPath: destinationURL.path
        )

        if hadPreviousInstallation {
            try fileManager.moveItem(
                at: destinationURL,
                to: backupURL
            )
        }

        do {
            try fileManager.moveItem(
                at: stagingURL,
                to: destinationURL
            )

            if hadPreviousInstallation {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if hadPreviousInstallation {
                try? fileManager.moveItem(
                    at: backupURL,
                    to: destinationURL
                )
            }

            throw ModulePackageError.installationFailed
        }

        return InstalledModuleRecord(
            sourceID: source.id,
            repositoryURL: source.repositoryURL.absoluteString,
            repositoryName: source.repositoryName,
            moduleID: source.module.moduleId,
            name: validatedPackage.name,
            version: validatedPackage.version,
            contentType: validatedPackage.contentType,
            packageSHA256: actualChecksum,
            installedAt: Date(),
            directoryPath: destinationURL.path,
            manifestPath: destinationURL
                .appendingPathComponent("manifest.json")
                .path,
            entryScriptPath: destinationURL
                .appendingPathComponent("index.js")
                .path
        )
    }

    private func modulesRootURL() throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ModulePackageError.installationFailed
        }

        let rootURL = applicationSupportURL
            .appendingPathComponent("Kinetiq", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)

        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        return rootURL
    }

    private func storageFolderName(
        for source: ModuleSourceOption
    ) -> String {
        SHA256.hash(
            data: Data(source.id.utf8)
        )
        .map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}

// MARK: - Installed Module Store

@MainActor
final class ModulePackageStore: ObservableObject {

    static let shared = ModulePackageStore()

    @Published private(set) var installedModules:
        [String: InstalledModuleRecord] = [:]

    @Published private(set) var installingSourceIDs: Set<String> = []

    private let fileManager = FileManager.default

    private init() {
        loadInstalledModules()
    }

    func installedModule(
        for source: ModuleSourceOption
    ) -> InstalledModuleRecord? {
        installedModules[source.id]
    }

    func isInstalled(
        _ source: ModuleSourceOption
    ) -> Bool {
        guard let record = installedModules[source.id] else {
            return false
        }

        return
            record.version == source.module.version
            && source.module.sha256?.lowercased()
                == record.packageSHA256.lowercased()
            && fileManager.fileExists(
                atPath: record.entryScriptPath
            )
            && fileManager.fileExists(
                atPath: record.manifestPath
            )
    }

    func isInstalling(
        _ source: ModuleSourceOption
    ) -> Bool {
        installingSourceIDs.contains(source.id)
    }

    func install(
        _ source: ModuleSourceOption
    ) async throws {
        guard !installingSourceIDs.contains(source.id) else {
            throw ModulePackageError.alreadyInstalling
        }

        installingSourceIDs.insert(source.id)

        defer {
            installingSourceIDs.remove(source.id)
        }

        let record = try await ModulePackageInstaller.shared.install(
            source: source
        )

        installedModules[source.id] = record

        try persistInstalledModules()
    }

    func uninstall(
        _ source: ModuleSourceOption
    ) throws {
        guard let record = installedModules[source.id] else {
            return
        }

        let directoryURL = URL(
            fileURLWithPath: record.directoryPath,
            isDirectory: true
        )

        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }

        installedModules.removeValue(forKey: source.id)

        try persistInstalledModules()
    }

    private func loadInstalledModules() {
        do {
            let indexURL = try installedIndexURL()

            guard fileManager.fileExists(atPath: indexURL.path) else {
                return
            }

            let data = try Data(contentsOf: indexURL)

            let records = try JSONDecoder().decode(
                [InstalledModuleRecord].self,
                from: data
            )

            installedModules = Dictionary(
                uniqueKeysWithValues: records.compactMap { record in
                    guard
                        fileManager.fileExists(
                            atPath: record.manifestPath
                        ),
                        fileManager.fileExists(
                            atPath: record.entryScriptPath
                        )
                    else {
                        return nil
                    }

                    return (record.sourceID, record)
                }
            )
        } catch {
            installedModules = [:]
        }
    }

    private func persistInstalledModules() throws {
        let indexURL = try installedIndexURL()

        let records = installedModules.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }

        let data = try JSONEncoder().encode(records)

        try data.write(
            to: indexURL,
            options: .atomic
        )
    }

    private func installedIndexURL() throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ModulePackageError.installationFailed
        }

        let rootURL = applicationSupportURL
            .appendingPathComponent("Kinetiq", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)

        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        return rootURL.appendingPathComponent(
            "installed-modules.json"
        )
    }
}

// MARK: - Repository Module Row

struct ModuleSourceListRow: View {

    let source: ModuleSourceOption
    let isSelected: Bool
    let onSelect: () -> Void

    @StateObject private var packageStore = ModulePackageStore.shared

    @State private var showingInstallConfirmation = false
    @State private var errorMessage: String?

    private var isVideoModule: Bool {
        source.module.contentType?.lowercased() == "video"
    }

    private var isInstalled: Bool {
        packageStore.isInstalled(source)
    }

    private var isInstalling: Bool {
        packageStore.isInstalling(source)
    }

    private var canInstall: Bool {
        isVideoModule
        && source.packageURL != nil
        && source.module.sha256 != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Group {
                        if let iconURL = source.iconURL {
                            AsyncImage(url: iconURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    Image(systemName: source.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(KinetiqPalette.accent)
                                }
                            }
                        } else {
                            Image(systemName: source.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(KinetiqPalette.accent)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .padding(5)
                    .background(
                        KinetiqPalette.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(source.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let purpose = source.module.displayPurpose {
                            Text(purpose)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        if source.module.presentation?.recommended == true {
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(KinetiqPalette.accent)
                        }
                    }

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(KinetiqPalette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isVideoModule {
                Button {
                    showingInstallConfirmation = true
                } label: {
                    Group {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                isInstalled ? "Verified" : "Install",
                                systemImage: isInstalled
                                    ? "checkmark.seal.fill"
                                    : "arrow.down.circle"
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(KinetiqPalette.accent)
                .disabled(!canInstall || isInstalling)
            } else {
                Text("Later")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            isInstalled
                ? "Re-verify \(source.title)?"
                : "Install \(source.title)?",
            isPresented: $showingInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                isInstalled
                    ? "Download and Verify Again"
                    : "Download and Verify"
            ) {
                Task {
                    await installPackage()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Kinetiq will download the module ZIP, verify its SHA-256 checksum, and inspect the manifest and required JavaScript handlers. The module's JavaScript will not execute during this installation step. Kinetiq cannot independently authenticate the publisher signature yet."
            )
        }
        .alert(
            "Module Installation",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "The package could not be installed.")
        }
    }

    @MainActor
    private func installPackage() async {
        do {
            try await packageStore.install(source)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}