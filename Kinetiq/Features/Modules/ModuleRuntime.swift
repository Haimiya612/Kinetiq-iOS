import AVKit
import Foundation
import JavaScriptCore
import SwiftUI
import UIKit

// MARK: - Runtime Errors

enum ModuleRuntimeError: LocalizedError {
    case invalidManifest
    case unsupportedContentType
    case invalidBaseURL
    case contextUnavailable
    case scriptLoadFailed(String)
    case missingHandler(String)
    case handlerFailed(String)
    case handlerTimedOut
    case invalidArguments
    case invalidRequestURL
    case insecureRequest
    case invalidHTTPMethod
    case invalidHeaders
    case responseTooLarge
    case invalidHTTPResponse
    case invalidResult
    case invalidStream

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The installed module manifest is invalid."

        case .unsupportedContentType:
            return "This browser currently supports video modules."

        case .invalidBaseURL:
            return "The module does not provide a valid HTTPS base URL."

        case .contextUnavailable:
            return "Kinetiq could not create the JavaScript runtime."

        case .scriptLoadFailed(let message):
            return "The module could not be loaded: \(message)"

        case .missingHandler(let name):
            return "The module does not provide \(name)."

        case .handlerFailed(let message):
            return message

        case .handlerTimedOut:
            return "The module took too long to respond."

        case .invalidArguments:
            return "Kinetiq could not prepare the module request."

        case .invalidRequestURL:
            return "The module requested an invalid URL."

        case .insecureRequest:
            return "Module requests must use HTTPS."

        case .invalidHTTPMethod:
            return "The module requested an unsupported HTTP method."

        case .invalidHeaders:
            return "The module supplied invalid HTTP headers."

        case .responseTooLarge:
            return "The module response exceeded its configured size limit."

        case .invalidHTTPResponse:
            return "The source returned an invalid HTTP response."

        case .invalidResult:
            return "The module returned data Kinetiq could not understand."

        case .invalidStream:
            return "The module did not return a valid playable stream."
        }
    }
}

// MARK: - Runtime Manifest

private struct RuntimeManifest: Decodable {
    let contentType: String?
    let config: RuntimeManifestConfiguration
}

private struct RuntimeManifestConfiguration: Decodable {
    let baseUrl: String
    let runtime: RuntimeManifestRuntime
    let caps: RuntimeManifestCaps
}

private struct RuntimeManifestRuntime: Decodable {
    let entry: String
    let mode: String
}

private struct RuntimeManifestCaps: Decodable {
    let homeMaxResults: Int
    let maxResponseBytes: Int
    let timeoutMs: Int
    let maxConcurrentRequests: Int
}

// MARK: - Runtime Request Gate

private actor ModuleRequestGate {
    private let maximumRequests: Int
    private var activeRequests = 0

    private var waitingRequests: [
        CheckedContinuation<Void, Never>
    ] = []

    init(maximumRequests: Int) {
        self.maximumRequests = max(1, maximumRequests)
    }

    func acquire() async {
        if activeRequests < maximumRequests {
            activeRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingRequests.append(continuation)
        }
    }

    func release() {
        if waitingRequests.isEmpty {
            activeRequests = max(0, activeRequests - 1)
        } else {
            waitingRequests.removeFirst().resume()
        }
    }
}

// MARK: - Module Networking

/// Immutable cookie values can safely cross the URLSession actor boundary.
/// They are never written to defaults, diagnostics, or the module catalogue.
struct ModuleStreamCookie: Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
}

private actor SynthetiqModuleNetworkClient {
    private let baseURL: URL
    private let maximumResponseBytes: Int
    private let timeoutMilliseconds: Int

    private let gate: ModuleRequestGate
    private let session: URLSession

    init(
        baseURL: URL,
        maximumResponseBytes: Int,
        timeoutMilliseconds: Int,
        maximumConcurrentRequests: Int
    ) {
        self.baseURL = baseURL
        self.maximumResponseBytes = maximumResponseBytes
        self.timeoutMilliseconds = timeoutMilliseconds

        gate = ModuleRequestGate(
            maximumRequests: maximumConcurrentRequests
        )

        let configuration = URLSessionConfiguration.ephemeral

        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil

        // Each ephemeral session has transient cookie storage. Retain
        // source cookies for subsequent module requests without persisting
        // them to the app's shared cookie store on disk.
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        session = URLSession(configuration: configuration)
    }

    func cookies(for streamURL: URL) -> [ModuleStreamCookie] {
        guard streamURL.scheme?.lowercased() == "https",
              let cookieStorage = session.configuration.httpCookieStorage else {
            return []
        }

        return Array((cookieStorage.cookies(for: streamURL) ?? []).prefix(40))
            .map { cookie in
                ModuleStreamCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    isSecure: cookie.isSecure
                )
            }
    }

    func fetch(
        rawURL: String,
        headersJSON: String,
        method: String,
        body: String
    ) async throws -> [String: Any] {
        await gate.acquire()

        defer {
            Task {
                await gate.release()
            }
        }

        guard
            let resolvedURL = URL(
                string: rawURL,
                relativeTo: baseURL
            )?.absoluteURL,
            let components = URLComponents(
                url: resolvedURL,
                resolvingAgainstBaseURL: true
            ),
            components.host != nil,
            components.user == nil,
            components.password == nil
        else {
            throw ModuleRuntimeError.invalidRequestURL
        }

        guard components.scheme?.lowercased() == "https" else {
            throw ModuleRuntimeError.insecureRequest
        }

        let normalizedMethod = method
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let supportedMethods: Set<String> = [
            "GET",
            "HEAD",
            "POST",
            "PUT",
            "PATCH",
            "DELETE"
        ]

        guard supportedMethods.contains(normalizedMethod) else {
            throw ModuleRuntimeError.invalidHTTPMethod
        }

        guard let headerData = headersJSON.data(using: .utf8),
              let headers = try? JSONDecoder().decode(
                [String: String].self,
                from: headerData
              ) else {
            throw ModuleRuntimeError.invalidHeaders
        }

        var request = URLRequest(url: resolvedURL)

        request.httpMethod = normalizedMethod
        request.timeoutInterval =
            Double(timeoutMilliseconds) / 1_000

        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        for (name, value) in headers {
            guard
                !name.isEmpty,
                !name.contains("\r"),
                !name.contains("\n"),
                !value.contains("\r"),
                !value.contains("\n")
            else {
                throw ModuleRuntimeError.invalidHeaders
            }

            request.setValue(
                value,
                forHTTPHeaderField: name
            )
        }

        if !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }

        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await session.data(
                for: request
            )
        } catch {
            throw ModuleRuntimeError.handlerFailed(
                "Source request failed: \(error.localizedDescription)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModuleRuntimeError.invalidHTTPResponse
        }

        guard
            httpResponse.url?.scheme?.lowercased() == "https"
        else {
            throw ModuleRuntimeError.insecureRequest
        }

        guard responseData.count <= maximumResponseBytes else {
            throw ModuleRuntimeError.responseTooLarge
        }

        let responseHeaders = Dictionary(
            uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap {
                key, value -> (String, String)? in

                guard let key = key as? String else {
                    return nil
                }

                return (
                    key.lowercased(),
                    String(describing: value)
                )
            }
        )

        let responseBody = String(
            data: responseData,
            encoding: .utf8
        ) ?? ""

        return [
            "status": httpResponse.statusCode,
            "ok": (200...299).contains(httpResponse.statusCode),
            "url": httpResponse.url?.absoluteString ?? "",
            "headers": responseHeaders,
            "body": responseBody
        ]
    }
}

