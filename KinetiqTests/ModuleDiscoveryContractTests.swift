import Foundation
import CryptoKit
import XCTest
@testable import Kinetiq

// Batch 05J: deterministic fixtures model the shapes returned by the
// Synthetiq One / Anime / Flux / AniWorld discovery_v1 handlers. These are
// parser tests, NOT evidence of source-site availability or iPhone playback.
final class ModuleDiscoveryContractTests: XCTestCase {
    private let baseURL = URL(string: "https://example.org/")!

    func testRealHomeSectionsAndViewAllFeed() {
        let payload: [String: Any] = [
            "sections": [
                ["id": "popular", "title": "Popular Now", "style": "poster",
                 "viewAll": ["mode": "feed", "feedId": "more-fast"],
                 "items": [
                    ["id": "mal:21", "href": "mal:21", "title": "One Piece",
                     "image": "https://img.example.org/21.jpg",
                     "streamCached": true, "year": 1999],
                    ["id": "mal:21", "href": "mal:21", "title": "Duplicate"]]],
                ["id": "empty", "title": "Empty", "items": []]
            ]
        ]
        let shelves = ModuleDiscoveryDecoder.home(from: payload, baseURL: baseURL)
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves[0].id, "popular")
        XCTAssertEqual(shelves[0].title, "Popular Now")
        XCTAssertEqual(shelves[0].feedID, "more-fast")
        XCTAssertEqual(shelves[0].cards.count, 1)
        XCTAssertEqual(shelves[0].cards[0].anime.href, "mal:21")
        XCTAssertEqual(shelves[0].cards[0].badge, "FAST")
        XCTAssertEqual(shelves[0].cards[0].year, "1999")
    }

    func testAniWorldHomeCardsUseSourceIdentity() {
        let payload: [String: Any] = [
            "sections": [[
                "id": "home-new", "title": "Neue Animes",
                "items": [["id": "series-abc", "href": "/anime/stream/series-abc",
                           "title": "Example Anime", "posterUrl": "/images/abc.jpg"]]
            ]]
        ]
        let shelves = ModuleDiscoveryDecoder.home(from: payload, baseURL: baseURL)
        XCTAssertEqual(shelves.first?.cards.first?.anime.id, "series-abc")
        XCTAssertEqual(shelves.first?.cards.first?.anime.href,
                       "/anime/stream/series-abc")
        XCTAssertEqual(shelves.first?.cards.first?.anime.imageURL?.absoluteString,
                       "https://example.org/images/abc.jpg")
        XCTAssertNil(shelves.first?.feedID)
    }

    func testInvalidArtAndMissingTitlesAreRejectedSafely() {
        let cards = ModuleDiscoveryDecoder.parseCards([
            ["id": "a", "title": "Valid", "image": "http://insecure.example/a.jpg"],
            ["id": "b", "title": "Missing art", "image": "javascript:alert(1)"],
            ["id": "c", "image": "https://example.org/c.jpg"],
            ["id": "a", "title": "Repeated"]
        ], baseURL: baseURL, limit: 40)
        XCTAssertEqual(cards.map(\.id), ["a", "b"])
        XCTAssertNil(cards[0].anime.imageURL)
        XCTAssertNil(cards[1].anime.imageURL)
    }

    func testExplicitFeedPaginationAndNoManufacturedHasMore() {
        let first = ModuleDiscoveryDecoder.feed(from: [
            "items": [["id": "mal:10", "title": "A"],
                      ["id": "mal:10", "title": "A again"]],
            "page": 2, "hasMore": true
        ], baseURL: baseURL, requestedPage: 2)
        XCTAssertEqual(first.cards.count, 1)
        XCTAssertEqual(first.page, 2)
        XCTAssertTrue(first.hasMore)

        let empty = ModuleDiscoveryDecoder.feed(from: [
            "items": [], "page": 3, "hasMore": true
        ], baseURL: baseURL, requestedPage: 3)
        XCTAssertFalse(empty.hasMore)
    }

    func testMalformedDiscoveryDoesNotBreakSearchFallback() {
        XCTAssertTrue(ModuleDiscoveryDecoder.home(from: ["error": "source down"],
                                                  baseURL: baseURL).isEmpty)
        XCTAssertTrue(ModuleDiscoveryDecoder.home(from: ["sections": "not an array"],
                                                  baseURL: baseURL).isEmpty)
    }

    func testBoundedLargeModuleOutput() {
        let many = (0..<250).map { i -> [String: Any] in
            ["id": "s\(i)", "title": "Title \(i)"]
        }
        let sections = (0..<30).map { index -> [String: Any] in
            ["id": "shelf\(index)", "items": many]
        }
        let result = ModuleDiscoveryDecoder.home(
            from: ["sections": sections], baseURL: baseURL
        )
        XCTAssertEqual(result.count, 12)
        XCTAssertTrue(result.allSatisfy { $0.cards.count == 40 })
    }


    // MARK: - Batch 05K Source Playback Triage

    func testSourceAdvertisedNoStreamIsNotDecoderError() {
        // Synthetiq One deliberately returns this shape when a DUB
        // stream is not currently cached; inventing an MP4 URL is forbidden.
        let result: [String: Any] = ["streams": []]
        XCTAssertThrowsError(try ModuleRuntimeDecoder.streams(
            from: result, title: "Unavailable episode", baseURL: baseURL
        )) { error in
            XCTAssertEqual(ModulePlaybackDiagnostics.code(for: error),
                           "SOURCE_NO_MEDIA_FOR_EPISODE")
        }
    }

    func testFlatStreamPairsPreserveSourceOrderAndHeaders() throws {
        // The V3/V4 documented flat [label, URL, ...] format is shared
        // by source modules and self-authored modules like ReAnime.
        let result: [String: Any] = [
            "streams": ["HD 1080p", "https://media.example.org/1080.m3u8",
                        "SD 480p", "https://media.example.org/480.m3u8"],
            "streamType": "hls",
            "headers": ["Referer": "https://source.example.org/"]
        ]
        let streams = try ModuleRuntimeDecoder.streams(
            from: result, title: "Example", baseURL: baseURL
        )
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(streams.map(\.label), ["HD 1080p", "SD 480p"])
        XCTAssertEqual(streams.first?.headers["Referer"],
                       "https://source.example.org/")
        XCTAssertFalse(streams[0].isWebEmbed)
    }

    func testMegaKinoTxtHLSIsNativeAndDoesNotFabricateExtension() throws {
        // GXPlayer can supply an HLS master whose URL ends with .txt.
        // Its explicit streamType, not its suffix, is the deciding hint.
        let result: [String: Any] = [
            "streams": ["Deutsch Dub", "https://cdn.example.org/m3u8/123/master.txt?s=1"],
            "streamType": "hls"
        ]
        let streams = try ModuleRuntimeDecoder.streams(
            from: result, title: "Film", baseURL: baseURL
        )
        XCTAssertEqual(streams.first?.url.pathExtension, "txt")
        XCTAssertEqual(streams.first?.streamType, "hls")
        XCTAssertEqual(streams.first?.isWebEmbed, false)
    }

    func testProviderErrorClassificationDoesNotExposeDetails() {
        let result: [String: Any] = [
            "streams": [],
            "error": ["message": "HTTP 403 forbidden https://example.org/?token=secret"]
        ]
        let summary = ModulePlaybackDiagnostics.sourceResponseStatus(result)
        XCTAssertTrue(summary.contains("SOURCE_ACCESS_DENIED"))
        XCTAssertFalse(summary.contains("token="))
        XCTAssertFalse(summary.contains("secret"))
    }

    func testExplicitProviderFailureIsNotFlattenedToEmptyMedia() {
        let result: [String: Any] = [
            "streams": [], "error": ["message": "HTTP 403 forbidden"]
        ]
        XCTAssertThrowsError(try ModuleRuntimeDecoder.streams(
            from: result, title: "Blocked episode", baseURL: baseURL
        )) { error in
            XCTAssertEqual(ModulePlaybackDiagnostics.code(for: error),
                           "SOURCE_REPORTED_RESOLVE_FAILURE")
        }
    }

    func testAccessDenialDoesNotGetLabelledAsNoMedia() {
        XCTAssertEqual(ModulePlaybackDiagnostics.providerErrorCategory(
            "HTTP 429 - too many requests"), "SOURCE_RATE_LIMITED")
        XCTAssertEqual(ModulePlaybackDiagnostics.providerErrorCategory(
            "Cloudflare challenge"), "SOURCE_CHALLENGE")
    }
}

