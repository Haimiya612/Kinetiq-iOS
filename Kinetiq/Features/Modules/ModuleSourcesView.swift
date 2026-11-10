import CryptoKit
import Foundation
import SwiftUI
import UIKit

// MARK: - Repository contract
// Replacement for the existing ModuleSourcesView.swift. Public names and source
// selection behavior remain compatible with the rest of Kinetiq 05J/05K.

struct ModuleRepositoryDocument: Decodable {
    let schemaVersion: Int?
    let repositoryId: String?
    let name: String?
    let enabled: Bool?
    let modules: [ModuleRepositoryModule]?
    let defaultModules: [String: String]?
    let defaultModulesSignature: String?
    let signature: String?
    // Optional Kinetiq-owned publisher signing contract. Legacy signatures
    // are not treated as authenticated without a documented signing scheme.
    let signatureVersion: String?
    let publisherKeyId: String?
    let publishedAtMs: Int64?
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

    var id: String { moduleId }

    private var identityNameKey: String {
        let components = (moduleIdentity ?? "").split(separator: "-")
        let suffix = components.count > 3 ? components.dropFirst(3).joined() : moduleId
        return suffix.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private var packageName: String? {
        guard let location = packageUrl ?? packagePath else { return nil }
        let filename = URL(string: location)?.lastPathComponent
            ?? URL(fileURLWithPath: location).lastPathComponent
        let bare = filename.replacingOccurrences(
            of: #"\.zip$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        let stripped = bare.replacingOccurrences(
            of: #"[-_ ]v?\d+(?:\.\d+){1,3}(?:-[A-Za-z0-9.-]+)?$"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    var displayName: String {
        // Keep upstream branding. Existing canonical names preserve previously
        // established Synthetiq UI aliases and are NOT rewritten by this batch.
        let names: [String: String] = [
            "synthetiqanime": "Synthetiq Anime", "animedirect": "Synthetiq Flux",
            "synthetiqone": "Synthetiq One", "anipm": "AniPM",
            "anikoto": "AniKoto", "anikage": "AniKage", "yflix": "YFlix",
            "dramacool": "DramaCool", "dramadirect": "Drama Direct",
            "onepace": "One Pace", "animeheaven": "AnimeHeaven",
            "xstream": "X-Stream", "miruro": "Miruro", "animesama": "Anime-Sama",
            "an1me": "An1me", "animeav1": "AnimeAV1", "kartoons": "Kartoons",
            "dramafun": "DramaFun", "toontales": "ToonTales",
            "aniworld": "AniWorld", "megakino": "MegaKino",
            "weebcentral": "WeebCentral", "synthetiqmanga": "Synthetiq Manga",
            "atsu": "Atsu", "synthetiqmusichub": "Synthetiq Music Hub",
            "animeunity": "AnimeUnity", "kickassanime": "KickAssAnime",
            "shahiid": "Shahiid", "mugiwara": "Mugiwara",
            "justanime": "JustAnime", "streamingunity": "StreamingUnity",
            "mangakatana": "MangaKatana", "mgreadlikemanga": "MGRead Like Manga",
            "colorizedmanga": "ColorizedManga", "alphamovies": "Alpha Movies",
            "moviedb": "MovieDB", "cimaclub": "CimaClub", "anime4up": "Anime4up"
        ]
        if let known = names[identityNameKey] { return known }
        if let packageName { return packageName.replacingOccurrences(of: "_", with: " ") }
        return moduleId.replacingOccurrences(
            of: #"(?i)-v\d+(?:\.\d+)*$"#, with: "", options: .regularExpression
        )
    }

    var displaySubtitle: String {
        let modes = presentation?.languages?.map { $0.uppercased() }.joined(separator: " / ")
        return [presentation?.category, presentation?.language, modes, version.map { "v\($0)" }]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }.joined(separator: " • ")
    }
    var displayPurpose: String? {
        let value = presentation?.purpose?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
    var displayType: String { (contentType ?? "Module").capitalized }
    var publishedDate: Date? {
        publishedAtMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
    }

    // This identity is pinned at the REPOSITORY level. Adding a new module does
    // not require a new prompt, but replacing an existing identity does.
    var stablePublisherIdentity: String {
        [moduleId, moduleFamilyId ?? "", moduleIdentity ?? "",
         moduleIdentityNumber.map(String.init) ?? ""].joined(separator: "|")
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
    var signatureVersion: String? = nil
    var publisherKeyId: String? = nil
    var publishedAtMs: Int64? = nil
    var independentlyVerified: Bool? = nil

    var id: String { url.absoluteString }
}

struct ModuleSourceOption: Identifiable {
    let repositoryURL: URL
    let repositoryName: String
    let module: ModuleRepositoryModule

    var id: String { "\(repositoryURL.absoluteString)|\(module.moduleId)" }

    @MainActor var title: String {
        if let installed = ModulePackageStore.shared.installedModule(for: self),
           installed.version == module.version,
           let hash = module.sha256,
           installed.packageSHA256.lowercased() == hash.lowercased() {
            return installed.name
        }
        return module.displayName
    }
    var subtitle: String { module.displaySubtitle.isEmpty ? module.displayType : module.displaySubtitle }

    var packageURL: URL? {
        if let raw = module.packageUrl, let url = URL(string: raw),
           KinetiqRepositorySecurity.isPublicHTTPS(url) { return url }
        guard let path = module.packagePath else { return nil }
        if let url = URL(string: path), KinetiqRepositorySecurity.isPublicHTTPS(url) {
            return url
        }
        if repositoryURL.host?.lowercased() == "raw.githubusercontent.com",
           path.hasPrefix("/") {
            var components = URLComponents(url: repositoryURL, resolvingAgainstBaseURL: false)
            components?.host = "github.com"
            components?.path = path
            components?.query = nil
            components?.fragment = nil
            if let url = components?.url, KinetiqRepositorySecurity.isPublicHTTPS(url) {
                return url
            }
        }
        if let url = URL(string: path, relativeTo: repositoryURL)?.absoluteURL,
           KinetiqRepositorySecurity.isPublicHTTPS(url) { return url }
        return nil
    }

    var iconURL: URL? {
        guard let raw = module.presentation?.iconUrl, let url = URL(string: raw),
              KinetiqRepositorySecurity.isPublicHTTPS(url) else { return nil }
        return url
    }
    var symbol: String {
        switch module.contentType?.lowercased() {
        case "video": return "play.rectangle.fill"
        case "image": return "photo.fill"
        case "music": return "music.note"
        case "text": return "doc.text.fill"
        default: return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Repository origin and release validation (05M/05N)

enum KinetiqRepositorySecurity {
    // URL guard covers literal private addresses and local-looking hostnames.
    // It cannot eliminate DNS rebinding. The JS runtime and package downloader
    // require independent egress/redirect policy hardening in 05M.
    static func isPublicHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty,
              url.port == nil || url.port == 443 else { return false }
        let plainHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !plainHost.hasSuffix("."), !plainHost.hasSuffix(".local"),
              !plainHost.hasSuffix(".internal"), !plainHost.hasSuffix(".localhost"),
              plainHost != "localhost", !plainHost.hasSuffix(".test"),
              plainHost != "0", plainHost != "::", plainHost != "::1" else { return false }
        if plainHost.contains(":") {
            // Reject all literal IPv6 addresses (including mapped IPv4) for
            // repository and package URLs; legitimate DNS names remain valid.
            return false
        }
        if plainHost.allSatisfy({ $0.isNumber || $0 == "." }) {
            let octets = plainHost.split(separator: ".", omittingEmptySubsequences: false)
            let values = octets.compactMap { UInt8($0) }
            guard octets.count == 4, values.count == 4 else { return false }
            let a = values[0], b = values[1]
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(Int(b)) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(Int(b)) { return false }
            if a == 198 && (b == 18 || b == 19) { return false }
            if a == 192 && b == 0 { return false }
            return true
        }
        return plainHost.contains(".") && !plainHost.contains(" ")
    }

    static func isSamePublisherScope(initial: URL, redirected: URL) -> Bool {
        guard isPublicHTTPS(initial), isPublicHTTPS(redirected),
              initial.host?.lowercased() == redirected.host?.lowercased() else {
            return false
        }
        if initial.host?.lowercased() == "raw.githubusercontent.com" {
            let a = initial.path.split(separator: "/")
            let b = redirected.path.split(separator: "/")
            return a.count >= 4 && b.count >= 4 &&
                a[0] == b[0] && a[1] == b[1]
        }
        return true
    }

    static func sameVersionMutation(installedVersion: String, installedSHA: String,
                                    listedVersion: String, listedSHA: String) -> Bool {
        installedVersion == listedVersion && installedSHA.lowercased() != listedSHA.lowercased()
    }

    static func isValidSHA(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    static func expectedIdentityIsStable(_ previous: String, _ current: String) -> Bool {
        previous == current
    }
}

private final class KinetiqRepositoryRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let approvedURL: URL
    init(approvedURL: URL) { self.approvedURL = approvedURL }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let target = request.url,
           KinetiqRepositorySecurity.isSamePublisherScope(initial: approvedURL,
                                                           redirected: target) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

// MARK: - Publisher trust policy (05L)

enum KinetiqRepositoryTrust: String {
    case verifiedPublisher = "Verified publisher"
    case communityApproved = "Trusted repository"
    case approvalNeeded = "Approval needed"
    case changedPublisher = "Publisher changed"
    case invalidSignature = "Invalid publisher signature"
    case offline = "Repository unavailable"

    var allowsInstall: Bool { self == .verifiedPublisher || self == .communityApproved }
    var symbol: String {
        switch self {
        case .verifiedPublisher: return "checkmark.seal.fill"
        case .communityApproved: return "checkmark.shield.fill"
        case .approvalNeeded: return "hand.raised.fill"
        case .changedPublisher: return "exclamationmark.shield.fill"
        case .invalidSignature: return "xmark.shield.fill"
        case .offline: return "wifi.slash"
        }
    }
}

struct KinetiqRepositoryApproval: Codable {
    let repositoryURL: String
    let repositoryID: String
    let acceptedAt: Date
    let knownIdentities: [String: String]
    let acceptedSignatureVersion: String?
    let acceptedPublisherKeyID: String?
}

// Strict, explicitly versioned signing format for future Kinetiq publishers.
// No public keys are fabricated: external/legacy signatures remain unverified
// until the publisher's authentic key and canonical format are independently
// established and added to this release.
enum KinetiqPublisherSignature {
    static let scheme = "kinetiq-p256-v1"
    static let independentlyPinnedKeys: [String: Data] = [:]

    static func canonicalMessage(repositoryID: String, issuedAtMs: Int64,
                                 modules: [ModuleRepositoryModule]) -> Data {
        var lines = [scheme, repositoryID, String(issuedAtMs)]
        for module in modules.sorted(by: { $0.moduleId < $1.moduleId }) {
            let number = module.moduleIdentityNumber.map { String($0) } ?? ""
            let listedSHA = module.sha256?.lowercased() ?? ""
            let packageLocation = module.packageUrl ?? module.packagePath ?? ""
            let fields: [String] = [
                module.moduleId, module.moduleFamilyId ?? "", module.moduleIdentity ?? "",
                number, module.version ?? "", listedSHA, packageLocation
            ]
            // Byte-length framing prevents delimiter/newline ambiguity in signatures.
            let encoded = fields.map { "\($0.utf8.count):\($0)" }.joined()
            lines.append(encoded)
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func verify(signatureBase64: String, message: Data, publicKey: Data) -> Bool {
        guard let bytes = Data(base64Encoded: signatureBase64), bytes.count == 64,
              signatureBase64 == bytes.base64EncodedString(),
              let key = try? P256.Signing.PublicKey(rawRepresentation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: bytes)
        else { return false }
        return key.isValidSignature(signature, for: message)
    }

    static func recognizedSignatureIsWellFormed(_ record: ModuleRepositoryRecord) -> Bool {
        guard record.signatureVersion == scheme else { return true }
        guard let keyID = record.publisherKeyId, !keyID.isEmpty,
              let repositoryID = record.repositoryId, !repositoryID.isEmpty,
              let issued = record.publishedAtMs, issued > 0,
              let encoded = record.signature,
              let decoded = Data(base64Encoded: encoded), decoded.count == 64,
              encoded == decoded.base64EncodedString() else {
            return false
        }
        return true
    }

    static func signedState(for record: ModuleRepositoryRecord) -> Bool? {
        guard record.signatureVersion == scheme else { return nil }
        guard recognizedSignatureIsWellFormed(record) else { return false }
        guard let keyID = record.publisherKeyId,
              let publicKey = independentlyPinnedKeys[keyID],
              let signature = record.signature,
              let issued = record.publishedAtMs,
              let repoID = record.repositoryId else { return nil }
        return verify(signatureBase64: signature,
                      message: canonicalMessage(repositoryID: repoID,
                                                issuedAtMs: issued,
                                                modules: record.modules),
                      publicKey: publicKey)
    }
}

@MainActor
final class KinetiqRepositoryTrustStore: ObservableObject {
    static let shared = KinetiqRepositoryTrustStore()
    @Published private(set) var approvals: [String: KinetiqRepositoryApproval] = [:]
    private static let key = "kinetiq.modules.approvedRepositories.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: KinetiqRepositoryApproval].self, from: data) {
            approvals = decoded
        }
    }

    func trust(for repository: ModuleRepositoryRecord) -> KinetiqRepositoryTrust {
        if repository.refreshError != nil { return .offline }
        guard KinetiqPublisherSignature.recognizedSignatureIsWellFormed(repository) else {
            return .invalidSignature
        }
        if let signed = KinetiqPublisherSignature.signedState(for: repository) {
            return signed ? .verifiedPublisher : .invalidSignature
        }
        guard let previous = approvals[repository.url.absoluteString] else {
            return .approvalNeeded
        }
        if previous.repositoryID != stableID(repository)
            || previous.acceptedSignatureVersion != repository.signatureVersion
            || previous.acceptedPublisherKeyID != repository.publisherKeyId {
            return .changedPublisher
        }
        for item in repository.modules {
            if let previousIdentity = previous.knownIdentities[item.moduleId],
               !KinetiqRepositorySecurity.expectedIdentityIsStable(previousIdentity,
                                                                    item.stablePublisherIdentity) {
                return .changedPublisher
            }
        }
        return .communityApproved
    }

    // Offline operation can continue for an already approved module whose
    // saved source identity still matches. Never approve NEW modules offline.
    func allowsRuntime(for repository: ModuleRepositoryRecord,
                       installedModuleID: String) -> Bool {
        let state = trust(for: repository)
        if state.allowsInstall { return true }
        guard state == .offline,
              let accepted = approvals[repository.url.absoluteString],
              accepted.repositoryID == stableID(repository),
              let pinnedIdentity = accepted.knownIdentities[installedModuleID],
              let current = repository.modules.first(where: { $0.moduleId == installedModuleID })
        else { return false }
        return pinnedIdentity == current.stablePublisherIdentity
    }

    // One user approval authorizes all video sources belonging to this exact
    // repository, including later additions while its publisher identity stays
    // stable. It does NOT skip SHA-256, manifest checks or signature validation.
    // Existing approvals are persisted and shared with ModuleBrowserView.
    @discardableResult
    func approveAllSources(in repository: ModuleRepositoryRecord) -> Bool {
        guard repository.refreshError == nil,
              KinetiqPublisherSignature.recognizedSignatureIsWellFormed(repository),
              KinetiqPublisherSignature.signedState(for: repository) != false else {
            return false
        }
        var identities: [String: String] = [:]
        for module in repository.modules {
            guard identities[module.moduleId] == nil else { return false }
            identities[module.moduleId] = module.stablePublisherIdentity
        }
        approvals[repository.url.absoluteString] = KinetiqRepositoryApproval(
            repositoryURL: repository.url.absoluteString,
            repositoryID: stableID(repository), acceptedAt: Date(),
            knownIdentities: identities,
            acceptedSignatureVersion: repository.signatureVersion,
            acceptedPublisherKeyID: repository.publisherKeyId
        )
        persist()
        return true
    }

    // Compatibility with existing browser approval call sites.
    func approve(_ repository: ModuleRepositoryRecord) {
        _ = approveAllSources(in: repository)
    }

    func revoke(_ repository: ModuleRepositoryRecord) {
        approvals.removeValue(forKey: repository.url.absoluteString)
        persist()
    }

    private func stableID(_ repository: ModuleRepositoryRecord) -> String {
        // Bind approval to the complete repository URL AND its declared ID.
        // An unchanged URL whose repo identity changes must be re-approved.
        repository.repositoryId ?? "(legacy-no-repository-id)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(approvals), data.count <= 1_000_000 else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - Module update/certification summary (05N/05O)

enum KinetiqModuleReleaseState: String {
    case notInstalled = "Not installed"
    case current = "Current"
    case updateAvailable = "Update available"
    case sameVersionMutation = "Version reused with different ZIP"
    case downgrade = "Older release"
    case incomplete = "Invalid package listing"

    var permitsAutomaticInstall: Bool {
        self == .notInstalled || self == .updateAvailable
    }
}

enum KinetiqModuleReleasePolicy {
    static func status(listedVersion: String?, listedSHA: String?,
                       installedVersion: String?, installedSHA: String?) -> KinetiqModuleReleaseState {
        guard let listedVersion, !listedVersion.isEmpty,
              KinetiqRepositorySecurity.isValidSHA(listedSHA), let listedSHA
        else { return .incomplete }
        guard let installedVersion, let installedSHA else { return .notInstalled }
        if installedVersion == listedVersion {
            return installedSHA.lowercased() == listedSHA.lowercased()
                ? .current : .sameVersionMutation
        }
        // Numeric component comparisons prevent lexical 1.10 < 1.9 mistakes.
        // For prereleases Swift remains conservative; uncertain ordering is
        // handled as an update requiring repository approval, not silent rollback.
        guard let cmp = compareVersions(installedVersion, listedVersion) else {
            return .incomplete // unknown version ordering: never silently downgrade
        }
        return cmp == .orderedDescending ? .downgrade : .updateAvailable
    }

    static func compareVersions(_ left: String, _ right: String) -> ComparisonResult? {
        func parsed(_ version: String) -> ([Int], [String])? {
            var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("v") { text.removeFirst() }
            let noBuild = String(text.prefix(while: { $0 != "+" }))
            let split = noBuild.split(separator: "-", maxSplits: 1,
                                      omittingEmptySubsequences: false)
            guard let core = split.first else { return nil }
            let components = core.split(separator: ".")
            guard !components.isEmpty, components.count <= 6 else { return nil }
            let numbers = components.compactMap { Int($0) }
            guard numbers.count == components.count else { return nil }
            let pre = split.count > 1 ? split[1].split(separator: ".").map(String.init) : []
            return (numbers, pre)
        }
        guard let (a, ap) = parsed(left), let (b, bp) = parsed(right) else { return nil }
        for index in 0..<max(a.count, b.count) {
            let av = index < a.count ? a[index] : 0
            let bv = index < b.count ? b[index] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        if ap.isEmpty && bp.isEmpty { return .orderedSame }
        if ap.isEmpty { return .orderedDescending }
        if bp.isEmpty { return .orderedAscending }
        for index in 0..<min(ap.count, bp.count) {
            if ap[index] == bp[index] { continue }
            let ai = Int(ap[index]), bi = Int(bp[index])
            if let ai, let bi {
                return ai < bi ? .orderedAscending : .orderedDescending
            }
            if ai != nil { return .orderedAscending }
            if bi != nil { return .orderedDescending }
            return ap[index] < bp[index] ? .orderedAscending : .orderedDescending
        }
        if ap.count == bp.count { return .orderedSame }
        return ap.count < bp.count ? .orderedAscending : .orderedDescending
    }
}

// MARK: - Evidence-based module resolution health (05O)

struct KinetiqModuleHealthEntry: Codable {
    var lastVersion: String
    var lastPackagePrefix: String
    var successes: Int
    var failures: Int
    var lastFailureCode: String?
    var lastResolutionAt: Date?
    var lastFailureAt: Date?
}

@MainActor
final class KinetiqModuleHealthStore: ObservableObject {
    static let shared = KinetiqModuleHealthStore()
    private static let storageKey = "kinetiq.modules.resolutionHealth.v1"
    @Published private(set) var entries: [String: KinetiqModuleHealthEntry] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           data.count <= 200_000,
           let decoded = try? JSONDecoder().decode([String: KinetiqModuleHealthEntry].self,
                                                   from: data) {
            entries = decoded
        }
    }

    // Never persist a full source URL (which might include credentials).
    static func anonymousKey(for sourceID: String) -> String {
        SHA256.hash(data: Data(sourceID.utf8))
            .prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func status(for source: ModuleSourceOption,
                installed: InstalledModuleRecord?) -> String {
        guard let installed,
              let item = entries[Self.anonymousKey(for: source.id)],
              installed.version == item.lastVersion,
              installed.packageSHA256.hasPrefix(item.lastPackagePrefix) else {
            return "Unverified on this build"
        }
        if let resolved = item.lastResolutionAt,
           item.lastFailureAt == nil || resolved > item.lastFailureAt! {
            return "Stream resolved (player not certified)"
        }
        if item.lastFailureAt != nil {
            return "Stream resolution failed: \(item.lastFailureCode ?? "UNKNOWN")"
        }
        return "No recent resolution result"
    }

    func record(sourceID: String?, version: String, packagePrefix: String,
                succeeded: Bool, failureCode: String? = nil) {
        guard let sourceID, !sourceID.isEmpty, !version.isEmpty,
              !packagePrefix.isEmpty else { return }
        let key = Self.anonymousKey(for: sourceID)
        var entry = entries[key] ?? KinetiqModuleHealthEntry(
            lastVersion: version, lastPackagePrefix: packagePrefix,
            successes: 0, failures: 0, lastFailureCode: nil,
            lastResolutionAt: nil, lastFailureAt: nil)
        if entry.lastVersion != version || entry.lastPackagePrefix != packagePrefix {
            entry = KinetiqModuleHealthEntry(
                lastVersion: version, lastPackagePrefix: packagePrefix,
                successes: 0, failures: 0, lastFailureCode: nil,
                lastResolutionAt: nil, lastFailureAt: nil)
        }
        if succeeded {
            entry.successes = min(10_000, entry.successes + 1)
            entry.lastResolutionAt = Date()
        } else {
            entry.failures = min(10_000, entry.failures + 1)
            let raw = failureCode ?? "UNKNOWN"
            entry.lastFailureCode = String(raw.uppercased()
                .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
                .prefix(40))
            entry.lastFailureAt = Date()
        }
        entries[key] = entry
        if entries.count > 150 {
            // Remove oldest evidence. No raw URLs, tokens or media links saved.
            let oldest = entries.min {
                let a = $0.value.lastResolutionAt ?? $0.value.lastFailureAt ?? .distantPast
                let b = $1.value.lastResolutionAt ?? $1.value.lastFailureAt ?? .distantPast
                return a < b
            }?.key
            if let oldest { entries.removeValue(forKey: oldest) }
        }
        if let data = try? JSONEncoder().encode(entries), data.count <= 200_000 {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Repository errors

private enum ModuleRepositoryError: LocalizedError {
    case invalidURL, duplicate, operationInProgress, invalidResponse, responseTooLarge
    case invalidDocument, disabledRepository, duplicateModuleIDs, unsafeRedirect
    case unsupportedSchema(Int), invalidSignature

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a public HTTPS repository.json URL."
        case .duplicate: return "This repository has already been added."
        case .operationInProgress: return "A repository operation is already running."
        case .invalidResponse: return "The repository server did not return HTTP 200."
        case .responseTooLarge: return "The repository exceeds the 8 MB response limit."
        case .invalidDocument: return "This is not a valid module repository JSON file."
        case .disabledRepository: return "This repository is disabled."
        case .duplicateModuleIDs: return "The repository lists duplicate module IDs."
        case .unsafeRedirect: return "The repository redirected to an unsafe or non-HTTPS URL."
        case .unsupportedSchema(let version): return "Repository schema \(version) is unsupported."
        case .invalidSignature: return "The independently pinned publisher signature is invalid."
        }
    }
}

// MARK: - Shared source store; existing API preserved

@MainActor
final class ModuleSourceStore: ObservableObject {
    static let shared = ModuleSourceStore()
    static let localLibraryID = "kinetiq.local-library"
    static let synthetiqRepositoryURL =
        "https://raw.githubusercontent.com/kas021/Synthetiq-Modules/main/repository.json"

    private static let repositoriesKey = "kinetiq.modules.repositoryURLs"
    private static let selectedSourceKey = "kinetiq.modules.selectedSource"
    private static let repositoryCacheKey = "kinetiq.modules.repositoryCache.v1"
    private static let maximumCacheBytes = 2_000_000

    @Published private(set) var repositories: [ModuleRepositoryRecord] = []
    @Published private(set) var selectedSourceID: String
    @Published private(set) var isRefreshing = false
    private var hasLoadedSavedRepositories = false

    private init() {
        selectedSourceID = UserDefaults.standard.string(forKey: Self.selectedSourceKey)
            ?? Self.localLibraryID
        if let data = UserDefaults.standard.data(forKey: Self.repositoryCacheKey),
           data.count <= Self.maximumCacheBytes,
           let cached = try? JSONDecoder().decode([ModuleRepositoryRecord].self, from: data) {
            let urls = Set(UserDefaults.standard.stringArray(forKey: Self.repositoriesKey) ?? [])
            repositories = cached.filter { urls.contains($0.url.absoluteString) }
        }
    }

    var availableSources: [ModuleSourceOption] { repositories.flatMap { sources(in: $0) } }
    var activeSource: ModuleSourceOption? { availableSources.first { $0.id == selectedSourceID } }
    var isLocalLibrarySelected: Bool { selectedSourceID == Self.localLibraryID }
    var activeSourceTitle: String {
        isLocalLibrarySelected ? "Local Library" : (activeSource?.title ?? "Source Unavailable")
    }
    var activeSourceSubtitle: String {
        guard let activeSource else {
            return isLocalLibrarySelected ? "Personal media on this device" : "Refresh repositories to reconnect"
        }
        return "\(activeSource.repositoryName) • \(activeSource.subtitle)"
    }
    var activeSourceSymbol: String {
        activeSource?.symbol ?? (isLocalLibrarySelected ? "iphone" : "exclamationmark.triangle")
    }

    func sources(in repository: ModuleRepositoryRecord) -> [ModuleSourceOption] {
        repository.modules.map { ModuleSourceOption(repositoryURL: repository.url,
                                                    repositoryName: repository.name, module: $0) }
    }
    func isSelected(_ sourceID: String) -> Bool { selectedSourceID == sourceID }
    func selectSource(_ sourceID: String) {
        guard sourceID == Self.localLibraryID || availableSources.contains(where: { $0.id == sourceID })
        else { return }
        selectedSourceID = sourceID
        UserDefaults.standard.set(sourceID, forKey: Self.selectedSourceKey)
    }
    func selectLocalLibrary() { selectSource(Self.localLibraryID) }

    func loadSavedRepositoriesIfNeeded() async {
        guard !hasLoadedSavedRepositories else { return }
        hasLoadedSavedRepositories = true
        await refreshAll()
        if Task.isCancelled { hasLoadedSavedRepositories = false }
    }

    func addRepository(from rawValue: String) async throws {
        guard !isRefreshing else { throw ModuleRepositoryError.operationInProgress }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), KinetiqRepositorySecurity.isPublicHTTPS(url)
        else { throw ModuleRepositoryError.invalidURL }
        let saved = UserDefaults.standard.stringArray(forKey: Self.repositoriesKey) ?? []
        guard !saved.contains(url.absoluteString), !repositories.contains(where: { $0.url == url })
        else { throw ModuleRepositoryError.duplicate }
        isRefreshing = true
        defer { isRefreshing = false }
        let repository = try await fetchRepository(from: url)
        repositories.append(repository)
        persistCache()
        UserDefaults.standard.set(saved + [url.absoluteString], forKey: Self.repositoriesKey)
    }

    func removeRepository(_ repository: ModuleRepositoryRecord) {
        repositories.removeAll { $0.id == repository.id }
        persistCache()
        let saved = UserDefaults.standard.stringArray(forKey: Self.repositoriesKey) ?? []
        UserDefaults.standard.set(saved.filter { $0 != repository.url.absoluteString },
                                  forKey: Self.repositoriesKey)
        // Keep trust records until the user explicitly revokes them. A removed
        // repo cannot install anything, but re-adding the SAME identity won't
        // demand an unnecessary new prompt.
        if selectedSourceID.hasPrefix(repository.url.absoluteString + "|") {
            selectLocalLibrary()
        }
    }

    static func selectionBelongsToFailedRepository(_ selectedID: String,
                                                    in repositories: [ModuleRepositoryRecord]) -> Bool {
        guard selectedID != localLibraryID else { return false }
        return repositories.contains { $0.refreshError != nil && selectedID.hasPrefix($0.url.absoluteString + "|") }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        let saved = UserDefaults.standard.stringArray(forKey: Self.repositoriesKey) ?? []
        isRefreshing = true
        defer { isRefreshing = false }
        var newRecords: [ModuleRepositoryRecord] = []
        for raw in saved {
            guard let url = URL(string: raw) else { continue }
            do {
                let fresh = try await fetchRepository(from: url)
                guard !Task.isCancelled else { return }
                newRecords.append(fresh)
            } catch {
                let previous = repositories.first { $0.url == url }
                newRecords.append(ModuleRepositoryRecord(
                    url: url, repositoryId: previous?.repositoryId,
                    name: previous?.name ?? (url.host ?? "Repository"),
                    modules: previous?.modules ?? [], lastRefreshed: previous?.lastRefreshed,
                    refreshError: error.localizedDescription,
                    schemaVersion: previous?.schemaVersion, enabled: previous?.enabled,
                    defaultModules: previous?.defaultModules,
                    defaultModulesSignature: previous?.defaultModulesSignature,
                    signature: previous?.signature,
                    signatureVersion: previous?.signatureVersion,
                    publisherKeyId: previous?.publisherKeyId,
                    publishedAtMs: previous?.publishedAtMs,
                    independentlyVerified: previous?.independentlyVerified
                ))
            }
        }
        guard !Task.isCancelled else { return }
        repositories = newRecords
        persistCache()
        if !isLocalLibrarySelected,
           !availableSources.contains(where: { $0.id == selectedSourceID }),
           !Self.selectionBelongsToFailedRepository(selectedSourceID, in: newRecords) {
            selectLocalLibrary()
        }
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(repositories),
              data.count <= Self.maximumCacheBytes else { return }
        UserDefaults.standard.set(data, forKey: Self.repositoryCacheKey)
    }

    private func fetchRepository(from url: URL) async throws -> ModuleRepositoryRecord {
        guard KinetiqRepositorySecurity.isPublicHTTPS(url) else {
            throw ModuleRepositoryError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration,
                                 delegate: KinetiqRepositoryRedirectGuard(approvedURL: url), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200
        else { throw ModuleRepositoryError.invalidResponse }
        guard let finalURL = http.url,
              KinetiqRepositorySecurity.isSamePublisherScope(initial: url, redirected: finalURL)
        else { throw ModuleRepositoryError.unsafeRedirect }
        guard data.count <= 8_000_000 else { throw ModuleRepositoryError.responseTooLarge }
        let document = try JSONDecoder().decode(ModuleRepositoryDocument.self, from: data)
        if let schema = document.schemaVersion, schema != 1 {
            throw ModuleRepositoryError.unsupportedSchema(schema)
        }
        guard document.enabled != false else { throw ModuleRepositoryError.disabledRepository }
        guard let modules = document.modules else { throw ModuleRepositoryError.invalidDocument }
        let ids = modules.map(\.moduleId)
        guard Set(ids).count == ids.count,
              ids.allSatisfy({ id in
                  !id.isEmpty && id.count <= 200 &&
                  !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }) else { throw ModuleRepositoryError.duplicateModuleIDs }
        let name = document.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = ModuleRepositoryRecord(
            url: url, repositoryId: document.repositoryId,
            name: name?.isEmpty == false ? name! : (url.host ?? "Module Repository"),
            modules: modules, lastRefreshed: Date(), refreshError: nil,
            schemaVersion: document.schemaVersion, enabled: document.enabled,
            defaultModules: document.defaultModules,
            defaultModulesSignature: document.defaultModulesSignature,
            signature: document.signature,
            signatureVersion: document.signatureVersion,
            publisherKeyId: document.publisherKeyId,
            publishedAtMs: document.publishedAtMs,
            independentlyVerified: nil
        )
        // Fail closed ONLY when we know and trust the publisher's actual key.
        // Do not reinterpret the legacy Synthetiq signature as our format.
        guard KinetiqPublisherSignature.recognizedSignatureIsWellFormed(record),
              KinetiqPublisherSignature.signedState(for: record) != false else {
            throw ModuleRepositoryError.invalidSignature
        }
        return record
    }
}

// MARK: - Module sources UI (one approval per repository, not per module)

struct ModuleSourcesView: View {
    @StateObject private var store = ModuleSourceStore.shared
    @StateObject private var packageStore = ModulePackageStore.shared
    @StateObject private var trustStore = KinetiqRepositoryTrustStore.shared
    @StateObject private var healthStore = KinetiqModuleHealthStore.shared
    @StateObject private var updateCenter = KinetiqModuleUpdateCenterStore.shared
    @State private var showingUpdateCenter = false

    @State private var repositoryURL = ModuleSourceStore.synthetiqRepositoryURL
    @State private var adding = false
    @State private var errorMessage: String?
    @State private var trustTarget: String?
    @State private var showingTrustConfirmation = false
    @State private var batchTarget: String?
    @State private var showingBatchConfirmation = false
    @State private var activeBatch: String?
    @State private var batchTask: Task<Void, Never>?
    @State private var batchProcessed = 0
    @State private var batchTotal = 0
    @State private var batchFailures: [String] = []
    @State private var batchInstalled = 0
    @State private var batchCurrent = ""
    @State private var report: String?
    @State private var showReport = false

    // MARK: - Composable screen
    //
    // Batch 05L–05O originally placed the entire Form, several repository
    // builders, two confirmation dialogs and an alert into one SwiftUI body.
    // On Xcode 26.3 that exceeded the Swift constraint solver's budget.
    // Opaque `some View` boundaries below keep each expression independently
    // type-checkable. They do not change repository trust or installation state.

    var body: some View {
        reportPresentation
            .task {
                await store.loadSavedRepositoriesIfNeeded()
                updateCenter.scan()
            }
            .refreshable {
                await store.refreshAll()
                updateCenter.scan()
            }
    }

    private var reportPresentation: some View {
        batchConfirmationPresentation
            .fullScreenCover(isPresented: $showingUpdateCenter) {
                KinetiqModuleUpdateCenterView()
            }
            .alert("Module Report", isPresented: $showReport) {
                Button("Copy Report") { UIPasteboard.general.string = report ?? "" }
                Button("OK", role: .cancel) {}
            } message: {
                Text(report ?? "No report was generated.")
            }
    }

    private var batchConfirmationPresentation: some View {
        trustConfirmationPresentation
            .confirmationDialog(
                "Install available video modules?",
                isPresented: $showingBatchConfirmation,
                titleVisibility: .visible
            ) {
                if let batchTarget,
                   let repo = store.repositories.first(where: { $0.id == batchTarget }) {
                    Button("Install \(pendingSources(repo).count) Modules") {
                        beginBatch(repo)
                    }
                }
                Button("Cancel", role: .cancel) { batchTarget = nil }
            } message: {
                Text("Each ZIP must match its SHA-256. Previously trusted repositories require no additional trust prompt. Existing installations and working playback are left untouched when updates are unsafe.")
            }
    }

    private var trustConfirmationPresentation: some View {
        navigationPresentation
            .confirmationDialog(
                "Trust all modules from this repository?",
                isPresented: $showingTrustConfirmation,
                titleVisibility: .visible
            ) {
                if let trustTarget,
                   let repo = store.repositories.first(where: { $0.id == trustTarget }) {
                    Button("Trust All \(repo.modules.count) Sources") {
                        if !trustStore.approveAllSources(in: repo) {
                            report = "This repository could not be approved. Refresh it and review its publisher identity or signature before trying again."
                            showReport = true
                        }
                        self.trustTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) { trustTarget = nil }
            } message: {
                Text("This trusts all sources from the selected repository, including new modules added later. It is a COMMUNITY approval, not proof of publisher authenticity. Modules execute JavaScript with network access. If the repository or an existing module changes publisher identity, you must review and approve again. Invalid known signatures cannot be approved. ZIP integrity checks remain mandatory.")
            }
    }

    private var navigationPresentation: some View {
        Form {
            addRepositorySection
            moduleUpdatesSection
            connectedRepositoriesSection
            sourceSelectionSection
        }
        .navigationTitle("Module Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.repositories.isEmpty || store.isRefreshing)
                .accessibilityLabel("Refresh repositories")
            }
        }
    }

    private var addRepositorySection: some View {
        Section {
            TextField("Paste repository.json URL", text: $repositoryURL, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button { Task { await addRepository() } } label: {
                HStack {
                    if adding {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("Add Repository").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(cannotAddRepository)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Add a Source")
        } footer: {
            Text("Use Trust All Sources under a repository to approve its modules once. SHA-256 checks and publisher identity protection remain active.")
        }
    }

    private var cannotAddRepository: Bool {
        adding || store.isRefreshing ||
            repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var moduleUpdatesSection: some View {
        Section {
            Button {
                updateCenter.scan()
                showingUpdateCenter = true
            } label: {
                HStack {
                    Label("Module Update Center", systemImage: "arrow.down.circle")
                    Spacer()
                    if !updateCenter.updates.isEmpty {
                        Text("\(updateCenter.updates.count)")
                            .font(.caption.weight(.bold))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !updateCenter.blocked.isEmpty {
                Label("\(updateCenter.blocked.count) release(s) need review",
                      systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Available Updates")
        } footer: {
            Text("Open the full-screen update center for publisher release notes, safe updates, and previous-version recovery.")
        }
    }

    private var connectedRepositoriesSection: some View {
        Section("Connected Repositories") {
            if store.repositories.isEmpty {
                ContentUnavailableView(
                    "No Repositories",
                    systemImage: "square.stack.3d.up",
                    description: Text("Add a repository.json URL above to discover modules.")
                )
            }
            ForEach(store.repositories) { repository in
                repositoryDisclosure(repository)
                repositoryQuickTrustAction(repository)
            }
        }
    }

    // Always visible, even when a repository's disclosure group is collapsed.
    // A successful approval covers EVERY source in that repository, not just
    // the currently selected or installed module.
    @ViewBuilder
    private func repositoryQuickTrustAction(_ repo: ModuleRepositoryRecord) -> some View {
        let state = trustStore.trust(for: repo)
        switch state {
        case .approvalNeeded, .changedPublisher:
            Button {
                trustTarget = repo.id
                showingTrustConfirmation = true
            } label: {
                Label(
                    state == .changedPublisher
                        ? "Review Publisher Change and Trust All Sources"
                        : "Trust All \(repo.modules.count) Sources in This Repository",
                    systemImage: "checkmark.shield"
                )
                .font(.subheadline.weight(.medium))
            }
            .disabled(store.isRefreshing || repo.refreshError != nil)
            .accessibilityHint("Approve this community repository once for all of its listed and future modules, subject to publisher identity checks.")

        case .communityApproved:
            Label("All \(repo.modules.count) Sources Trusted — Community Repository",
                  systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .verifiedPublisher:
            Label("Verified Publisher — All Sources Allowed",
                  systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .offline:
            Label("Repository Offline — Existing Trusted Modules Only",
                  systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)

        default:
            Label("Repository Trust Blocked — Review Publisher Signature",
                  systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func repositoryDisclosure(_ repo: ModuleRepositoryRecord) -> some View {
        DisclosureGroup {
            repositoryContents(repo)
        } label: {
            repositoryHeader(repo)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.removeRepository(repo) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func repositoryContents(_ repo: ModuleRepositoryRecord) -> some View {
        repositoryTrustControls(repo)
        if !repo.modules.isEmpty {
            batchControls(repo)
        }
        if repo.modules.isEmpty {
            Text(repo.refreshError ?? "This repository contains no modules.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        ForEach(store.sources(in: repo)) { source in
            KinetiqApprovedModuleSourceRow(
                source: source,
                isSelected: store.isSelected(source.id)
            ) {
                store.selectSource(source.id)
            }
        }
        if let refreshError = repo.refreshError {
            Label(refreshError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
            Button("Retry Repository Refresh") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isRefreshing)
        }
    }

    private func repositoryHeader(_ repo: ModuleRepositoryRecord) -> some View {
        let status = trustStore.trust(for: repo)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(repo.modules.count) modules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.allowsInstall ? Color.green : Color.orange)
            }
        }
    }

    private var sourceSelectionSection: some View {
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
            Text("\(store.availableSources.count) available modules across connected repositories.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Source Selection")
        } footer: {
            Text("Installed video modules use Kinetiq's native player. Manga and music modules remain listed but are not yet supported by the current runtime.")
        }
    }

    @ViewBuilder private func repositoryTrustControls(_ repo: ModuleRepositoryRecord) -> some View {
        let status = trustStore.trust(for: repo)
        VStack(alignment: .leading, spacing: 9) {
            Label(status.rawValue, systemImage: status.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.allowsInstall ? .green : .orange)
            Text(status == .verifiedPublisher
                 ? "Publisher signature verified using an independently pinned public key."
                 : status == .communityApproved
                 ? "Approved once for this repository. Individual modules still need SHA-256 and manifest validation."
                 : "Repository approval is required before installing its modules.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if status == .approvalNeeded || status == .changedPublisher {
                    Button(status == .changedPublisher ? "Review Publisher Change" : "Trust All Sources") {
                        trustTarget = repo.id
                        showingTrustConfirmation = true
                    }.buttonStyle(.borderedProminent)
                } else if status == .communityApproved {
                    Button("Revoke Trust", role: .destructive) { trustStore.revoke(repo) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    report = moduleReport(repo)
                    UIPasteboard.general.string = report
                    showReport = true
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                }.font(.caption).buttonStyle(.bordered)
            }
        }.padding(.vertical, 6)
    }

    private func releaseState(_ source: ModuleSourceOption) -> KinetiqModuleReleaseState {
        let record = packageStore.installedModule(for: source)
        return KinetiqModuleReleasePolicy.status(
            listedVersion: source.module.version,
            listedSHA: source.module.sha256,
            installedVersion: record?.version,
            installedSHA: record?.packageSHA256
        )
    }

    private func eligible(_ repo: ModuleRepositoryRecord) -> [ModuleSourceOption] {
        store.sources(in: repo).filter { source in
            source.module.contentType?.lowercased() == "video"
            && source.packageURL != nil
            && releaseState(source).permitsAutomaticInstall
        }
    }
    private func pendingSources(_ repo: ModuleRepositoryRecord) -> [ModuleSourceOption] {
        eligible(repo)
    }

    @ViewBuilder private func batchControls(_ repo: ModuleRepositoryRecord) -> some View {
        let pending = pendingSources(repo)
        let canInstall = trustStore.trust(for: repo).allowsInstall
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repository Installer").font(.subheadline.weight(.semibold))
                    Text("\(pending.count) modules available to install/update")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if activeBatch == repo.id {
                    Button("Stop") { batchTask?.cancel() }.tint(.orange)
                } else {
                    Button {
                        batchTarget = repo.id
                        showingBatchConfirmation = true
                    } label: {
                        Label("Install All", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KinetiqPalette.accent)
                    .disabled(!canInstall || pending.isEmpty || activeBatch != nil || store.isRefreshing)
                }
            }
            if activeBatch == repo.id {
                ProgressView(value: Double(batchProcessed), total: Double(max(1, batchTotal)))
                Text("\(batchProcessed)/\(batchTotal) · \(batchCurrent)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label("ZIP integrity: SHA-256 verified. Publisher authenticity requires a separately pinned key.",
                  systemImage: "checkmark.shield")
                .font(.caption2).foregroundStyle(.secondary)
            let blocked = store.sources(in: repo).filter { source in
                let status = releaseState(source)
                return status == .sameVersionMutation || status == .downgrade
            }.count
            if blocked > 0 {
                Label("\(blocked) suspicious or older release(s) blocked from automatic updates.",
                      systemImage: "exclamationmark.shield")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }.padding(.vertical, 8)
    }

    @MainActor private func beginBatch(_ repo: ModuleRepositoryRecord) {
        guard activeBatch == nil, trustStore.trust(for: repo).allowsInstall else { return }
        let pending = pendingSources(repo)
        guard !pending.isEmpty else { return }
        batchTotal = pending.count
        batchProcessed = 0
        batchInstalled = 0
        batchFailures = []
        batchCurrent = "Starting"
        activeBatch = repo.id
        batchTarget = nil
        batchTask = Task { @MainActor in
            for source in pending {
                if Task.isCancelled { break }
                // Refresh-time mutation or revoked trust must stop new writes.
                guard let current = store.repositories.first(where: { $0.id == repo.id }),
                      trustStore.trust(for: current).allowsInstall else { break }
                batchCurrent = source.module.displayName
                if releaseState(source).permitsAutomaticInstall {
                    do {
                        if let installed = packageStore.installedModule(for: source) {
                            try KinetiqModuleRollbackVault.capture(installed)
                        }
                        try await packageStore.install(source)
                        batchInstalled += 1
                    } catch is CancellationError { break }
                    catch {
                        batchFailures.append("\(source.module.moduleId): \(error.localizedDescription.prefix(180))")
                    }
                }
                batchProcessed += 1
            }
            let cancelled = Task.isCancelled
            report = (["Kinetiq module install summary", "Repository: \(repo.name)",
                       "Trusted state: \(trustStore.trust(for: repo).rawValue)",
                       "Installed or updated: \(batchInstalled)",
                       "Processed: \(batchProcessed)/\(batchTotal)",
                       "Failed: \(batchFailures.count)", "Cancelled: \(cancelled)",
                       "Package SHA-256 checked by native installer. Publisher verification is separate."]
                      + Array(batchFailures.prefix(12))).joined(separator: "\n")
            activeBatch = nil
            batchTask = nil
            batchCurrent = ""
            showReport = true
        }
    }

    private func moduleReport(_ repo: ModuleRepositoryRecord) -> String {
        let state = trustStore.trust(for: repo)
        let host = repo.url.host ?? "unknown"
        let records: [String] = store.sources(in: repo).prefix(150).map { source in
            let status = releaseState(source)
            let health = healthStore.status(for: source, installed: packageStore.installedModule(for: source))
            return "\(source.module.moduleId) v\(source.module.version ?? "?"): \(status.rawValue); \(health)"
        }
        return (["Kinetiq module diagnostics · 05L–05O foundation",
                 "Repository: \(repo.name)", "Host: \(host)",
                 "Repository ID: \(repo.repositoryId ?? "(unspecified)")",
                 "Trust: \(state.rawValue)",
                 "Publisher signature independently verified: \(state == .verifiedPublisher)",
                 "Catalogue status: \(repo.refreshError == nil ? "available" : "unavailable")",
                 "Modules: \(repo.modules.count)",
                 "Note: No URLs, headers, tokens, cookies, or raw response bodies included."]
                + records).joined(separator: "\n")
    }

    @MainActor private func addRepository() async {
        adding = true
        errorMessage = nil
        defer { adding = false }
        do {
            try await store.addRepository(from: repositoryURL)
            repositoryURL = ""
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Source row (no per-module trust prompt)

struct KinetiqApprovedModuleSourceRow: View {
    let source: ModuleSourceOption
    let isSelected: Bool
    let onSelect: () -> Void

    @StateObject private var packageStore = ModulePackageStore.shared
    @StateObject private var sourceStore = ModuleSourceStore.shared
    @StateObject private var trustStore = KinetiqRepositoryTrustStore.shared
    @StateObject private var healthStore = KinetiqModuleHealthStore.shared
    @State private var errorMessage: String?

    private var repository: ModuleRepositoryRecord? {
        sourceStore.repositories.first { $0.url == source.repositoryURL }
    }
    private var trust: KinetiqRepositoryTrust {
        repository.map { trustStore.trust(for: $0) } ?? .approvalNeeded
    }
    private var release: KinetiqModuleReleaseState {
        let record = packageStore.installedModule(for: source)
        return KinetiqModuleReleasePolicy.status(
            listedVersion: source.module.version, listedSHA: source.module.sha256,
            installedVersion: record?.version, installedSHA: record?.packageSHA256
        )
    }
    private var isVideo: Bool { source.module.contentType?.lowercased() == "video" }
    private var canInstall: Bool {
        isVideo && trust.allowsInstall && source.packageURL != nil &&
            (release.permitsAutomaticInstall || release == .current)
    }

    var body: some View {
        HStack(spacing: 10) {
            selectionControl
            installationControl
        }
        .padding(.vertical, 4)
        .alert("Module Installation", isPresented: installationErrorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The module could not be installed.")
        }
    }

    private var installationErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var selectionControl: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                sourceArtwork
                sourceInformation
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KinetiqPalette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sourceArtwork: some View {
        Group {
            if let iconURL = source.iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        sourceSymbol
                    }
                }
            } else {
                sourceSymbol
            }
        }
        .frame(width: 34, height: 34)
        .padding(5)
        .background(
            KinetiqPalette.accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var sourceInformation: some View {
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
            if release == .sameVersionMutation || release == .downgrade {
                Text(release.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            let health = healthStore.status(
                for: source,
                installed: packageStore.installedModule(for: source)
            )
            if health != "Unverified on this build" {
                Text(health)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var installationControl: some View {
        if isVideo {
            Button {
                Task { await installPackage() }
            } label: {
                installationLabel
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(KinetiqPalette.accent)
            .disabled(!canInstall || packageStore.isInstalling(source))
        } else {
            Text("Later")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var installationLabel: some View {
        if packageStore.isInstalling(source) {
            ProgressView().controlSize(.small)
        } else if release == .current {
            Label("Re-verify", systemImage: "checkmark.circle.fill")
        } else if release == .updateAvailable {
            Label("Update", systemImage: "arrow.up.circle")
        } else {
            Label(
                trust.allowsInstall ? "Install" : "Trust first",
                systemImage: trust.allowsInstall ? "arrow.down.circle" : "lock.shield"
            )
        }
    }

    private var sourceSymbol: some View {
        Image(systemName: source.symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(KinetiqPalette.accent)
    }

    @MainActor private func installPackage() async {
        guard trust.allowsInstall,
              (release.permitsAutomaticInstall || release == .current) else {
            errorMessage = "Trust this repository first, or review the blocked release."
            return
        }
        do {
            if release == .updateAvailable,
               let original = packageStore.installedModule(for: source) {
                try KinetiqModuleRollbackVault.capture(original)
            }
            try await packageStore.install(source)
            KinetiqModuleUpdateCenterStore.shared.scan()
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Batch 05P-B: Real repository module update center
// Kept in ModuleSourcesView.swift so this batch does not require an
// unverified Xcode project.pbxproj change.

struct KinetiqModuleUpdateOffer: Identifiable {
    let source: ModuleSourceOption
    let repository: ModuleRepositoryRecord
    let installed: InstalledModuleRecord

    var id: String { source.id }
    var revisionToken: String {
        // Release-specific notification key; changed versions notify again.
        let version = source.module.version ?? ""
        let digest = source.module.sha256?.lowercased() ?? ""
        return SHA256.hash(data: Data((id + "\n" + version + "\n" + digest).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    var releaseNotes: [String] {
        (source.module.changelog ?? []).prefix(24).compactMap { raw -> String? in
            let note = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : String(note.prefix(800))
        }
    }
    var newVersion: String { source.module.version ?? "Unknown" }
    @MainActor var publisherStatus: KinetiqRepositoryTrust {
        KinetiqRepositoryTrustStore.shared.trust(for: repository)
    }
}

struct KinetiqModuleBlockedRelease: Identifiable {
    let id: String
    let name: String
    let installedVersion: String
    let listedVersion: String
    let reason: String
}

@MainActor
final class KinetiqModuleUpdateCenterStore: ObservableObject {
    static let shared = KinetiqModuleUpdateCenterStore()

    @Published private(set) var updates: [KinetiqModuleUpdateOffer] = []
    @Published private(set) var blocked: [KinetiqModuleBlockedRelease] = []
    @Published private(set) var dismissedRevisions: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeModuleID: String?
    @Published private(set) var installedThisSession = 0
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    @Published var statusMessage: String?

    private static let dismissKey = "kinetiq.modules.updateDismissals.05PB.v1"
    private let sources = ModuleSourceStore.shared
    private let packages = ModulePackageStore.shared
    private let trust = KinetiqRepositoryTrustStore.shared

    private init() {
        dismissedRevisions = Set(UserDefaults.standard.stringArray(forKey: Self.dismissKey) ?? [])
    }

    var newUndismissedUpdates: [KinetiqModuleUpdateOffer] {
        updates.filter { !dismissedRevisions.contains($0.revisionToken) }
    }
    var canUpdateAny: Bool {
        activeModuleID == nil && updates.contains { trust.trust(for: $0.repository).allowsInstall }
    }

    /// No update is announced merely because a new module is in the catalog.
    /// Only an installed source with a strictly newer, hash-pinned version
    /// qualifies. Same-version mutations and downgrades are warning-only.
    func scan() {
        var next: [KinetiqModuleUpdateOffer] = []
        var rejected: [KinetiqModuleBlockedRelease] = []
        for repo in sources.repositories {
            for source in sources.sources(in: repo) {
                guard let installed = packages.installedModule(for: source) else { continue }
                let state = KinetiqModuleReleasePolicy.status(
                    listedVersion: source.module.version,
                    listedSHA: source.module.sha256,
                    installedVersion: installed.version,
                    installedSHA: installed.packageSHA256
                )
                let trustState = trust.trust(for: repo)
                if state == .updateAvailable && repo.refreshError == nil &&
                    source.module.contentType?.lowercased() == "video" && source.packageURL != nil {
                    if trustState.allowsInstall {
                        next.append(KinetiqModuleUpdateOffer(source: source,
                                                             repository: repo, installed: installed))
                    } else {
                        rejected.append(.init(id: source.id, name: installed.name,
                                              installedVersion: installed.version,
                                              listedVersion: source.module.version ?? "?",
                                              reason: "Repository approval or publisher review required: \(trustState.rawValue)."))
                    }
                } else if state == .updateAvailable && repo.refreshError != nil {
                    rejected.append(.init(id: source.id, name: installed.name,
                                          installedVersion: installed.version,
                                          listedVersion: source.module.version ?? "?",
                                          reason: "Repository could not be refreshed. Cached update is not eligible for installation."))
                } else if state == .sameVersionMutation || state == .downgrade {
                    let reason = state == .sameVersionMutation
                        ? "Same version number, different ZIP checksum. Update blocked."
                        : "Repository advertises an older version. Automatic downgrade blocked."
                    rejected.append(.init(id: source.id, name: installed.name,
                                          installedVersion: installed.version,
                                          listedVersion: source.module.version ?? "?", reason: reason))
                }
            }
        }
        let currentIDs = Set(sources.availableSources.map(\.id))
        for record in packages.installedModules.values where !currentIDs.contains(record.sourceID) {
            rejected.append(.init(id: record.sourceID, name: record.name,
                                  installedVersion: record.version, listedVersion: "Not listed",
                                  reason: "Installed version is preserved; the original source is no longer listed in a connected repository."))
        }
        updates = next.sorted { $0.source.module.displayName.localizedCaseInsensitiveCompare(
            $1.source.module.displayName) == .orderedAscending }
        blocked = rejected.sorted { $0.name < $1.name }
    }

    /// App launch calls this once after the saved repository catalogues load.
    func checkForUpdatesOnLaunch() async -> Bool {
        await sources.loadSavedRepositoriesIfNeeded()
        // Home and the update center may initiate their first repository fetch
        // concurrently. Avoid prompting with stale cache while a refresh runs.
        for _ in 0..<120 {
            if !sources.isRefreshing || Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled else { return false }
        scan()
        return !newUndismissedUpdates.isEmpty
    }

    func checkNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await sources.refreshAll()
        guard !Task.isCancelled else { return }
        scan()
        if updates.isEmpty { statusMessage = "No newer installed module releases were found." }
    }

    func remindMeLater() {
        dismissedRevisions.formUnion(updates.map(\.revisionToken))
        // Persist a bounded amount of notification history.
        if dismissedRevisions.count > 600 {
            dismissedRevisions = Set(updates.map(\.revisionToken))
        }
        UserDefaults.standard.set(Array(dismissedRevisions), forKey: Self.dismissKey)
    }

    func update(_ offer: KinetiqModuleUpdateOffer) async throws {
        guard activeModuleID == nil else {
            throw KinetiqModuleUpdateError.installationInProgress
        }
        guard let liveRepo = sources.repositories.first(where: { $0.id == offer.repository.id }),
              liveRepo.refreshError == nil,
              trust.trust(for: liveRepo).allowsInstall,
              let live = sources.sources(in: liveRepo).first(where: { $0.id == offer.id }),
              live.module.version == offer.source.module.version,
              live.module.sha256?.lowercased() == offer.source.module.sha256?.lowercased(),
              live.packageURL != nil,
              let original = packages.installedModule(for: live),
              original.packageSHA256.caseInsensitiveCompare(offer.installed.packageSHA256) == .orderedSame,
              original.version == offer.installed.version,
              KinetiqModuleReleasePolicy.status(
                listedVersion: live.module.version, listedSHA: live.module.sha256,
                installedVersion: original.version, installedSHA: original.packageSHA256
              ) == .updateAvailable else {
            throw KinetiqModuleUpdateError.releaseChanged
        }
        activeModuleID = live.id
        defer { activeModuleID = nil; scan() }
        try Task.checkCancellation()
        // Capture an exact, hash-checked previous release before any write.
        // The native installer manages its own temporary backup; this vault
        // survives successful swaps so a user can recover on the next launch.
        let previous = try KinetiqModuleRollbackVault.capture(original)
        do {
            try await packages.install(live)
        } catch {
            // The native installer may have rolled back on its own. Schedule
            // cold-start recovery only if its persisted record differs from
            // the version we captured; never touch favorites/history/downloads.
            let current = packages.installedModule(for: live)
            if KinetiqModuleUpdateSafety.requiresRecovery(from: original, current: current) ||
                !KinetiqModuleRollbackVault.installedFilesMatch(previous) {
                do {
                    try KinetiqModuleRollbackVault.requestRestore(previous)
                    statusMessage = "Update interrupted for \(original.name). Recovery is scheduled for the next launch."
                } catch {
                    statusMessage = "Update interrupted for \(original.name). Open Module Updates → Recovery to restore your previous version."
                }
            }
            throw error
        }
        // Revalidate the current catalogue/trust AFTER the network await,
        // since another task may have refreshed or revoked this repository.
        let currentRepository = sources.repositories.first(where: { $0.id == liveRepo.id })
        let currentRelease = currentRepository.flatMap { repo in
            sources.sources(in: repo).first(where: { $0.id == live.id })
        }
        let installed = packages.installedModule(for: live)
        let postinstallValid = installed?.moduleID == original.moduleID &&
            installed?.sourceID == original.sourceID &&
            installed?.version == live.module.version &&
            installed?.packageSHA256.caseInsensitiveCompare(live.module.sha256 ?? "") == .orderedSame &&
            currentRepository.map { $0.refreshError == nil && trust.trust(for: $0).allowsInstall } == true &&
            currentRelease?.module.version == live.module.version &&
            currentRelease?.module.sha256?.lowercased() == live.module.sha256?.lowercased()
        guard postinstallValid, let installed else {
            do {
                try KinetiqModuleRollbackVault.requestRestore(previous)
                statusMessage = "Update verification failed for \(original.name). Recovery is scheduled for the next launch."
            } catch {
                statusMessage = "Update verification failed for \(original.name). Open Module Updates → Recovery to restore your previous version."
            }
            throw KinetiqModuleUpdateError.installationVerificationFailed
        }
        installedThisSession += 1
        statusMessage = "Updated \(installed.name) to v\(installed.version). A previous version is available under Recovery."
    }

    func updateAll() async {
        guard activeModuleID == nil else { return }
        let batch = updates
        total = batch.count
        processed = 0
        installedThisSession = 0
        var failures: [String] = []
        for offer in batch {
            if Task.isCancelled { break }
            do { try await update(offer) }
            catch is CancellationError { break }
            catch { failures.append("\(offer.source.module.displayName): \(error.localizedDescription)") }
            processed += 1
        }
        let summary = "Installed \(installedThisSession)/\(total) updates."
        let stopped = Task.isCancelled ? " Stopped by user." : ""
        statusMessage = summary + stopped + (failures.isEmpty ? "" :
            " \(failures.count) failed: " + failures.prefix(3).joined(separator: "; "))
        scan()
    }
}

// A failed installer must not schedule an unnecessary rollback if its own
// atomic swap restored the original installed record successfully.
enum KinetiqModuleUpdateSafety {
    static func requiresRecovery(from previous: InstalledModuleRecord,
                                 current: InstalledModuleRecord?) -> Bool {
        guard let current else { return true }
        return previous.sourceID != current.sourceID ||
            previous.repositoryURL != current.repositoryURL ||
            previous.moduleID != current.moduleID ||
            previous.version != current.version ||
            previous.packageSHA256.caseInsensitiveCompare(current.packageSHA256) != .orderedSame ||
            previous.manifestPath != current.manifestPath ||
            previous.entryScriptPath != current.entryScriptPath
    }
}

enum KinetiqModuleUpdateError: LocalizedError {
    case installationInProgress
    case releaseChanged
    case installationVerificationFailed
    var errorDescription: String? {
        switch self {
        case .installationInProgress: return "Another module is currently updating."
        case .releaseChanged: return "The release, repository trust, or installed version changed. Refresh before updating."
        case .installationVerificationFailed: return "The installed package did not match the expected release. Use Recovery or report this failure."
        }
    }
}

// MARK: - Persistent last-known-good module snapshot and cold-launch recovery
// This service backs up only module runtime files, never favorites/history,
// playback credentials, media downloads or source browsing data.

enum KinetiqModuleRollbackVault {
    struct Snapshot: Codable, Identifiable {
        let record: InstalledModuleRecord
        let folder: String
        let savedAt: Date
        let manifestDigest: String
        let scriptDigest: String
        var id: String { record.sourceID }
    }

    private static let pendingKey = "kinetiq.modules.rollbackPending.05PB.v1"
    private static let resultKey = "kinetiq.modules.lastRollbackResult.05PB.v1"
    private static let pendingV2Key = "kinetiq.modules.rollbackPending.05PC.v2"

    private struct PendingRecovery: Codable {
        let sourceID: String
        let folder: String
        let version: String
        let packageSHA256: String
    }

    static func root() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw KinetiqModuleRollbackError.storageUnavailable }
        return appSupport.appendingPathComponent("Kinetiq", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)
    }

    private static func vault() throws -> URL {
        try root().appendingPathComponent("PreviousReleases", isDirectory: true)
    }

    private static func index() throws -> URL {
        try vault().appendingPathComponent("snapshots.json")
    }
    private static func installedIndex() throws -> URL {
        try root().appendingPathComponent("installed-modules.json")
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func snapshots() -> [Snapshot] {
        guard let data = try? Data(contentsOf: index()),
              let list = try? JSONDecoder().decode([Snapshot].self, from: data) else { return [] }
        return list
    }

    static func isSafeFolder(_ folder: String) -> Bool {
        guard let id = UUID(uuidString: folder) else { return false }
        return id.uuidString == folder
    }

    // Shared by the runtime and deterministic tests: reject any file changed
    // after capture, including a replacement that retains the same filename.
    static func verifyFilePair(at directory: URL, manifestDigest: String,
                               scriptDigest: String) -> Bool {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let scriptURL = directory.appendingPathComponent("index.js")
        for url in [directory, manifestURL, scriptURL] {
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { return false }
        }
        guard let manifest = try? Data(contentsOf: manifestURL),
              let script = try? Data(contentsOf: scriptURL),
              !manifest.isEmpty, !script.isEmpty,
              manifest.count <= 512 * 1024, script.count <= 9 * 1024 * 1024,
              KinetiqRepositorySecurity.isValidSHA(manifestDigest),
              KinetiqRepositorySecurity.isValidSHA(scriptDigest) else { return false }
        return digest(manifest).caseInsensitiveCompare(manifestDigest) == .orderedSame &&
            digest(script).caseInsensitiveCompare(scriptDigest) == .orderedSame
    }

    private static func validatedLocation(_ record: InstalledModuleRecord) throws -> URL {
        let dir = URL(fileURLWithPath: record.directoryPath, isDirectory: true).standardizedFileURL
        let parent = dir.deletingLastPathComponent().standardizedFileURL
        guard parent == (try root()).standardizedFileURL,
              dir.lastPathComponent.count == 64,
              dir.lastPathComponent.allSatisfy(\.isHexDigit),
              record.manifestPath == dir.appendingPathComponent("manifest.json").path,
              record.entryScriptPath == dir.appendingPathComponent("index.js").path else {
            throw KinetiqModuleRollbackError.unsafeSnapshot
        }
        return dir
    }

    private static func validSnapshot(_ snapshot: Snapshot) -> Bool {
        guard isSafeFolder(snapshot.folder),
              KinetiqRepositorySecurity.isValidSHA(snapshot.record.packageSHA256),
              !snapshot.record.sourceID.isEmpty,
              !snapshot.record.moduleID.isEmpty,
              !snapshot.record.version.isEmpty,
              (try? validatedLocation(snapshot.record)) != nil,
              let base = try? vault() else { return false }
        let dir = base.appendingPathComponent(snapshot.folder, isDirectory: true)
        return verifyFilePair(at: dir, manifestDigest: snapshot.manifestDigest,
                              scriptDigest: snapshot.scriptDigest)
    }

    // The record can remain unchanged when a partially failed replacement
    // has already modified the actual installed files. Verify BOTH layers.
    static func installedFilesMatch(_ snapshot: Snapshot) -> Bool {
        guard let live = try? validatedLocation(snapshot.record) else { return false }
        return verifyFilePair(at: live, manifestDigest: snapshot.manifestDigest,
                              scriptDigest: snapshot.scriptDigest)
    }

    static func usableSnapshots() -> [Snapshot] {
        snapshots().filter(validSnapshot).sorted(by: { $0.savedAt > $1.savedAt })
    }

    @discardableResult
    static func capture(_ record: InstalledModuleRecord) throws -> Snapshot {
        let fm = FileManager.default
        let active = try validatedLocation(record)
        guard fm.fileExists(atPath: active.path),
              let manifest = try? Data(contentsOf: active.appendingPathComponent("manifest.json")),
              let script = try? Data(contentsOf: active.appendingPathComponent("index.js")) else {
            throw KinetiqModuleRollbackError.invalidInstalledModule
        }
        let base = try vault()
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let snapshotURL = base.appendingPathComponent(name, isDirectory: true)
        try fm.copyItem(at: active, to: snapshotURL)
        var updated = snapshots()
        let old = updated.filter { $0.id == record.sourceID }
        updated.removeAll { $0.id == record.sourceID }
        let new = Snapshot(record: record, folder: name, savedAt: Date(),
                           manifestDigest: digest(manifest), scriptDigest: digest(script))
        // Do not replace a known-good snapshot if this newly copied backup
        // differs from the installed manifest/script at capture time.
        guard validSnapshot(new) else {
            try? fm.removeItem(at: snapshotURL)
            throw KinetiqModuleRollbackError.unsafeSnapshot
        }
        updated.append(new)
        do {
            let encoded = try JSONEncoder().encode(updated)
            try encoded.write(to: index(), options: .atomic)
            for expired in old where isSafeFolder(expired.folder) {
                try? fm.removeItem(at: base.appendingPathComponent(expired.folder, isDirectory: true))
            }
            return new
        } catch {
            try? fm.removeItem(at: snapshotURL)
            throw error
        }
    }

    // Only an exact release may satisfy an approved recovery request.
    // An updated snapshot must NEVER be substituted merely because its
    // sourceID matches the previously approved module.
    static func pinnedSnapshot(in snapshots: [Snapshot], sourceID: String,
                               folder: String, version: String,
                               packageSHA256: String) -> Snapshot? {
        snapshots.first(where: {
            $0.id == sourceID && $0.folder == folder &&
            $0.record.version == version &&
            $0.record.packageSHA256.caseInsensitiveCompare(packageSHA256) == .orderedSame
        })
    }

    static func requestRestore(_ snapshot: Snapshot) throws {
        guard usableSnapshots().contains(where: { $0.id == snapshot.id && $0.folder == snapshot.folder }) else {
            throw KinetiqModuleRollbackError.unsafeSnapshot
        }
        let request = PendingRecovery(sourceID: snapshot.id, folder: snapshot.folder,
                                      version: snapshot.record.version,
                                      packageSHA256: snapshot.record.packageSHA256)
        UserDefaults.standard.set(try JSONEncoder().encode(request), forKey: pendingV2Key)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    /// App.init invokes this BEFORE ModulePackageStore.shared loads its cached
    /// installed module index. This is essential because that store's index
    /// is private and is read only once at initialization.
    static func restorePendingOnLaunch() {
        let defaults = UserDefaults.standard
        let pending: PendingRecovery?
        if let data = defaults.data(forKey: pendingV2Key) {
            pending = try? JSONDecoder().decode(PendingRecovery.self, from: data)
            if pending == nil {
                defaults.set("Recovery refused: pending request is malformed.", forKey: resultKey)
                defaults.removeObject(forKey: pendingV2Key)
                return
            }
        } else if let legacyID = defaults.string(forKey: pendingKey) {
            // Legacy 05P-B had no version/folder pin. Only accept it when
            // exactly one valid snapshot exists for that installed source.
            let candidates = usableSnapshots().filter { $0.id == legacyID }
            guard candidates.count == 1, let snapshot = candidates.first else {
                defaults.set("Legacy recovery refused: no unique verified backup exists.", forKey: resultKey)
                defaults.removeObject(forKey: pendingKey)
                return
            }
            pending = PendingRecovery(sourceID: legacyID, folder: snapshot.folder,
                                      version: snapshot.record.version,
                                      packageSHA256: snapshot.record.packageSHA256)
        } else { return }
        guard let pending,
              let snapshot = pinnedSnapshot(in: usableSnapshots(),
                                            sourceID: pending.sourceID,
                                            folder: pending.folder,
                                            version: pending.version,
                                            packageSHA256: pending.packageSHA256) else {
            defaults.set("Recovery refused: the selected backup is missing or changed.", forKey: resultKey)
            defaults.removeObject(forKey: pendingV2Key)
            defaults.removeObject(forKey: pendingKey)
            return
        }
        do {
            try restore(snapshot)
            defaults.set("Restored \(snapshot.record.name) v\(snapshot.record.version).", forKey: resultKey)
            defaults.removeObject(forKey: pendingV2Key)
            defaults.removeObject(forKey: pendingKey)
        } catch {
            defaults.set("Recovery failed: \(error.localizedDescription)", forKey: resultKey)
            // Preserve the exact request for one more attempt; never erase
            // or modify favorites, history, downloads or user media.
        }
    }

    static func takeLastResult() -> String? {
        let result = UserDefaults.standard.string(forKey: resultKey)
        UserDefaults.standard.removeObject(forKey: resultKey)
        return result
    }

    private static func restore(_ snapshot: Snapshot) throws {
        guard validSnapshot(snapshot) else { throw KinetiqModuleRollbackError.unsafeSnapshot }
        let fm = FileManager.default
        let live = try validatedLocation(snapshot.record)
        let snapshotFolder = try vault().appendingPathComponent(snapshot.folder, isDirectory: true)
        let indexURL = try installedIndex()
        let previousData = try Data(contentsOf: indexURL)
        var installed = try JSONDecoder().decode([InstalledModuleRecord].self, from: previousData)
        guard installed.contains(where: {
            $0.sourceID == snapshot.id &&
            $0.moduleID == snapshot.record.moduleID &&
            $0.repositoryURL == snapshot.record.repositoryURL &&
            $0.directoryPath == snapshot.record.directoryPath
        }) else {
            throw KinetiqModuleRollbackError.invalidInstalledModule
        }
        installed.removeAll { $0.sourceID == snapshot.id }
        installed.append(snapshot.record)
        let oldDestination = try root().appendingPathComponent(".rollback-temp-\(UUID().uuidString)")
        var movedOld = false
        do {
            if fm.fileExists(atPath: live.path) {
                try fm.moveItem(at: live, to: oldDestination)
                movedOld = true
            }
            try fm.copyItem(at: snapshotFolder, to: live)
            guard verifyFilePair(at: live, manifestDigest: snapshot.manifestDigest,
                                 scriptDigest: snapshot.scriptDigest) else {
                throw KinetiqModuleRollbackError.unsafeSnapshot
            }
            try JSONEncoder().encode(installed).write(to: indexURL, options: .atomic)
            if movedOld { try? fm.removeItem(at: oldDestination) }
        } catch {
            try? fm.removeItem(at: live)
            if movedOld { try? fm.moveItem(at: oldDestination, to: live) }
            try? previousData.write(to: indexURL, options: .atomic)
            throw error
        }
    }
}

enum KinetiqModuleRollbackError: LocalizedError {
    case storageUnavailable
    case invalidInstalledModule
    case unsafeSnapshot
    var errorDescription: String? {
        switch self {
        case .storageUnavailable: return "Application Support storage is unavailable."
        case .invalidInstalledModule: return "The previous module installation could not be verified."
        case .unsafeSnapshot: return "A previous-version backup failed integrity or path checks."
        }
    }
}

// MARK: - Small SwiftUI views keep Xcode's constraint solver responsive

struct KinetiqModuleUpdateCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var updates = KinetiqModuleUpdateCenterStore.shared
    @State private var batchTask: Task<Void, Never>?
    @State private var error: String?
    @State private var restoreTarget: KinetiqModuleRollbackVault.Snapshot?

    var body: some View {
        NavigationStack {
            updateList
                .navigationTitle("Module Updates")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { actionBar }
        }
        .task {
            updates.scan()
            if let message = KinetiqModuleRollbackVault.takeLastResult() {
                updates.statusMessage = message
            }
        }
        .alert("Module Update", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} }
        message: { Text(error ?? "Unknown error") }
        .confirmationDialog("Restore previous module version?",
            isPresented: Binding(get: { restoreTarget != nil },
                                 set: { if !$0 { restoreTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let restoreTarget {
                Button("Restore v\(restoreTarget.record.version) on Next Launch") {
                    do {
                        try KinetiqModuleRollbackVault.requestRestore(restoreTarget)
                        updates.statusMessage = "Recovery scheduled for \(restoreTarget.record.name). Close Kinetiq fully and reopen it to restore the previous version."
                    } catch { self.error = error.localizedDescription }
                    self.restoreTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { restoreTarget = nil }
        } message: {
            Text("The previous verified module files will be restored the next time you fully relaunch Kinetiq. Favorites, history and downloads are not changed.")
        }
    }

    private var updateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if let status = updates.statusMessage {
                    Label(status, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if updates.updates.isEmpty {
                    ContentUnavailableView("You're Up to Date", systemImage: "checkmark.shield",
                        description: Text("No newer versions were advertised for currently installed video modules."))
                } else {
                    ForEach(updates.updates) { offer in
                        KinetiqModuleUpdateOfferCard(offer: offer,
                            isInstalling: updates.activeModuleID == offer.id,
                            canInstall: updates.activeModuleID == nil,
                            onInstall: { Task { await install(offer) } })
                    }
                }
                if !updates.blocked.isEmpty { blockedSection }
                if !KinetiqModuleRollbackVault.usableSnapshots().isEmpty { recoverySection }
                Text("Publisher changelogs come from the repository, not Kinetiq. A community-approved repository is not a cryptographically verified publisher. Downloads still require exact ZIP SHA-256 and manifest validation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("KINETIQ UPDATES", systemImage: "arrow.down.circle")
                .font(.caption.weight(.bold)).foregroundStyle(KinetiqPalette.accent)
            Text("Keep your sources current")
                .font(.title2.weight(.bold))
            Text("\(updates.updates.count) installed module update(s) available")
                .font(.subheadline).foregroundStyle(.secondary)
            if updates.total > 0 {
                ProgressView(value: Double(updates.processed),
                             total: Double(max(1, updates.total)))
                Text("\(updates.processed) of \(updates.total) processed")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs Review", systemImage: "exclamationmark.shield")
                .font(.headline)
            ForEach(updates.blocked) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    Text("v\(item.installedVersion) → v\(item.listedVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.reason).font(.caption).foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Previous Versions · Recovery", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
            ForEach(KinetiqModuleRollbackVault.usableSnapshots()) { snapshot in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.record.name).font(.subheadline.weight(.semibold))
                        Text("Restore v\(snapshot.record.version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { restoreTarget = snapshot }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if updates.canUpdateAny {
                Button {
                    batchTask = Task { await updates.updateAll(); batchTask = nil }
                } label: {
                    Label("Update All (\(updates.updates.count))", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(batchTask != nil)
            }
            HStack {
                Button("Remind Me Later") {
                    updates.remindMeLater()
                    dismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                if batchTask != nil {
                    Button("Stop After Current") { batchTask?.cancel() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await updates.checkNow() }
            } label: { Image(systemName: "arrow.clockwise") }
                .disabled(updates.isRefreshing || updates.activeModuleID != nil)
                .accessibilityLabel("Check for module updates")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }.fontWeight(.semibold)
        }
    }

    @MainActor private func install(_ offer: KinetiqModuleUpdateOffer) async {
        do { try await updates.update(offer) }
        catch { self.error = error.localizedDescription }
    }
}

private struct KinetiqModuleUpdateOfferCard: View {
    let offer: KinetiqModuleUpdateOffer
    let isInstalling: Bool
    let canInstall: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.source.module.displayName)
                        .font(.headline)
                    Text(offer.repository.name)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("v\(offer.installed.version) → v\(offer.newVersion)")
                        .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
            }
            if let published = offer.source.module.publishedDate {
                Text("Published \(published.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("WHAT'S NEW")
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if offer.releaseNotes.isEmpty {
                Text("The publisher did not provide release notes for this version.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(offer.releaseNotes.enumerated()), id: \.offset) { item in
                    Label(item.element, systemImage: "circle.fill")
                        .font(.subheadline).labelStyle(.titleAndIcon)
                }
            }
            Label(offer.publisherStatus == .verifiedPublisher
                  ? "Independently verified publisher"
                  : "Community-approved repository · package SHA-256 checked on install",
                  systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: onInstall) {
                HStack {
                    if isInstalling { ProgressView().controlSize(.small) }
                    Text(isInstalling ? "Installing…" : "Update Module")
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canInstall)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var artwork: some View {
        Group {
            if let icon = offer.source.iconURL {
                AsyncImage(url: icon) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: offer.source.symbol)
                }
            } else {
                Image(systemName: offer.source.symbol)
            }
        }
        .frame(width: 52, height: 52)
        .background(KinetiqPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