// MARK: - JavaScript Module Runtime

/// Executes an installed Synthetiq-compatible module in JavaScriptCore.
///
/// JavaScriptCore does not expose a browser DOM or Node.js environment.
/// The module receives a deliberately small native networking bridge.
///
/// IMPORTANT:
/// JavaScriptCore is an execution environment, not an operating-system
/// security sandbox. Only execute packages that the user has explicitly
/// trusted.
final class SynthetiqModuleRuntime: @unchecked Sendable {

    let baseURL: URL
    let timeoutMilliseconds: Int
    let maximumHomeResults: Int
    let moduleName: String

    private let jsQueue = DispatchQueue(
        label: "com.kinetiq.modules.javascript",
        qos: .userInitiated
    )

    private let networkClient: SynthetiqModuleNetworkClient

    // This context is accessed only on jsQueue.
    private var context: JSContext?

    // These continuations are also accessed only on jsQueue.
    private var pendingCalls: [
        String: CheckedContinuation<Any, Error>
    ] = [:]

    // MARK: Initialization

    init(record: InstalledModuleRecord) throws {
        let manifestData: Data

        do {
            manifestData = try Data(
                contentsOf: record.manifestURL
            )
        } catch {
            throw ModuleRuntimeError.invalidManifest
        }

        let manifest: RuntimeManifest

        do {
            manifest = try JSONDecoder().decode(
                RuntimeManifest.self,
                from: manifestData
            )
        } catch {
            throw ModuleRuntimeError.invalidManifest
        }

        guard record.contentType.lowercased() == "video",
              manifest.contentType?.lowercased() == "video" else {
            throw ModuleRuntimeError.unsupportedContentType
        }

        guard manifest.config.runtime.mode.lowercased() == "local" else {
            throw ModuleRuntimeError.invalidManifest
        }

        let moduleRootPath = URL(
            fileURLWithPath: record.directoryPath
        ).standardizedFileURL.path

        let entryScriptPath = record.entryScriptURL
            .standardizedFileURL.path

        guard entryScriptPath.hasPrefix(moduleRootPath + "/"),
              FileManager.default.fileExists(atPath: entryScriptPath) else {
            throw ModuleRuntimeError.invalidManifest
        }

        guard
            let parsedBaseURL = URL(
                string: manifest.config.baseUrl
            ),
            parsedBaseURL.scheme?.lowercased() == "https",
            parsedBaseURL.host != nil,
            parsedBaseURL.user == nil,
            parsedBaseURL.password == nil
        else {
            throw ModuleRuntimeError.invalidBaseURL
        }

        let caps = manifest.config.caps

        let responseLimit = min(
            max(caps.maxResponseBytes, 1),
            8_000_000
        )

        let timeout = min(
            max(caps.timeoutMs, 500),
            30_000
        )

        let homeLimit = min(
            max(caps.homeMaxResults, 1),
            100
        )

        let concurrency = min(
            max(caps.maxConcurrentRequests, 1),
            12
        )

        baseURL = parsedBaseURL
        timeoutMilliseconds = timeout
        maximumHomeResults = homeLimit
        moduleName = record.name

        networkClient = SynthetiqModuleNetworkClient(
            baseURL: parsedBaseURL,
            maximumResponseBytes: responseLimit,
            timeoutMilliseconds: timeout,
            maximumConcurrentRequests: concurrency
        )

        var initializationError: Error?

        jsQueue.sync {
            guard let javascriptContext = JSContext() else {
                initializationError =
                    ModuleRuntimeError.contextUnavailable
                return
            }

            context = javascriptContext

            javascriptContext.exceptionHandler = { _, exception in
                NSLog(
                    "Kinetiq module JavaScript exception: %@",
                    exception?.toString() ?? "Unknown exception"
                )
            }

            let fetchBridge:
                @convention(block)
                (String, String, String, String, String) -> Void = {
                    [weak self] url, headers, method, body, requestID in

                    guard let self else {
                        return
                    }

                    Task {
                        do {
                            let payload = try await self.networkClient.fetch(
                                rawURL: url,
                                headersJSON: headers,
                                method: method,
                                body: body
                            )

                            let data = try JSONSerialization.data(
                                withJSONObject: payload,
                                options: [.fragmentsAllowed]
                            )

                            let payloadJSON = String(
                                data: data,
                                encoding: .utf8
                            ) ?? "{}"

                            self.resolveFetch(
                                requestID,
                                payloadJSON: payloadJSON,
                                error: ""
                            )
                        } catch {
                            self.resolveFetch(
                                requestID,
                                payloadJSON: "{}",
                                error: error.localizedDescription
                            )
                        }
                    }
                }

            let completionBridge:
                @convention(block)
                (String, String, String) -> Void = {
                    [weak self] callID, resultJSON, errorMessage in

                    self?.finishCall(
                        callID,
                        resultJSON: resultJSON,
                        errorMessage: errorMessage
                    )
                }

            javascriptContext.setObject(
                fetchBridge,
                forKeyedSubscript: "__kinetiqFetch" as NSString
            )

            javascriptContext.setObject(
                completionBridge,
                forKeyedSubscript: "__kinetiqComplete" as NSString
            )

            javascriptContext.evaluateScript(
                Self.runtimeBootstrap
            )

            if let exception = javascriptContext.exception {
                initializationError =
                    ModuleRuntimeError.scriptLoadFailed(
                        exception.toString()
                    )
                return
            }

            let script: String

            do {
                script = try String(
                    contentsOf: record.entryScriptURL,
                    encoding: .utf8
                )
            } catch {
                initializationError =
                    ModuleRuntimeError.scriptLoadFailed(
                        error.localizedDescription
                    )
                return
            }

            javascriptContext.exception = nil

            javascriptContext.evaluateScript(
                script,
                withSourceURL: record.entryScriptURL
            )

            if let exception = javascriptContext.exception {
                initializationError =
                    ModuleRuntimeError.scriptLoadFailed(
                        exception.toString()
                    )
            }
        }

        if let initializationError {
            throw initializationError
        }
    }