// MARK: - 05L-05O repository security regression tests
// These run WITHOUT contacting real source websites. They do not certify any
// particular publisher, CDN, playback stream, or physical iPhone result.

final class KinetiqRepositoryPolicyTests: XCTestCase {
    private func sourceModule(_ id: String = "demo-v1", identity: String = "DEMO-VID-1") throws -> ModuleRepositoryModule {
        let object: [String: Any] = [
            "moduleId": id, "moduleFamilyId": "demo", "moduleIdentity": identity,
            "moduleIdentityNumber": 1, "contentType": "video", "version": "1.0.0",
            "sha256": String(repeating: "a", count: 64),
            "packageUrl": "https://example.org/demo.zip"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ModuleRepositoryModule.self, from: data)
    }

    func testUnsafeRepositoryURLsAreRejected() {
        let rejected = [
            "http://example.org/repository.json",
            "https://localhost/repository.json",
            "https://127.0.0.1/repository.json",
            "https://10.1.2.3/repository.json",
            "https://172.16.3.4/repository.json",
            "https://192.168.1.50/repository.json",
            "https://169.254.169.254/latest/meta-data/",
            "https://100.64.0.1/repository.json",
            "https://user:password@example.org/repository.json",
            "https://example.local/repository.json",
            "https://[::1]/repository.json",
            "file:///tmp/repository.json"
        ]
        for raw in rejected {
            guard let url = URL(string: raw) else { continue }
            XCTAssertFalse(KinetiqRepositorySecurity.isPublicHTTPS(url), "Allowed unsafe URL: \(raw)")
        }
    }

