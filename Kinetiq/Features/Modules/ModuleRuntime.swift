import AVKit
import Foundation
import JavaScriptCore
import SwiftUI

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
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        session = URLSession(configuration: configuration)
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
        request.httpShouldHandleCookies = false

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
                continuation.resume(
                    throwing: ModuleRuntimeError.handlerFailed(
                        errorMessage
                    )
                )
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

struct ModuleResolvedStream: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let headers: [String: String]
    let streamType: String
}

// MARK: - Module Episode Playback Session

/// Owns one module-backed series queue. It never writes to the local media
/// queue or local playback history.
@MainActor
final class ModuleEpisodePlaybackSession: ObservableObject, Identifiable {

    let id = UUID()
    let animeTitle: String
    let sourceName: String

    @Published private(set) var episodes: [ModuleAnimeEpisode]
    @Published private(set) var currentEpisode: ModuleAnimeEpisode?
    @Published private(set) var currentEpisodeIndex: Int?
    @Published private(set) var currentStream: ModuleResolvedStream?
    @Published private(set) var currentEpisodeTitle: String
    @Published private(set) var selectedLanguage = "sub"
    @Published private(set) var isResolving = false
    @Published private(set) var playbackError: String?

    private let runtime: SynthetiqModuleRuntime
    private var activeRequestID: UUID?

    init(
        animeTitle: String,
        episodes: [ModuleAnimeEpisode],
        runtime: SynthetiqModuleRuntime
    ) {
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
            let response = try await runtime.call(
                handler: "extractStreamUrl",
                arguments: [
                    episode.href,
                    language.lowercased()
                ]
            )

            let stream = try ModuleRuntimeDecoder.stream(
                from: response,
                title: episodeTitle,
                baseURL: runtime.baseURL
            )

            guard activeRequestID == requestID else {
                return false
            }

            currentEpisode = episode
            currentEpisodeIndex = index
            currentEpisodeTitle = episodeTitle
            selectedLanguage = language.lowercased()
            currentStream = stream
            playbackError = nil

            return true
        } catch {
            guard activeRequestID == requestID else {
                return false
            }

            playbackError = error.localizedDescription
            return false
        }
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