    /// Returns only cookies that match the requested HTTPS stream host.
    /// The native video player converts them to AVURLAsset cookies.
    func cookies(for streamURL: URL) async -> [ModuleStreamCookie] {
        await networkClient.cookies(for: streamURL)
    }

    // MARK: JavaScript Runtime Bootstrap

    private static let runtimeBootstrap = """
    (() => {
        const pending = Object.create(null);
        let nextRequestID = 0;

        globalThis.console = globalThis.console || {
            log: function() {},
            info: function() {},
            warn: function() {},
            error: function() {}
        };

        globalThis.fetchv2 = function(
            url,
            headers,
            method,
            body
        ) {
            return new Promise((resolve, reject) => {
                const requestID = String(++nextRequestID);

                pending[requestID] = {
                    resolve: resolve,
                    reject: reject
                };

                let serializedHeaders = "{}";

                try {
                    serializedHeaders = JSON.stringify(headers || {});
                } catch (error) {
                    delete pending[requestID];
                    reject(new Error("Invalid request headers"));
                    return;
                }

                try {
                    __kinetiqFetch(
                        String(url),
                        serializedHeaders,
                        String(method || "GET"),
                        body == null ? "" : String(body),
                        requestID
                    );
                } catch (error) {
                    delete pending[requestID];
                    reject(error);
                }
            });
        };

        globalThis.__kinetiqResolveFetch = function(
            requestID,
            payloadJSON,
            errorMessage
        ) {
            const request = pending[String(requestID)];

            if (!request) {
                return;
            }

            delete pending[String(requestID)];

            if (errorMessage) {
                request.reject(new Error(String(errorMessage)));
                return;
            }

            try {
                const raw = JSON.parse(payloadJSON || "{}");
                const rawHeaders = raw.headers || {};

                const response = {
                    status: Number(raw.status || 0),
                    ok: Boolean(raw.ok),
                    url: String(raw.url || ""),
                    body: String(raw.body || ""),
                    headers: {
                        get: function(name) {
                            const wanted = String(name).toLowerCase();

                            const key = Object.keys(rawHeaders).find(
                                item => item.toLowerCase() === wanted
                            );

                            return key ? String(rawHeaders[key]) : null;
                        }
                    },
                    json: async function() {
                        return JSON.parse(String(raw.body || ""));
                    },
                    text: async function() {
                        return String(raw.body || "");
                    }
                };

                request.resolve(response);
            } catch (error) {
                request.reject(error);
            }
        };

        globalThis.__kinetiqInvoke = async function(
            handlerName,
            argumentsJSON,
            callID
        ) {
            try {
                const handler = globalThis[String(handlerName)];

                if (typeof handler !== "function") {
                    throw new Error(
                        "Missing module handler: " + String(handlerName)
                    );
                }

                const args = JSON.parse(argumentsJSON || "[]");
                const result = await handler(...args);

                const resultJSON = JSON.stringify(
                    result === undefined ? null : result
                ) || "null";

                __kinetiqComplete(
                    String(callID),
                    resultJSON,
                    ""
                );
            } catch (error) {
                const message = error && error.message
                    ? error.message
                    : String(error);

                __kinetiqComplete(
                    String(callID),
                    "",
                    message
                );
            }
        };
    })();
    """

    // MARK: Call Module Handler

    func call(
        handler: String,
        arguments: [Any]
    ) async throws -> Any {
        guard JSONSerialization.isValidJSONObject(arguments) else {
            throw ModuleRuntimeError.invalidArguments
        }

        let argumentsData = try JSONSerialization.data(
            withJSONObject: arguments,
            options: [.fragmentsAllowed]
        )

        guard let argumentsJSON = String(
            data: argumentsData,
            encoding: .utf8
        ) else {
            throw ModuleRuntimeError.invalidArguments
        }

        let callID = UUID().uuidString
        let timeout = timeoutMilliseconds

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Any, Error>) in

            jsQueue.async { [self] in
                guard let context else {
                    continuation.resume(
                        throwing: ModuleRuntimeError.contextUnavailable
                    )
                    return
                }

                pendingCalls[callID] = continuation

                context.exception = nil

                context.objectForKeyedSubscript(
                    "__kinetiqInvoke"
                )?.call(
                    withArguments: [
                        handler,
                        argumentsJSON,
                        callID
                    ]
                )

                if let exception = context.exception {
                    finishCall(
                        callID,
                        resultJSON: "",
                        errorMessage: exception.toString()
                    )
                    return
                }

                Task.detached { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: UInt64(timeout) * 1_000_000
                    )

                    guard let self else {
                        return
                    }

                    self.jsQueue.async {
                        self.finishCall(
                            callID,
                            resultJSON: "",
                            errorMessage: ModuleRuntimeError
                                .handlerTimedOut
                                .localizedDescription
                        )
                    }
                }
            }
        }
    }

    // MARK: Resolve Networking Promise

    private func resolveFetch(
        _ requestID: String,
        payloadJSON: String,
        error: String
    ) {
        jsQueue.async { [self] in
            guard let context else {
                return
            }

            context.objectForKeyedSubscript(
                "__kinetiqResolveFetch"
            )?.call(
                withArguments: [
                    requestID,
                    payloadJSON,
                    error
                ]
            )
        }
    }

    // MARK: Resolve Handler Call

    private func finishCall(
        _ callID: String,
        resultJSON: String,
        errorMessage: String
    ) {
        jsQueue.async { [self] in
            guard let continuation = pendingCalls.removeValue(
                forKey: callID
            ) else {
                return
            }

            if !errorMessage.isEmpty {
                if errorMessage ==
                    ModuleRuntimeError.handlerTimedOut.localizedDescription {
                    continuation.resume(
                        throwing: ModuleRuntimeError.handlerTimedOut
                    )
                } else {
                    continuation.resume(
                        throwing: ModuleRuntimeError.handlerFailed(
                            errorMessage
                        )
                    )
                }
                return
            }

            guard
                let data = resultJSON.data(using: .utf8),
                let result = try? JSONSerialization.jsonObject(
                    with: data,
                    options: [.fragmentsAllowed]
                )
            else {
                continuation.resume(
                    throwing: ModuleRuntimeError.invalidResult
                )
                return
            }

            continuation.resume(returning: result)
        }
    }
}

// MARK: - Anime Models

struct ModuleAnimeItem: Identifiable {
    let id: String
    let title: String
    let href: String
    let imageURL: URL?
}

struct ModuleAnimeEpisode: Identifiable {
    let id: String
    let number: String
    let href: String
    let subAvailable: Bool
    let dubAvailable: Bool
}