    func testPublicRepositoryAndPackageURLsRemainAvailable() {
        for raw in [
            "https://raw.githubusercontent.com/kas021/Synthetiq-Modules/main/repository.json",
            "https://github.com/Haimiya612/Kinetiq-Modules/releases/download/v1/module.zip",
            "https://cdn.example.org/media/module.zip"
        ] {
            XCTAssertTrue(KinetiqRepositorySecurity.isPublicHTTPS(URL(string: raw)!))
        }
    }

    func testRepositoryRedirectCannotChangePublisherOwner() {
        let initial = URL(string: "https://raw.githubusercontent.com/owner-a/my-modules/main/repository.json")!
        let safe = URL(string: "https://raw.githubusercontent.com/owner-a/my-modules/main/catalogue.json")!
        let stolen = URL(string: "https://raw.githubusercontent.com/owner-b/my-modules/main/repository.json")!
        XCTAssertTrue(KinetiqRepositorySecurity.isSamePublisherScope(initial: initial, redirected: safe))
        XCTAssertFalse(KinetiqRepositorySecurity.isSamePublisherScope(initial: initial, redirected: stolen))
        XCTAssertFalse(KinetiqRepositorySecurity.isSamePublisherScope(
            initial: initial,
            redirected: URL(string: "https://example.net/repository.json")!))
    }

    func testPackageHashAndSameVersionMutationDetection() {
        XCTAssertTrue(KinetiqRepositorySecurity.isValidSHA(String(repeating: "a", count: 64)))
        XCTAssertFalse(KinetiqRepositorySecurity.isValidSHA("not-a-hash"))
        XCTAssertTrue(KinetiqRepositorySecurity.sameVersionMutation(
            installedVersion: "1.0.0", installedSHA: String(repeating: "a", count: 64),
            listedVersion: "1.0.0", listedSHA: String(repeating: "b", count: 64)))
        XCTAssertFalse(KinetiqRepositorySecurity.sameVersionMutation(
            installedVersion: "1.0.0", installedSHA: String(repeating: "a", count: 64),
            listedVersion: "1.0.1", listedSHA: String(repeating: "b", count: 64)))
    }

    func testUpdatePolicyRejectsReusedVersionAndDowngrade() {
        let a = String(repeating: "a", count: 64)
        let b = String(repeating: "b", count: 64)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.0.1", listedSHA: a, installedVersion: nil, installedSHA: nil), .notInstalled)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.0.1", listedSHA: a, installedVersion: "1.0.1", installedSHA: a), .current)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.0.1", listedSHA: b, installedVersion: "1.0.1", installedSHA: a), .sameVersionMutation)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.9.0", listedSHA: b, installedVersion: "1.10.0", installedSHA: a), .downgrade)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.10.0", listedSHA: b, installedVersion: "1.9.0", installedSHA: a), .updateAvailable)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "2", listedSHA: "incorrect", installedVersion: nil, installedSHA: nil), .incomplete)
        XCTAssertEqual(KinetiqModuleReleasePolicy.compareVersions("1.0.5-beta.9", "1.0.5-beta.10"),
                       .orderedAscending)
        XCTAssertEqual(KinetiqModuleReleasePolicy.compareVersions("1.0.5-beta.4", "1.0.5-beta.3"),
                       .orderedDescending)
    }

    func testExistingModuleIdentityChangeIsDetected() throws {
        let original = try sourceModule("same-id", identity: "ACME-VID-01")
        let replaced = try sourceModule("same-id", identity: "MALICIOUS-VID-01")
        XCTAssertFalse(KinetiqRepositorySecurity.expectedIdentityIsStable(
            original.stablePublisherIdentity, replaced.stablePublisherIdentity))
        XCTAssertEqual(original.stablePublisherIdentity, original.stablePublisherIdentity)
    }

    func testSignedCanonicalMessageAndTamperRejection() throws {
        let original = try sourceModule()
        let originalMessage = KinetiqPublisherSignature.canonicalMessage(
            repositoryID: "approved-publisher", issuedAtMs: 1_800_000_000_000, modules: [original])
        let privateKey = P256.Signing.PrivateKey()
        let signature = try privateKey.signature(for: originalMessage)
        let base64 = signature.rawRepresentation.base64EncodedString()
        XCTAssertTrue(KinetiqPublisherSignature.verify(
            signatureBase64: base64, message: originalMessage,
            publicKey: privateKey.publicKey.rawRepresentation))
        let modified = KinetiqPublisherSignature.canonicalMessage(
            repositoryID: "different-publisher", issuedAtMs: 1_800_000_000_000, modules: [original])
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: base64, message: modified,
            publicKey: privateKey.publicKey.rawRepresentation))
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: "not-base64", message: originalMessage,
            publicKey: privateKey.publicKey.rawRepresentation))
    }

    @MainActor
    func testCommunityApprovalCoversModulesButReapprovalForIdentityChange() throws {
        let module = try sourceModule()
        let url = URL(string: "https://example.org/\(UUID().uuidString)/repository.json")!
        var repository = ModuleRepositoryRecord(
            url: url, repositoryId: "publisher-A", name: "Example",
            modules: [module], lastRefreshed: Date(), refreshError: nil)
        let trust = KinetiqRepositoryTrustStore.shared
        defer { trust.revoke(repository) }
        XCTAssertEqual(trust.trust(for: repository), .approvalNeeded)
        trust.approve(repository)
        XCTAssertEqual(trust.trust(for: repository), .communityApproved)
        // Adding another module under the SAME owner should not prompt again.
        repository.modules.append(try sourceModule("extra-v1", identity: "EXTRA-VID-2"))
        XCTAssertEqual(trust.trust(for: repository), .communityApproved)
        // Reusing an existing ID with a different publisher identity is blocked.
        repository.modules[0] = try sourceModule("demo-v1", identity: "NEW-VID-IDENTITY")
        XCTAssertEqual(trust.trust(for: repository), .changedPublisher)
    }

    @MainActor
    func testTrustAllSourcesCoversSelectionsAndNewModules() throws {
        let first = try sourceModule("series-a", identity: "PUBLISHER-A")
        let second = try sourceModule("series-b", identity: "PUBLISHER-B")
        let url = URL(string: "https://example.org/\(UUID().uuidString)/repository.json")!
        var repository = ModuleRepositoryRecord(
            url: url, repositoryId: "community-repository", name: "Community",
            modules: [first, second], lastRefreshed: Date(), refreshError: nil)
        let store = KinetiqRepositoryTrustStore.shared
        defer { store.revoke(repository) }
        XCTAssertEqual(store.trust(for: repository), .approvalNeeded)
        XCTAssertTrue(store.approveAllSources(in: repository))
        XCTAssertEqual(store.trust(for: repository), .communityApproved)
        XCTAssertTrue(store.allowsRuntime(for: repository, installedModuleID: "series-a"))
        XCTAssertTrue(store.allowsRuntime(for: repository, installedModuleID: "series-b"))

        // A third legitimate module from the same catalogue owner inherits
        // the approval without an additional module-specific prompt.
        repository.modules.append(try sourceModule("series-c", identity: "PUBLISHER-C"))
        XCTAssertEqual(store.trust(for: repository), .communityApproved)
        XCTAssertTrue(store.allowsRuntime(for: repository, installedModuleID: "series-c"))

        // Changing the owner or an existing identity never inherits trust.
        repository.repositoryId = "different-owner"
        XCTAssertEqual(store.trust(for: repository), .changedPublisher)
        XCTAssertFalse(store.allowsRuntime(for: repository, installedModuleID: "series-a"))
        repository.repositoryId = "community-repository"
        store.revoke(repository)
        XCTAssertEqual(store.trust(for: repository), .approvalNeeded)
        XCTAssertFalse(store.allowsRuntime(for: repository, installedModuleID: "series-a"))
    }

    @MainActor
    func testTrustAllSourcesRefusesDuplicateModuleIDsAndOfflineApproval() throws {
        let first = try sourceModule("same-id", identity: "ORIGINAL")
        let duplicate = try sourceModule("same-id", identity: "OTHER")
        let url = URL(string: "https://example.org/\(UUID().uuidString)/repository.json")!
        var repository = ModuleRepositoryRecord(
            url: url, repositoryId: "community", name: "Example",
            modules: [first, duplicate], lastRefreshed: Date(), refreshError: nil)
        let store = KinetiqRepositoryTrustStore.shared
        defer { store.revoke(repository) }
        XCTAssertFalse(store.approveAllSources(in: repository))
        XCTAssertEqual(store.trust(for: repository), .approvalNeeded)
        repository.modules = [first]
        repository.refreshError = "Offline"
        XCTAssertFalse(store.approveAllSources(in: repository))
        repository.refreshError = nil
        XCTAssertTrue(store.approveAllSources(in: repository))
        XCTAssertTrue(store.allowsRuntime(for: repository, installedModuleID: "same-id"))
    }
}