struct ModuleResolvedStream: Identifiable, Sendable {
    let id = UUID()
    /// The episode title; distinct from the provider's server label.
    let title: String
    let label: String
    let url: URL
    let headers: [String: String]
    let streamType: String
    var cookies: [ModuleStreamCookie] = []

    /// Never display the full URL: it may contain signed query tokens.
    var hostName: String { url.host ?? "Unknown host" }
}

// MARK: - Module Episode Playback Session

/// Owns one module-backed series queue. It never writes to the local media
/// queue or local playback history.
@MainActor
final class ModuleEpisodePlaybackSession: ObservableObject, Identifiable {

    let id = UUID()
    let animeTitle: String
    let sourceName: String
    let sourceID: String?
    let animeItem: ModuleAnimeItem?

    @Published private(set) var episodes: [ModuleAnimeEpisode]
    @Published private(set) var currentEpisode: ModuleAnimeEpisode?
    @Published private(set) var currentEpisodeIndex: Int?
    @Published private(set) var currentStream: ModuleResolvedStream?
    @Published private(set) var availableStreams: [ModuleResolvedStream] = []
    @Published private(set) var currentEpisodeTitle: String
    @Published private(set) var selectedLanguage = "sub"
    @Published private(set) var isResolving = false
    @Published private(set) var playbackError: String?

    private let runtime: SynthetiqModuleRuntime
    private var activeRequestID: UUID?

    init(
        animeTitle: String,
        episodes: [ModuleAnimeEpisode],
        runtime: SynthetiqModuleRuntime,
        sourceID: String? = nil,
        animeItem: ModuleAnimeItem? = nil
    ) {
        self.sourceID = sourceID
        self.animeItem = animeItem
        self.animeTitle = animeTitle
        self.episodes = episodes
        self.runtime = runtime
        self.sourceName = runtime.moduleName
        self.currentEpisodeTitle = animeTitle
    }

    var upcomingEpisodes: [ModuleAnimeEpisode] {
        guard let currentEpisodeIndex,
              episodes.indices.contains(currentEpisodeIndex) else {
            return episodes
        }

        return Array(episodes.dropFirst(currentEpisodeIndex + 1))
    }

    func supports(
        _ language: String,
        for episode: ModuleAnimeEpisode
    ) -> Bool {
        switch language.lowercased() {
        case "sub":
            return episode.subAvailable
        case "dub":
            return episode.dubAvailable
        default:
            return false
        }
    }

    private func preferredLanguage(
        for episode: ModuleAnimeEpisode
    ) -> String? {
        if supports(selectedLanguage, for: episode) {
            return selectedLanguage
        }

        if supports("sub", for: episode) {
            return "sub"
        }

        if supports("dub", for: episode) {
            return "dub"
        }

        return nil
    }

    @discardableResult
    func play(
        episode: ModuleAnimeEpisode,
        language: String
    ) async -> Bool {
        guard let index = episodes.firstIndex(
            where: { $0.id == episode.id }
        ) else {
            playbackError = "This episode is no longer in the episode list."
            return false
        }

        guard supports(language, for: episode) else {
            playbackError = "This episode is not available in the selected language."
            return false
        }

        guard !isResolving else {
            return false
        }

        let requestID = UUID()
        activeRequestID = requestID
        isResolving = true
        playbackError = nil

        defer {
            if activeRequestID == requestID {
                isResolving = false
            }
        }

        let episodeTitle =
            "\(animeTitle) -- Episode \(episode.number)"

        do {
            // The Synthetiq handler expects the episode href. Keep it
            // first for modules such as JustAnime that already work.
            // Only try the ID as a compatibility fallback.
            let references = [episode.href, episode.id]
            var attempted = Set<String>()
            var lastError: Error?

            for rawReference in references {
                let reference = rawReference.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !reference.isEmpty,
                      attempted.insert(reference).inserted else {
                    continue
                }

                do {
                    let response = try await runtime.call(
                        handler: "extractStreamUrl",
                        arguments: [
                            reference,
                            language.lowercased()
                        ]
                    )

                    var choices = try ModuleRuntimeDecoder.streams(
                        from: response,
                        title: episodeTitle,
                        baseURL: runtime.baseURL
                    )

                    guard activeRequestID == requestID else {
                        return false
                    }

                    // Capture cookies only for each HTTPS stream host;
                    // never pass source-domain cookies to unrelated CDNs.
                    for index in choices.indices {
                        let streamURL = choices[index].url
                        let sourceCookies = await runtime.cookies(
                            for: streamURL
                        )
                        choices[index].cookies = sourceCookies
                    }

                    guard activeRequestID == requestID else {
                        return false
                    }

                    guard let preferredStream = choices.first else {
                        throw ModuleRuntimeError.invalidStream
                    }

                    currentEpisode = episode
                    currentEpisodeIndex = index
                    currentEpisodeTitle = episodeTitle
                    selectedLanguage = language.lowercased()
                    availableStreams = choices
                    currentStream = preferredStream
                    playbackError = nil
                    return true
                } catch {
                    if let moduleError = error as? ModuleRuntimeError,
                       case .handlerTimedOut = moduleError {
                        throw moduleError
                    }
                    lastError = error
                }
            }

            throw lastError ?? ModuleRuntimeError.invalidStream
        } catch {
            guard activeRequestID == requestID else {
                return false
            }

            playbackError = error.localizedDescription
            return false
        }
    }

    /// Changes the active server for this episode without rerunning JS.
    /// The player observes currentStream and performs the actual handoff.
    @discardableResult
    func selectStream(_ stream: ModuleResolvedStream) -> Bool {
        guard !isResolving,
              availableStreams.contains(where: { $0.id == stream.id }) else {
            return false
        }

        playbackError = nil
        currentStream = stream
        return true
    }

    @discardableResult
    func selectEpisode(_ episode: ModuleAnimeEpisode) async -> Bool {
        guard let language = preferredLanguage(for: episode) else {
            playbackError = "No playable language is available for this episode."
            return false
        }

        return await play(
            episode: episode,
            language: language
        )
    }

    func playNext() async {
        guard !isResolving else { return }

        playbackError = nil
        let startIndex = (currentEpisodeIndex ?? -1) + 1

        guard episodes.indices.contains(startIndex) else {
            playbackError = "There are no more episodes in this series."
            return
        }

        for episode in episodes.dropFirst(startIndex) {
            guard let language = preferredLanguage(for: episode) else {
                continue
            }

            if await play(episode: episode, language: language) {
                return
            }
        }

        if playbackError == nil {
            playbackError = "There are no more playable episodes in this series."
        }
    }