// MARK: - Batch 05P-B update center deterministic contract tests
final class KinetiqModuleUpdateCenterContractTests: XCTestCase {
    private func module(_ version: String, hash: String,
                        changelog: [String]? = nil) throws -> ModuleRepositoryModule {
        var object: [String: Any] = [
            "moduleId": "example-module", "moduleFamilyId": "example",
            "moduleIdentity": "EXAMPLE-VID-01", "moduleIdentityNumber": 1,
            "contentType": "video", "version": version,
            "sha256": hash, "packageUrl": "https://example.org/mod.zip"
        ]
        if let changelog { object["changelog"] = changelog }
        return try JSONDecoder().decode(ModuleRepositoryModule.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    func testReleaseNotesAreTakenFromPublisherOnly() throws {
        let hash = String(repeating: "b", count: 64)
        let m = try module("1.1.0", hash: hash,
                           changelog: ["Fix subtitle sync", "", "  Faster search  "])
        let repository = ModuleRepositoryRecord(
            url: URL(string: "https://example.org/repository.json")!,
            repositoryId: "publisher", name: "Community", modules: [m],
            lastRefreshed: Date(), refreshError: nil
        )
        let source = ModuleSourceOption(repositoryURL: repository.url,
                                        repositoryName: repository.name, module: m)
        let installed = InstalledModuleRecord(
            sourceID: source.id, repositoryURL: repository.url.absoluteString,
            repositoryName: repository.name, moduleID: m.moduleId, name: "Example",
            version: "1.0.0", contentType: "video",
            packageSHA256: String(repeating: "a", count: 64), installedAt: Date(),
            directoryPath: "/old/module", manifestPath: "/old/module/manifest.json",
            entryScriptPath: "/old/module/index.js"
        )
        let offer = KinetiqModuleUpdateOffer(source: source, repository: repository,
                                             installed: installed)
        XCTAssertEqual(offer.releaseNotes, ["Fix subtitle sync", "Faster search"])
        XCTAssertEqual(offer.newVersion, "1.1.0")
        XCTAssertFalse(offer.revisionToken.isEmpty)
        let newModule = try module("1.2.0", hash: String(repeating: "c", count: 64))
        let later = KinetiqModuleUpdateOffer(
            source: ModuleSourceOption(repositoryURL: repository.url,
                                       repositoryName: repository.name, module: newModule),
            repository: repository, installed: installed)
        XCTAssertNotEqual(offer.revisionToken, later.revisionToken)
        XCTAssertTrue(later.releaseNotes.isEmpty)
    }

    func testRollbackFolderNamesCannotEscapeVault() {
        for name in ["../escape", "sub/folder", "\\", "..", ".hidden", ""] {
            XCTAssertFalse(KinetiqModuleRollbackVault.isSafeFolder(name))
        }
        XCTAssertTrue(KinetiqModuleRollbackVault.isSafeFolder(UUID().uuidString))
    }

    func testUpdatesNeverAutomaticallyInstallReusedVersionOrDowngrade() {
        let old = String(repeating: "a", count: 64)
        let new = String(repeating: "b", count: 64)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "2.0.0", listedSHA: new,
            installedVersion: "2.0.0", installedSHA: old), .sameVersionMutation)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "1.8.0", listedSHA: new,
            installedVersion: "2.0.0", installedSHA: old), .downgrade)
        XCTAssertEqual(KinetiqModuleReleasePolicy.status(
            listedVersion: "2.0.1", listedSHA: new,
            installedVersion: "2.0.0", installedSHA: old), .updateAvailable)
        XCTAssertFalse(KinetiqModuleReleaseState.sameVersionMutation.permitsAutomaticInstall)
        XCTAssertFalse(KinetiqModuleReleaseState.downgrade.permitsAutomaticInstall)
    }

    // MARK: Batch 05P-C - recovery and publisher-signature regression guards

    func testRollbackSnapshotRejectsModifiedFilesAndSymlinks() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetiq-05pc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let manifest = Data("{\"id\":\"example\"}".utf8)
        let script = Data("export function searchResults() { return []; }".utf8)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let scriptURL = temp.appendingPathComponent("index.js")
        try manifest.write(to: manifestURL)
        try script.write(to: scriptURL)
        let mh = SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined()
        let sh = SHA256.hash(data: script).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(KinetiqModuleRollbackVault.verifyFilePair(at: temp,
            manifestDigest: mh, scriptDigest: sh))
        try Data("modified".utf8).write(to: scriptURL)
        XCTAssertFalse(KinetiqModuleRollbackVault.verifyFilePair(at: temp,
            manifestDigest: mh, scriptDigest: sh))
        try FileManager.default.removeItem(at: scriptURL)
        try FileManager.default.createSymbolicLink(at: scriptURL, withDestinationURL: manifestURL)
        XCTAssertFalse(KinetiqModuleRollbackVault.verifyFilePair(at: temp,
            manifestDigest: mh, scriptDigest: sh))
    }

    func testUpdateFailureRecoveryIsNeededOnlyForChangedInstall() {
        let old = InstalledModuleRecord(
            sourceID: "repo|module", repositoryURL: "https://example.org/repository.json",
            repositoryName: "Demo", moduleID: "module", name: "Module", version: "1.0.0",
            contentType: "video", packageSHA256: String(repeating: "a", count: 64),
            installedAt: Date(), directoryPath: "/safe/module",
            manifestPath: "/safe/module/manifest.json", entryScriptPath: "/safe/module/index.js")
        let same = old
        XCTAssertFalse(KinetiqModuleUpdateSafety.requiresRecovery(from: old, current: same))
        XCTAssertTrue(KinetiqModuleUpdateSafety.requiresRecovery(from: old, current: nil))
        let new = InstalledModuleRecord(
            sourceID: old.sourceID, repositoryURL: old.repositoryURL,
            repositoryName: old.repositoryName, moduleID: old.moduleID,
            name: old.name, version: "1.1.0", contentType: "video",
            packageSHA256: String(repeating: "b", count: 64),
            installedAt: Date(), directoryPath: old.directoryPath,
            manifestPath: old.manifestPath, entryScriptPath: old.entryScriptPath)
        XCTAssertTrue(KinetiqModuleUpdateSafety.requiresRecovery(from: old, current: new))
    }

    func testPublisherSignaturesRejectTamperedBytesAndMessages() throws {
        let key = P256.Signing.PrivateKey()
        let message = Data("kinetiq-p256-v1\nfixture\n123\n".utf8)
        let signature = try key.signature(for: message).rawRepresentation
        XCTAssertTrue(KinetiqPublisherSignature.verify(
            signatureBase64: signature.base64EncodedString(), message: message,
            publicKey: key.publicKey.rawRepresentation))
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: signature.base64EncodedString(),
            message: Data("kinetiq-p256-v1\nfixture\n124\n".utf8),
            publicKey: key.publicKey.rawRepresentation))
        var corrupted = signature
        corrupted[0] ^= 0x01
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: corrupted.base64EncodedString(), message: message,
            publicKey: key.publicKey.rawRepresentation))
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: "not-a-signature", message: message,
            publicKey: key.publicKey.rawRepresentation))
        XCTAssertFalse(KinetiqPublisherSignature.verify(
            signatureBase64: signature.base64EncodedString() + "\n", message: message,
            publicKey: key.publicKey.rawRepresentation))
        // A testing key is not automatically trusted as a production publisher.
        XCTAssertFalse(KinetiqPublisherSignature.independentlyPinnedKeys.values.contains(
            key.publicKey.rawRepresentation))
    }

    func testRecoveryMustMatchExactSnapshotAndNeverSubstituteAnother() {
        let checksum = String(repeating: "a", count: 64)
        let newer = String(repeating: "b", count: 64)
        let record = InstalledModuleRecord(
            sourceID: "repo|module", repositoryURL: "https://example.org/index.json",
            repositoryName: "Demo", moduleID: "module", name: "Module", version: "1.0.0",
            contentType: "video", packageSHA256: checksum, installedAt: Date(),
            directoryPath: "/safe/module", manifestPath: "/safe/module/manifest.json",
            entryScriptPath: "/safe/module/index.js")
        let first = KinetiqModuleRollbackVault.Snapshot(
            record: record, folder: UUID().uuidString, savedAt: Date(),
            manifestDigest: checksum, scriptDigest: checksum)
        let second = KinetiqModuleRollbackVault.Snapshot(
            record: record, folder: UUID().uuidString, savedAt: Date(),
            manifestDigest: newer, scriptDigest: newer)
        XCTAssertEqual(KinetiqModuleRollbackVault.pinnedSnapshot(
            in: [first, second], sourceID: first.id, folder: first.folder,
            version: record.version, packageSHA256: checksum)?.folder, first.folder)
        XCTAssertNil(KinetiqModuleRollbackVault.pinnedSnapshot(
            in: [second], sourceID: first.id, folder: first.folder,
            version: record.version, packageSHA256: checksum))
        XCTAssertNil(KinetiqModuleRollbackVault.pinnedSnapshot(
            in: [first], sourceID: first.id, folder: first.folder,
            version: "1.1.0", packageSHA256: checksum))
        XCTAssertNil(KinetiqModuleRollbackVault.pinnedSnapshot(
            in: [first], sourceID: first.id, folder: first.folder,
            version: record.version, packageSHA256: newer))
    }

    func testRollbackFolderRequiresCanonicalUUID() {
        XCTAssertTrue(KinetiqModuleRollbackVault.isSafeFolder(UUID().uuidString))
        for folder in ["../escape", "random", ".hidden", "sub/folder", "", "ABC"] {
            XCTAssertFalse(KinetiqModuleRollbackVault.isSafeFolder(folder))
        }
    }
}