    func playPrevious() async {
        guard !isResolving else { return }

        playbackError = nil
        guard let currentEpisodeIndex,
              currentEpisodeIndex > 0 else {
            playbackError = "You are already at the first episode."
            return
        }

        for index in stride(
            from: currentEpisodeIndex - 1,
            through: 0,
            by: -1
        ) {
            let episode = episodes[index]

            guard let language = preferredLanguage(for: episode) else {
                continue
            }

            if await play(episode: episode, language: language) {
                return
            }
                    }

        if playbackError == nil {
            playbackError = "There are no previous playable episodes."
        }
    }

    func retryCurrent() async -> Bool {
        guard let currentEpisode else {
            playbackError = "There is no current episode to retry."
            return false
        }

        return await play(
            episode: currentEpisode,
            language: selectedLanguage
        )
    }
}

// MARK: - Runtime Result Decoder

enum ModuleRuntimeDecoder {

    private static let listKeys = [
        "results",
        "items",
        "episodes",
        "data",
        "anime",
        "list",
        "entries",
        "records",
        "result"
    ]

    private static func dictionaryList(
        from value: Any,
        depth: Int = 0
    ) -> [[String: Any]] {
        guard depth <= 4 else {
            return []
        }

        if let direct = value as? [[String: Any]] {
            return direct
        }

        guard let dictionary = value as? [String: Any] else {
            return []
        }

        for key in listKeys {
            guard let nestedValue = dictionary[key] else {
                continue
            }

            if let direct = nestedValue as? [[String: Any]] {
                return direct
            }

            let nested = dictionaryList(
                from: nestedValue,
                depth: depth + 1
            )

            if !nested.isEmpty {
                return nested
            }
        }

        return []
    }

    private static func string(
        _ dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty {
                return value
            }

            if let number = dictionary[key] as? NSNumber {
                return number.stringValue
            }
        }

        return nil
    }

    private static func resolvedURL(
        _ value: String?,
        baseURL: URL
    ) -> URL? {
        guard let value else {
            return nil
        }

        guard let url = URL(
            string: value,
            relativeTo: baseURL
        )?.absoluteURL,
        let scheme = url.scheme?.lowercased(),
        ["https", "http"].contains(scheme),
        url.host != nil else {
            return nil
        }

        return url
    }

    private static func boolean(
        _ dictionary: [String: Any],
        key: String,
        fallback: Bool
    ) -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }

        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }

        return fallback
    }

    // MARK: Search Results

    static func searchResults(
        from value: Any,
        baseURL: URL,
        maximumResults: Int
    ) -> [ModuleAnimeItem] {
        dictionaryList(from: value)
            .compactMap { item in
                guard
                    let title = string(
                        item,
                        keys: ["title", "name", "label"]
                    ),
                    let href = string(
                        item,
                        keys: ["href", "url", "link"]
                    )
                else {
                    return nil
                }

                let id = string(
                    item,
                    keys: ["id", "animeId", "seriesId"]
                ) ?? href

                let image = string(
                    item,
                    keys: [
                        "image",
                        "poster",
                        "thumbnail",
                        "cover"
                    ]
                )

                return ModuleAnimeItem(
                    id: id,
                    title: title,
                    href: href,
                    imageURL: resolvedURL(
                        image,
                        baseURL: baseURL
                    )
                )
            }
            .prefix(maximumResults)
            .map { $0 }
    }

    // MARK: Details

    static func details(
        from value: Any,
        fallback: ModuleAnimeItem,
        baseURL: URL
    ) -> ModuleAnimeItem {
        let dictionary = value as? [String: Any] ?? [:]

        let title = string(
            dictionary,
            keys: ["title", "name"]
        ) ?? fallback.title

        let href = string(
            dictionary,
            keys: ["href", "url", "link"]
        ) ?? fallback.href

        let id = string(
            dictionary,
            keys: ["id", "animeId", "seriesId"]
        ) ?? fallback.id

        let image = string(
            dictionary,
            keys: [
                "image",
                "poster",
                "thumbnail",
                "cover"
            ]
        )

        return ModuleAnimeItem(
            id: id,
            title: title,
            href: href,
            imageURL: resolvedURL(
                image,
                baseURL: baseURL
            ) ?? fallback.imageURL
        )
    }

    // MARK: Episodes

    static func episodes(
        from value: Any
    ) -> [ModuleAnimeEpisode] {
        dictionaryList(from: value)
            .enumerated()
            .compactMap { index, episode in
                guard let href = string(
                    episode,
                    keys: [
                        "href",
                        "url",
                        "link",
                        "episodeUrl",
                        "episodeURL",
                        "watchUrl",
                        "watchURL",
                        "episodeLink",
                        "src",
                        "episodeId",
                        "episode_id",
                        "id"
                    ]
                ) else {
                    return nil
                }

                let number = string(
                    episode,
                    keys: [
                        "number",
                        "episode",
                        "episodeNumber",
                        "episode_number",
                        "ep",
                        "title",
                        "name"
                    ]
                ) ?? "\(index + 1)"

                let id = string(
                    episode,
                    keys: [
                        "id",
                        "episodeId",
                        "episode_id",
                        "slug",
                        "key"
                    ]
                ) ?? href

                return ModuleAnimeEpisode(
                    id: id,
                    number: number,
                    href: href,
                    subAvailable: boolean(
                        episode,
                        key: "subAvailable",
                        fallback: true
                    ),
                    dubAvailable: boolean(
                        episode,
                        key: "dubAvailable",
                        fallback: false
                    )
                )
            }
    }

    // MARK: Stream Resolution

    /// The Synthetiq V3 contract permits [label, URL], a direct URL, and
    /// stream dictionaries. This decoder also supports lists of labeled
    /// alternatives from compatible providers. A single malformed server
    /// never prevents another valid server from being used.
    static func streams(
        from value: Any,
        title: String,
        baseURL: URL
    ) throws -> [ModuleResolvedStream] {
        let root = value as? [String: Any] ?? [:]
        let inheritedHeaders = root["headers"] as? [String: String] ?? [:]
        let inheritedType = string(
            root,
            keys: ["streamType", "type"]
        ) ?? "auto"

        var choices: [ModuleResolvedStream] = []
        var seen = Set<String>()
        let maximumChoices = 24

        func isServerLabel(_ text: String) -> Bool {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return false }
            let lowered = value.lowercased()
            return !value.contains("/")
                && !value.contains("://")
                && !lowered.contains(".m3u8")
                && !lowered.contains(".mp4")
        }

        func append(
            urlString: String?,
            label: String?,
            headers: [String: String],
            streamType: String
        ) {
            guard choices.count < maximumChoices,
                  let urlString,
                  let url = resolvedURL(urlString, baseURL: baseURL) else {
                return
            }

            let displayLabel = label?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            // Labels originate from third-party module output. A label that
            // looks like a URL could accidentally expose a signed token.
            let sensitiveLabel = displayLabel.lowercased().contains("://")
                || displayLabel.lowercased().contains("token=")
                || displayLabel.lowercased().contains("signature=")
            let safeLabel = displayLabel.isEmpty || sensitiveLabel
                ? (url.host ?? "Auto")
                : String(displayLabel.prefix(80))

            // Keep distinct header-bearing streams even on the same URL.
            let headerSignature = headers.keys.sorted().map {
                "\($0.lowercased())=\(headers[$0] ?? "")"
            }.joined(separator: "&")
            let key = url.absoluteString + "|" + headerSignature

            guard seen.insert(key).inserted else { return }

            choices.append(
                ModuleResolvedStream(
                    title: title,
                    label: safeLabel,
                    url: url,
                    headers: headers,
                    streamType: streamType
                )
            )
        }

        func parseEntry(_ entry: Any, defaultLabel: String? = nil) {
            if let urlString = entry as? String {
                append(
                    urlString: urlString,
                    label: defaultLabel,
                    headers: inheritedHeaders,
                    streamType: inheritedType
                )
                return
            }

            if let pair = entry as? [String],
               pair.count == 2,
               isServerLabel(pair[0]) {
                append(
                    urlString: pair[1],
                    label: pair[0],
                    headers: inheritedHeaders,
                    streamType: inheritedType
                )
                return
            }

            if let dictionary = entry as? [String: Any] {
                let itemHeaders = dictionary["headers"] as? [String: String] ?? [:]
                let mergedHeaders = inheritedHeaders.merging(itemHeaders) {
                    _, incoming in incoming
                }

                let streamLabel = string(
                    dictionary,
                    keys: ["label", "name", "title", "quality", "server"]
                ) ?? defaultLabel

                let streamType = string(
                    dictionary,
                    keys: ["streamType", "type"]
                ) ?? inheritedType

                append(
                    urlString: string(
                        dictionary,
                        keys: ["url", "streamUrl", "file", "src", "href", "link"]
                    ),
                    label: streamLabel,
                    headers: mergedHeaders,
                    streamType: streamType
                )
            }
        }

        if let direct = value as? String {
            parseEntry(direct, defaultLabel: "Auto")
        } else if let list = value as? [Any] {
            if list.count == 2,
               let first = list[0] as? String,
               let second = list[1] as? String,
               isServerLabel(first) {
                parseEntry([first, second])
            } else {
                for element in list.prefix(maximumChoices) {
                    parseEntry(element)
                }
            }
        } else if !root.isEmpty {
            for key in ["streams", "sources", "servers", "links"] {
                guard let group = root[key] else { continue }

                if let list = group as? [Any] {
                    if list.count == 2,
                       let first = list[0] as? String,
                       let second = list[1] as? String,
                       isServerLabel(first) {
                        parseEntry([first, second])
                    } else {
                        for element in list.prefix(maximumChoices) {
                            parseEntry(element)
                        }
                    }
                } else if let mapping = group as? [String: Any] {
                    for key in mapping.keys.sorted().prefix(maximumChoices) {
                        if let entry = mapping[key] {
                            parseEntry(entry, defaultLabel: key)
                        }
                    }
                } else {
                    parseEntry(group)
                }
            }

            // Some modules expose a preferred direct URL alongside mirrors.
            // Prefer explicit server lists, then use the direct URL as backup.
            parseEntry(root, defaultLabel: "Auto")
        }

        guard !choices.isEmpty else {
            throw ModuleRuntimeError.invalidStream
        }

        return choices
    }

    static func stream(
        from value: Any,
        title: String,
        baseURL: URL
    ) throws -> ModuleResolvedStream {
        guard let first = try streams(
            from: value,
            title: title,
            baseURL: baseURL
        ).first else {
            throw ModuleRuntimeError.invalidStream
        }
        return first
    }
}

// MARK: - Module Trust Store

enum ModuleRuntimeTrustStore {

    private static let storageKey =
        "kinetiq.modules.trustedPackageHashes"

    static func isTrusted(
        _ record: InstalledModuleRecord
    ) -> Bool {
        let trusted = UserDefaults.standard.stringArray(
            forKey: storageKey
        ) ?? []

        return trusted.contains(
            trustIdentifier(for: record)
        )
    }

    static func trust(
        _ record: InstalledModuleRecord
    ) {
        var trusted = UserDefaults.standard.stringArray(
            forKey: storageKey
        ) ?? []

        let identifier = trustIdentifier(for: record)

        if !trusted.contains(identifier) {
            trusted.append(identifier)
        }

        UserDefaults.standard.set(
            trusted,
            forKey: storageKey
        )
    }

    private static func trustIdentifier(
        for record: InstalledModuleRecord
    ) -> String {
        "\(record.sourceID)|\(record.packageSHA256)"
    }
}


// Shared anime collection models and persistence now live in MainTabView.swift.

private enum ModuleCatalogueSection: String, CaseIterable, Identifiable {
    case search = "Search"
    case favorites = "Favorites"
    case recent = "Recent"
    var id: String { rawValue }
}

// MARK: - Module Browser

struct ModuleBrowserView: View {

    let source: ModuleSourceOption

    @StateObject private var packageStore =
        ModulePackageStore.shared

    @State private var runtime: SynthetiqModuleRuntime?

    @State private var searchQuery = ""
    @State private var results: [ModuleAnimeItem] = []

    @State private var selectedItem: ModuleAnimeItem?
    @State private var catalogueSection: ModuleCatalogueSection = .search
    @StateObject private var animeCollection = ModuleAnimeCollectionStore.shared

    @State private var isPreparingRuntime = false
    @State private var isSearching = false

    @State private var showingTrustConfirmation = false
    @State private var errorMessage: String?

    private var installedRecord: InstalledModuleRecord? {
        packageStore.installedModule(for: source)
    }

    private var runtimeIdentity: String {
        guard let record = installedRecord else {
            return "not-installed"
        }

        return "\(record.sourceID)|\(record.packageSHA256)"
    }

    private var isTrusted: Bool {
        guard let record = installedRecord else {
            return false
        }

        return ModuleRuntimeTrustStore.isTrusted(record)
    }

    var body: some View {
        Group {
            if source.module.contentType?.lowercased() != "video" {
                unsupportedContent
            } else if let record = installedRecord,
                      !packageStore.isInstalled(source) {
                notInstalled
            } else if installedRecord == nil {
                notInstalled
            } else if !isTrusted {
                trustRequired
            } else if runtime == nil {
                runtimeLoading
            } else {
                animeCatalogue
            }
        }
        .task(id: runtimeIdentity) {
            await prepareRuntime()
        }
        .sheet(item: $selectedItem) { item in
            if let runtime {
                ModuleAnimeDetailsView(
                    item: item,
                    runtime: runtime,
                    sourceID: source.id,
                    sourceName: source.title
                )
            }
        }
        .alert(
            "Module",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        }
        .alert(
            "Trust \(source.title)?",
            isPresented: $showingTrustConfirmation
        ) {
            Button("Trust and Load", role: .destructive) {
                trustAndLoad()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This installs third-party JavaScript into Kinetiq's module runtime. The module can make network requests to its source and other servers it uses. Only trust a module from a repository you trust. Kinetiq does not yet independently verify the publisher signature."
            )
        }
    }

    // MARK: Not Installed

    private var notInstalled: some View {
        ContentUnavailableView {
            Label(
                source.title,
                systemImage: source.symbol
            )
        } description: {
            Text(
                "Install this module before browsing its anime catalogue."
            )
        } actions: {
            NavigationLink {
                ModuleSourcesView()
            } label: {
                Label(
                    "Manage Modules",
                    systemImage: "square.stack.3d.up.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(KinetiqPalette.accent)
        }
    }

    // MARK: Unsupported Content

    private var unsupportedContent: some View {
        ContentUnavailableView(
            "Not Available Yet",
            systemImage: source.symbol,
            description: Text(
                "Kinetiq's first runtime milestone supports video modules. Other content types will follow."
            )
        )
    }

    // MARK: Trust

    private var trustRequired: some View {
        ContentUnavailableView {
            Label(
                "Module Trust Required",
                systemImage: "hand.raised.fill"
            )
        } description: {
            Text(
                "Review the trust warning before allowing this module's JavaScript to run."
            )
        } actions: {
            Button {
                showingTrustConfirmation = true
            } label: {
                Label(
                    "Review and Trust",
                    systemImage: "checkmark.shield"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(KinetiqPalette.accent)
        }
    }

    // MARK: Runtime Loading

    private var runtimeLoading: some View {
        ContentUnavailableView {
            ProgressView()
        } description: {
            Text("Loading \(source.title)…")
        }
    }

    private func prepareRuntime() async {
        runtime = nil
        results = []

        guard let record = installedRecord,
              packageStore.isInstalled(source) else {
            return
        }

        guard ModuleRuntimeTrustStore.isTrusted(record) else {
            return
        }

        isPreparingRuntime = true
        defer {
            isPreparingRuntime = false
        }

        do {
            let loadedRuntime = try SynthetiqModuleRuntime(
                record: record
            )

            runtime = loadedRuntime
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trustAndLoad() {
        guard let record = installedRecord else {
            return
        }

        ModuleRuntimeTrustStore.trust(record)

        Task {
            await prepareRuntime()
        }
    }

    // MARK: Anime Catalogue

    private var animeCatalogue: some View {
        VStack(spacing: 0) {
            Picker("Anime collection", selection: $catalogueSection) {
                ForEach(ModuleCatalogueSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .accessibilityLabel("Anime catalogue section")

            switch catalogueSection {
            case .search:
                searchBar
                if isSearching {
                    ProgressView("Searching \(source.title)…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 35)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search Anime",
                        systemImage: "magnifyingglass",
                        description: Text(
                            "Enter an anime title to search this source."
                        )
                    )
                } else {
                    collectionScroll(results, showRecent: false)
                }

            case .favorites:
                if animeCollection.favorites(for: source.id).isEmpty {
                    ContentUnavailableView(
                        "No Saved Anime",
                        systemImage: "heart",
                        description: Text("Tap a heart on an anime to save it from this source.")
                    )
                } else {
                    collectionScroll(
                        animeCollection.favorites(for: source.id).map(\.anime),
                        showRecent: false
                    )
                }

            case .recent:
                if animeCollection.recentEpisodes(for: source.id).isEmpty {
                    ContentUnavailableView(
                        "No Recent Episodes",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Episodes you open from this source appear here.")
                    )
                } else {
                    collectionScroll(
                        animeCollection.recentEpisodes(for: source.id).map(\.anime),
                        showRecent: true
                    )
                }
            }
        }
    }

    private func collectionScroll(
        _ items: [ModuleAnimeItem],
        showRecent: Bool
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button {
                            selectedItem = item
                        } label: {
                            animeRow(item)
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 12) {
                            Button {
                                animeCollection.toggleFavorite(
                                    sourceID: source.id,
                                    sourceName: source.title,
                                    anime: item
                                )
                            } label: {
                                Image(systemName: animeCollection.isFavorite(
                                    sourceID: source.id,
                                    animeID: item.id
                                ) ? "heart.fill" : "heart")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(KinetiqPalette.accent)
                                .frame(width: 38, height: 44)
                            }
                            .accessibilityLabel(
                                animeCollection.isFavorite(
                                    sourceID: source.id,
                                    animeID: item.id
                                ) ? "Remove favorite" : "Save to favorites"
                            )

                            if showRecent {
                                Button(role: .destructive) {
                                    animeCollection.removeRecent(
                                        sourceID: source.id,
                                        animeID: item.id
                                    )
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 17))
                                        .frame(width: 38, height: 40)
                                }
                                .accessibilityLabel("Remove recent episode")
                            }
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if showRecent,
                           let entry = animeCollection.recentEpisodes(for: source.id)
                            .first(where: { $0.animeID == item.id }),
                           let number = entry.latestEpisodeNumber {
                            Text("Last opened: Episode \(number) • \((entry.latestLanguage ?? "sub").uppercased())")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 19)
                                .padding(.bottom, 2)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "Search anime…",
                text: $searchQuery
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                Task {
                    await searchAnime()
                }
            }

            Button {
                Task {
                    await searchAnime()
                }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 23))
                    .foregroundStyle(KinetiqPalette.accent)
            }
            .disabled(
                searchQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || isSearching
            )
            .accessibilityLabel("Search anime")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func animeRow(
        _ item: ModuleAnimeItem
    ) -> some View {
        HStack(spacing: 13) {
            AsyncImage(url: item.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    KinetiqPalette.accent.opacity(0.12)

                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(KinetiqPalette.accent)
                }
            }
            .frame(width: 76, height: 105)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(source.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KinetiqPalette.accent)

                Spacer()

                HStack {
                    Text("View details")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    // MARK: Search Action

    @MainActor
    private func searchAnime() async {
        let query = searchQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !query.isEmpty,
              let runtime else {
            return
        }

        isSearching = true
        errorMessage = nil

        defer {
            isSearching = false
        }

        do {
            let response = try await runtime.call(
                handler: "searchResults",
                arguments: [query]
            )

            results = ModuleRuntimeDecoder.searchResults(
                from: response,
                baseURL: runtime.baseURL,
                maximumResults: runtime.maximumHomeResults
            )

            if results.isEmpty {
                errorMessage =
                    "The source returned no anime for \"\(query)\"."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Anime Details and Episodes

struct ModuleAnimeDetailsView: View {

    let item: ModuleAnimeItem
    let runtime: SynthetiqModuleRuntime
    let sourceID: String
    let sourceName: String

    @StateObject private var animeCollection = ModuleAnimeCollectionStore.shared

    @Environment(\.dismiss) private var dismiss

    @State private var details: ModuleAnimeItem?
    @State private var episodes: [ModuleAnimeEpisode] = []

    @State private var playbackSession: ModuleEpisodePlaybackSession?
    @State private var selectedPlaybackSession: ModuleEpisodePlaybackSession?

    @State private var isLoading = true
    @State private var isResolvingStream = false

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsHeader

                    episodeSection
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(details?.title ?? item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        animeCollection.toggleFavorite(
                            sourceID: sourceID,
                            sourceName: sourceName,
                            anime: item
                        )
                    } label: {
                        Image(systemName: animeCollection.isFavorite(
                            sourceID: sourceID,
                            animeID: item.id
                        ) ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel("Toggle anime favorite")

                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDetailsAndEpisodes()
            }
            .fullScreenCover(item: $selectedPlaybackSession) { session in
                KinetiqModulePlayerView(session: session)
                    .preferredColorScheme(.dark)
                    .presentationBackground(.black)
                    .ignoresSafeArea()
            }
            .alert(
                "Playback",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "The request failed.")
            }
        }
    }

    // MARK: Details Header

    private var savedPlayback: ModuleAnimeCollectionEntry? {
        animeCollection.entries.first {
            $0.sourceID == sourceID && $0.animeID == item.id
        }
    }

    private var resumeEpisode: ModuleAnimeEpisode? {
        guard let savedPlayback,
              (savedPlayback.lastPlaybackPosition ?? 0) >= 3,
              let episodeID = savedPlayback.latestEpisodeID else {
            return nil
        }

        return episodes.first { $0.id == episodeID }
    }

    private var detailsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = details?.imageURL ?? item.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            }

            Text(details?.title ?? item.title)
                .font(.system(size: 23, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            if let episode = resumeEpisode {
                Button {
                    let requested = savedPlayback?.latestLanguage ?? "sub"
                    let language = requested == "dub" && episode.dubAvailable
                        ? "dub"
                        : (episode.subAvailable ? "sub" : "dub")
                    Task { await play(episode: episode, language: language) }
                } label: {
                    Label(
                        "Continue Episode \(episode.number)",
                        systemImage: "play.circle.fill"
                    )
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(KinetiqPalette.accent)
                .disabled(isResolvingStream)
            }

            if isLoading {
                ProgressView("Loading episodes…")
                    .padding(.top, 5)
            }
        }
    }

    // MARK: Episode List

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Episodes")
                    .font(.system(size: 19, weight: .bold))

                Spacer()

                Text("\(episodes.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !isLoading && episodes.isEmpty {
                ContentUnavailableView(
                    "No Episodes",
                    systemImage: "rectangle.stack",
                    description: Text(
                        "This source did not return any episodes for this title."
                    )
                )
                .frame(minHeight: 150)
            } else {
                ForEach(episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func episodeRow(
        _ episode: ModuleAnimeEpisode
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Episode \(episode.number)")
                    .font(.system(size: 14, weight: .semibold))

                Text(
                    [
                        episode.subAvailable ? "Sub" : nil,
                        episode.dubAvailable ? "Dub" : nil
                    ]
                    .compactMap { $0 }
                    .joined(separator: " • ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if episode.subAvailable {
                Button("Sub") {
                    Task {
                        await play(
                            episode: episode,
                            language: "sub"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .tint(KinetiqPalette.accent)
                .disabled(isResolvingStream)
            }

            if episode.dubAvailable {
                Button("Dub") {
                    Task {
                        await play(
                            episode: episode,
                            language: "dub"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .tint(KinetiqPalette.accent)
                .disabled(isResolvingStream)
            }
        }
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    // MARK: Load Details and Episodes

    @MainActor
    private func loadDetailsAndEpisodes() async {
        isLoading = true
        episodes = []
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let detailsResponse = try await runtime.call(
                handler: "extractDetails",
                arguments: [item.href]
            )

            let resolvedDetails = ModuleRuntimeDecoder.details(
                from: detailsResponse,
                fallback: item,
                baseURL: runtime.baseURL
            )

            details = resolvedDetails

            // Prefer the documented series identifier first; only retry
            // with alternative references if that returns no episodes.
            let references = [
                resolvedDetails.id,
                resolvedDetails.href,
                item.id,
                item.href
            ]

            var attempted = Set<String>()
            var lastError: Error?

            for rawReference in references {
                let reference = rawReference.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !reference.isEmpty,
                      attempted.insert(reference).inserted else {
                    continue
                }

                do {
                    let response = try await runtime.call(
                        handler: "extractEpisodes",
                        arguments: [reference]
                    )

                    let foundEpisodes = ModuleRuntimeDecoder.episodes(
                        from: response
                    )

                    if !foundEpisodes.isEmpty {
                        episodes = foundEpisodes
                        return
                    }
                } catch {
                    // A timeout is not an identifier-format issue.
                    // Avoid multiplying a slow request four times.
                    if let moduleError = error as? ModuleRuntimeError,
                       case .handlerTimedOut = moduleError {
                        throw moduleError
                    }

                    lastError = error
                }
            }

            if let lastError {
                throw lastError
            }

            errorMessage =
                "The source did not return a recognizable episode list."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Resolve Stream

    @MainActor
    private func play(
        episode: ModuleAnimeEpisode,
        language: String
    ) async {
        guard !isResolvingStream else {
            return
        }

        isResolvingStream = true
        defer {
            isResolvingStream = false
        }

        let session: ModuleEpisodePlaybackSession

        if let playbackSession {
            session = playbackSession
        } else {
            session = ModuleEpisodePlaybackSession(
                animeTitle: details?.title ?? item.title,
                episodes: episodes,
                runtime: runtime,
                sourceID: sourceID,
                animeItem: item
            )
            playbackSession = session
        }

        let didResolve = await session.play(
            episode: episode,
            language: language
        )

        if didResolve {
            // Store the episode selection only after stream resolution;
            // playback position is deliberately not claimed as implemented.
            animeCollection.recordEpisode(
                sourceID: sourceID,
                sourceName: sourceName,
                anime: item,
                episode: episode,
                language: language
            )
            selectedPlaybackSession = session
        } else {
            errorMessage = session.playbackError
                ?? "The episode stream could not be resolved."
        }
    }
}