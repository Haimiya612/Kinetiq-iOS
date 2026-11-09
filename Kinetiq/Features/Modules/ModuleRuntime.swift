import AVKit
import CryptoKit
import Foundation
import JavaScriptCore
import SwiftUI
import UIKit

// MARK: - Shared Async UI (Batch 04A)

struct KinetiqAsyncStateView: View {
    enum Kind: Equatable {
        case loading
        case empty
        case failure
    }

    let kind: Kind
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        kind: Kind,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    private var stateSymbol: String {
        switch kind {
        case .loading: "arrow.triangle.2.circlepath"
        case .empty: "square.stack.3d.up"
        case .failure: "exclamationmark.triangle"
        }
    }

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(KinetiqPalette.accent.opacity(0.09))
                    .frame(width: 74, height: 74)

                Circle()
                    .strokeBorder(KinetiqPalette.accent.opacity(0.13), lineWidth: 1)
                    .frame(width: 74, height: 74)

                if kind == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(KinetiqPalette.accent)
                } else {
                    Image(systemName: stateSymbol)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(KinetiqPalette.accent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                }
            }

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if kind == .failure, let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(KinetiqPalette.accent)
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(KinetiqPalette.accent.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

}

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
    case sourceNoMedia
    case sourceReportedFailure

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
            return "The source returned no recognizable playable media URL."

        case .sourceNoMedia:
            return "This source has no playable stream for the selected episode or language. Try a different episode or the source's other available language."

        case .sourceReportedFailure:
            return "The source reported a problem while resolving this episode. Copy diagnostics for the source status and network response classes."
        }
    }
}

// MARK: - Batch 05E: Private Module Failure Diagnostics

/// Produces shareable evidence without including signed stream URLs, cookies,
/// request headers, episode identifiers, or raw module response bodies.
/// Reports are kept in memory only; nothing is uploaded automatically.
enum ModulePlaybackDiagnostics {
    static func redact(_ original: String, limit: Int = 240) -> String {
        var result = original
        let patterns = [
            #"(?i)https?://[^\s\"'<>]+"#,
            #"(?i)(?:authorization|set-cookie|cookie|x-api-key|api[_-]?key|token|signature|bearer)\s*[:=]\s*[^\s,;]+"#,
            #"[A-Za-z0-9_\-]{85,}"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern, with: "[redacted]", options: .regularExpression
            )
        }
        result = result.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String(result.prefix(limit))
    }

    static func code(for error: Error) -> String {
        if let module = error as? ModuleRuntimeError {
            switch module {
            case .invalidStream: return "E01_NO_ACCEPTED_STREAM"
            case .sourceNoMedia: return "SOURCE_NO_MEDIA_FOR_EPISODE"
            case .sourceReportedFailure: return "SOURCE_REPORTED_RESOLVE_FAILURE"
            case .handlerTimedOut: return "RUNTIME_HANDLER_TIMEOUT"
            case .missingHandler: return "RUNTIME_MISSING_HANDLER"
            case .handlerFailed: return "RUNTIME_HANDLER_FAILED"
            case .invalidResult: return "RUNTIME_INVALID_RESULT"
            case .invalidHTTPResponse: return "NETWORK_INVALID_RESPONSE"
            case .invalidRequestURL, .insecureRequest: return "NETWORK_INVALID_URL"
            case .invalidHeaders, .invalidHTTPMethod: return "NETWORK_UNSUPPORTED_REQUEST"
            case .responseTooLarge: return "NETWORK_RESPONSE_LIMIT"
            case .scriptLoadFailed: return "RUNTIME_SCRIPT_FAILURE"
            case .contextUnavailable: return "RUNTIME_UNAVAILABLE"
            case .invalidManifest, .invalidBaseURL, .unsupportedContentType:
                return "MODULE_CONFIGURATION"
            case .invalidArguments: return "RUNTIME_INVALID_ARGUMENTS"
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .cannotFindHost: return "NETWORK_DNS_FAILED"
            case .cannotConnectToHost: return "NETWORK_CONNECT_FAILED"
            case .timedOut: return "NETWORK_TIMEOUT"
            case .notConnectedToInternet: return "NETWORK_OFFLINE"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "NETWORK_TLS_FAILED"
            default: return "NETWORK_URL_ERROR_\(url.errorCode)"
            }
        }
        return "UNCLASSIFIED_\(String(describing: type(of: error)))"
    }

    /// Only counts structural fields and URL types. Never includes values.
    static func responseShape(_ value: Any) -> String {
        if let raw = value as? String {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (text.hasPrefix("{") || text.hasPrefix("[")),
               text.utf8.count <= 524_288,
               let data = text.data(using: .utf8),
               let container = try? JSONSerialization.jsonObject(with: data),
               container is [String: Any] || container is [Any] {
                return "encoded JSON -> " + responseShape(container)
            }
        }
        let urlKeys: Set<String> = [
            "url", "streamurl", "file", "src", "link", "href",
            "embedurl", "iframeurl", "playerurl", "weburl", "embed", "iframe"
        ]
        let containers: Set<String> = [
            "streams", "sources", "servers", "links", "mirrors", "qualities",
            "variants", "videos", "files", "data", "result", "stream", "source", "video"
        ]
        let exclusions: Set<String> = [
            "image", "poster", "cover", "thumbnail", "artwork", "banner",
            "subtitles", "captions", "tracks", "headers", "requestheaders",
            "description", "metadata", "title", "name", "label", "provider",
            "quality", "height", "language", "lang", "type", "streamtype",
            "id", "episode", "serverkey", "preferred", "duration"
        ]
        var groups = 0, fields = 0, https = 0, http = 0, relative = 0, opaque = 0
        var objects = 0, arrays = 0, visited = 0
        var emptyArrays = 0, errorFields = 0, reportedFailure = 0
        func candidate(_ string: String) {
            fields += 1
            let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.lowercased().hasPrefix("https://") { https += 1 }
            else if value.lowercased().hasPrefix("http://") { http += 1 }
            else if value.hasPrefix("/") { relative += 1 }
            else { opaque += 1 }
        }
        func walk(_ entry: Any, depth: Int, isCandidate: Bool) {
            guard depth <= 6, visited < 384 else { return }
            visited += 1
            if let text = entry as? String {
                if isCandidate { candidate(text) }
                return
            }
            if let array = entry as? [Any] {
                arrays += 1
                if array.isEmpty { emptyArrays += 1 }
                if isCandidate, array.count == 2,
                   let second = array[1] as? String {
                    candidate(second)
                    return
                }
                for item in array.prefix(48) {
                    walk(item, depth: depth + 1, isCandidate: isCandidate)
                }
                return
            }
            if let object = entry as? [String: Any] {
                objects += 1
                for (name, child) in object.prefix(48) {
                    let key = name.lowercased()
                    // Presence only: never copy provider error messages or tokens.
                    if ["error", "errors", "reason", "message"].contains(key) { errorFields += 1 }
                    if key == "success", let success = child as? Bool, !success { reportedFailure += 1 }
                    guard !exclusions.contains(key) else { continue }
                    if containers.contains(key) { groups += 1 }
                    let looksLikeNamedServer = isCandidate &&
                        (child is [String: Any] || child is [Any] || child is String)
                    guard containers.contains(key) || urlKeys.contains(key) ||
                          looksLikeNamedServer else { continue }
                    walk(child, depth: depth + 1,
                         isCandidate: urlKeys.contains(key) || looksLikeNamedServer ||
                             containers.contains(key) || isCandidate)
                }
            }
        }
        walk(value, depth: 0, isCandidate: value is String || value is [Any])
        let kind: String = value is [String: Any] ? "object"
            : value is [Any] ? "array" : value is String ? "string" : "other"
        return "type=\(kind), groups=\(groups), objects=\(objects), arrays=\(arrays), empty arrays=\(emptyArrays), error fields=\(errorFields), success=false=\(reportedFailure), url fields=\(fields), HTTPS=\(https), HTTP=\(http), relative=\(relative), opaque=\(opaque)"
    }

    /// Failure classification is intentionally vocabulary-only: provider error
    /// values may contain signed URLs, tokens, or private request details.
    /// Return fixed labels instead of copying provider-controlled text.
    static func providerErrorCategory(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("429") || lower.contains("rate limit") ||
            lower.contains("too many requests") { return "SOURCE_RATE_LIMITED" }
        if lower.contains("403") || lower.contains("forbidden") ||
            lower.contains("access denied") { return "SOURCE_ACCESS_DENIED" }
        if lower.contains("cloudflare") || lower.contains("captcha") ||
            lower.contains("challenge") { return "SOURCE_CHALLENGE" }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "SOURCE_TIMEOUT"
        }
        if lower.contains("404") || lower.contains("not found") {
            return "SOURCE_NOT_FOUND"
        }
        return "SOURCE_HANDLER_ERROR_OTHER"
    }

    static func sourceResponseStatus(_ response: Any) -> String {
        guard let object = response as? [String: Any] else {
            return "response is not an object"
        }
        let streams = object["streams"] as? [Any]
        let sources = object["sources"] as? [Any]
        let empty = (streams?.isEmpty == true || sources?.isEmpty == true)
        let flat = ["error", "reason", "message", "status"]
            .compactMap { object[$0] as? String }
        let nested = ["error", "errors", "reason"]
            .compactMap { object[$0] as? [String: Any] }
            .flatMap { dictionary in
                ["message", "reason", "code", "status"]
                    .compactMap { dictionary[$0] as? String }
            }
        let value = (flat + nested).joined(separator: " ").lowercased()
        let category: String
        if value.contains("timeout") || value.contains("timed out") || value.contains("deadline") {
            category = "SOURCE_TIMEOUT"
        } else if value.contains("cloudflare") || value.contains("captcha") || value.contains("challenge") {
            category = "SOURCE_CHALLENGE"
        } else if value.contains("403") || value.contains("forbidden") || value.contains("unauthoriz") {
            category = "SOURCE_ACCESS_DENIED"
        } else if value.contains("rate limit") || value.contains("429") {
            category = "SOURCE_RATE_LIMITED"
        } else if value.contains("unavailable") || value.contains("no playable") || value.contains("no verified") || value.contains("no stream") {
            category = "SOURCE_NO_MEDIA"
        } else if value.contains("not found") || value.contains("404") {
            category = "SOURCE_NOT_FOUND"
        } else if value.isEmpty {
            category = object["error"] != nil || object["errors"] != nil
                ? "SOURCE_REPORTED_ERROR_WITHOUT_TEXT"
                : "NO_SOURCE_ERROR_TEXT"
        } else {
            category = "SOURCE_ERROR_OTHER"
        }
        return "module returned \(empty ? "empty source list" : "source response"); provider class=\(category)"
    }

    static func simpleReport(source: String, phase: String, error: Error) -> String {
        [
            "Kinetiq module diagnostics · Batch 05F",
            "Source: \(redact(source, limit: 80))",
            "Phase: \(phase)",
            "Code: \(code(for: error))",
            "Reason: \(redact(error.localizedDescription))",
            "No stream URLs, request headers, cookies or tokens included."
        ].joined(separator: "\n")
    }
}

// MARK: - Runtime Manifest

private struct RuntimeManifest: Decodable {
    let contentType: String?
    let moduleVersion: String?
    let version: String?
    let moduleIdentity: String?
    let config: RuntimeManifestConfiguration
}

private struct RuntimeManifestConfiguration: Decodable {
    let baseUrl: String
    let runtime: RuntimeManifestRuntime
    let caps: RuntimeManifestCaps
    // Contract v4 (Synthetiq One): defaults for requests to source-provided
    // media endpoints. Individual stream headers take precedence.
    let streamHeaders: [String: String]?
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

// MARK: - Module Fetch Compatibility

/// Synthetiq modules can request raw 3xx responses so their own resolver
/// follows provider redirects and tracks the final media host. Normal requests
/// still use URLSession's standard HTTPS redirect behavior.
private final class ModuleManualRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct ModuleFetchOptions: Decodable {
    let followRedirects: Bool?
    let maxBytesHint: Int?
    let timeoutMs: Int?
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
    private let manualRedirectSession: URLSession

    // Batch 05F: bounded, non-identifying evidence for Error 01. No URLs,
    // hostnames, cookies, headers, request bodies, or module response bodies.
    private var totalRequests = 0
    private var okResponses = 0
    private var unauthorizedResponses = 0
    private var notFoundResponses = 0
    private var rateLimitedResponses = 0
    private var serverErrorResponses = 0
    private var otherResponses = 0
    private var transportFailures = 0
    private var binaryResponses = 0
    private var manualRedirectRequests = 0
    private var redirectResponses = 0
    private var lastNetworkFailure = "none"

    func diagnosticSummary() -> String {
        "requests=\(totalRequests), 2xx=\(okResponses), 3xx=\(redirectResponses), manual redirect requests=\(manualRedirectRequests), 401/403=\(unauthorizedResponses), 404=\(notFoundResponses), 429=\(rateLimitedResponses), 5xx=\(serverErrorResponses), other HTTP=\(otherResponses), transport failures=\(transportFailures), binary bodies=\(binaryResponses), last transport class=\(lastNetworkFailure)"
    }

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
        // Both sessions use the same ephemeral cookie jar. Using a separate
        // delegate avoids changing redirect policy for unrelated modules.
        manualRedirectSession = URLSession(
            configuration: configuration,
            delegate: ModuleManualRedirectDelegate(),
            delegateQueue: nil
        )
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
        body: String,
        optionsJSON: String
    ) async throws -> [String: Any] {
        await gate.acquire()
        totalRequests += 1

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

        // Fetchv2's fifth argument was previously discarded. AniWorld's
        // hoster/media checks explicitly require followRedirects=false.
        let bridgeOptions = optionsJSON.data(using: .utf8).flatMap {
            try? JSONDecoder().decode(ModuleFetchOptions.self, from: $0)
        }
        let followRedirects = bridgeOptions?.followRedirects ?? true
        if !followRedirects { manualRedirectRequests += 1 }
        // An optional hint may tighten but never increase the verified
        // module response cap. Do not use it to fabricate or truncate data.
        let requestedLimit = bridgeOptions?.maxBytesHint ?? maximumResponseBytes
        let responseLimit = min(max(requestedLimit, 1_024), maximumResponseBytes)

        var request = URLRequest(url: resolvedURL)

        request.httpMethod = normalizedMethod
        // A module can ask for a *shorter* provider timeout (e.g. hoster
        // failover), but never increase the manifest's native request limit.
        let perRequestTimeout = min(
            timeoutMilliseconds,
            max(500, bridgeOptions?.timeoutMs ?? timeoutMilliseconds)
        )
        request.timeoutInterval = Double(perRequestTimeout) / 1_000

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
            (responseData, response) = try await (
                followRedirects ? session : manualRedirectSession
            ).data(for: request)
        } catch {
            transportFailures += 1
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut: lastNetworkFailure = "timeout"
                case .cannotFindHost: lastNetworkFailure = "DNS"
                case .cannotConnectToHost: lastNetworkFailure = "connection"
                case .secureConnectionFailed, .serverCertificateUntrusted:
                    lastNetworkFailure = "TLS"
                case .notConnectedToInternet: lastNetworkFailure = "offline"
                default: lastNetworkFailure = "other URL session failure"
                }
            } else {
                lastNetworkFailure = "URL session failure"
            }
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

        guard responseData.count <= responseLimit else {
            throw ModuleRuntimeError.responseTooLarge
        }

        switch httpResponse.statusCode {
        case 200...299: okResponses += 1
        case 300...399:
            redirectResponses += 1
            otherResponses += 1
        case 401, 403: unauthorizedResponses += 1
        case 404: notFoundResponses += 1
        case 429: rateLimitedResponses += 1
        case 500...599: serverErrorResponses += 1
        default: otherResponses += 1
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

        // Provider modules inspect .body.charCodeAt(n) to verify actual
        // MPEG-TS/MP4 segment signatures. A non-UTF-8 body must NEVER turn
        // into "" merely because it is binary. Latin-1 maps each byte 1:1
        // into JS character codes 0...255 without rewriting the bytes.
        let mediaType = (responseHeaders["content-type"] ?? "").lowercased()
        let explicitlyBinary = mediaType.hasPrefix("video/") ||
            mediaType.hasPrefix("audio/") || mediaType.hasPrefix("image/") ||
            mediaType.contains("octet-stream") ||
            mediaType.contains("mpeg2-transport") ||
            mediaType.contains("application/mp2t")
        let isBinary = explicitlyBinary || String(data: responseData, encoding: .utf8) == nil
        if isBinary { binaryResponses += 1 }
        let responseBody = isBinary
            ? (String(data: responseData, encoding: .isoLatin1) ?? "")
            : (String(data: responseData, encoding: .utf8) ?? "")

        return [
            "status": httpResponse.statusCode,
            "ok": (200...299).contains(httpResponse.statusCode),
            "url": httpResponse.url?.absoluteString ?? "",
            "headers": responseHeaders,
            "body": responseBody,
            "binary": isBinary
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
    let moduleVersion: String
    let packageSHA256Prefix: String
    let defaultStreamHeaders: [String: String]

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

    // Browser-like timers for modules that use Promise.race, cooldowns,
    // delayed provider probes, and retry backoff. Accessed ONLY on jsQueue.
    // Timers are bounded, never evaluated as JavaScript strings, and do not
    // persist across runtime instances.
    private var scheduledTimers: [String: DispatchWorkItem] = [:]
    private let maximumPendingTimers = 64

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
        moduleVersion = String((manifest.moduleVersion ?? manifest.version ?? "unknown").prefix(48))
        packageSHA256Prefix = String(record.packageSHA256.prefix(12))
        // Only inherit non-secret presentation / media request metadata.
        // Credential headers MUST come from the actual extracted stream to
        // avoid forwarding unrelated provider secrets to an arbitrary CDN.
        let safeDefaultNames: Set<String> = [
            "user-agent", "accept", "accept-language", "referer", "origin"
        ]
        defaultStreamHeaders = Dictionary(
            uniqueKeysWithValues: (manifest.config.streamHeaders ?? [:])
                .filter { name, value in
                    let lowercaseName = name.lowercased()
                    return safeDefaultNames.contains(lowercaseName)
                        && name.count <= 80 && value.count <= 2_048
                        && !name.contains("\r") && !name.contains("\n")
                        && !value.contains("\r") && !value.contains("\n")
                }
                .map { ($0.key, $0.value) }
        )

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
                (String, String, String, String, String, String) -> Void = {
                    [weak self] url, headers, method, body, optionsJSON, requestID in

                    guard let self else {
                        return
                    }

                    Task {
                        do {
                            let payload = try await self.networkClient.fetch(
                                rawURL: url,
                                headersJSON: headers,
                                method: method,
                                body: body,
                                optionsJSON: optionsJSON
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

            // A timer callback must execute on the SAME serial queue as
            // JSContext. Calling JSContext from a background URLSession or
            // timer thread would cause intermittent crashes/corruption.
            let timerScheduleBridge:
                @convention(block)
                (String, Double) -> Bool = { [weak self] token, delay in
                    self?.scheduleModuleTimer(token: token, delay: delay) ?? false
                }

            let timerCancelBridge:
                @convention(block)
                (String) -> Void = { [weak self] token in
                    self?.cancelModuleTimer(token: token)
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

            javascriptContext.setObject(
                timerScheduleBridge,
                forKeyedSubscript: "__kinetiqScheduleTimer" as NSString
            )
            javascriptContext.setObject(
                timerCancelBridge,
                forKeyedSubscript: "__kinetiqCancelTimer" as NSString
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

    func networkDiagnosticSummary() async -> String {
        await networkClient.diagnosticSummary()
    }

    // MARK: Browser-compatible timer bridge

    // These methods are invoked by JavaScriptCore on the serial jsQueue.
    // Do not call them from the main thread or the networking actor.
    private func scheduleModuleTimer(token: String, delay: Double) -> Bool {
        guard !token.isEmpty, token.count <= 64,
              scheduledTimers.count < maximumPendingTimers || scheduledTimers[token] != nil else {
            return false
        }

        scheduledTimers[token]?.cancel()
        scheduledTimers.removeValue(forKey: token)

        let clampedDelay = delay.isFinite
            ? min(max(delay, 1), 60_000)
            : 1

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledTimers.removeValue(forKey: token)
            self.context?.objectForKeyedSubscript("__kinetiqFireTimer")?
                .call(withArguments: [token])
        }

        scheduledTimers[token] = work
        jsQueue.asyncAfter(
            deadline: .now() + clampedDelay / 1_000,
            execute: work
        )
        return true
    }

    private func cancelModuleTimer(token: String) {
        scheduledTimers.removeValue(forKey: token)?.cancel()
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

        // Synthetiq modules may use browser timer APIs for cooldowns and
        // provider races. JavaScriptCore has no event loop/timers by default.
        // Never evaluate string callbacks; bound concurrency and deadlines.
        const timers = Object.create(null);
        let nextTimerID = 0;

        function scheduleTimer(callback, delay, repeating, args) {
            if (typeof callback !== 'function') {
                throw new TypeError('Timer callback must be a function');
            }
            const id = String(++nextTimerID);
            let ms = Number(delay);
            if (!Number.isFinite(ms)) ms = 1;
            ms = Math.max(repeating ? 100 : 1, Math.min(ms, 60000));
            const task = { callback: callback, args: args, repeat: repeating, delay: ms };
            timers[id] = task;
            if (!__kinetiqScheduleTimer(id, ms)) {
                delete timers[id];
                throw new Error('Too many pending module timers');
            }
            return Number(id);
        }

        globalThis.setTimeout = function(callback, delay, ...args) {
            return scheduleTimer(callback, delay, false, args);
        };
        globalThis.setInterval = function(callback, delay, ...args) {
            return scheduleTimer(callback, delay, true, args);
        };
        globalThis.clearTimeout = function(id) {
            const key = String(id);
            delete timers[key];
            __kinetiqCancelTimer(key);
        };
        globalThis.clearInterval = globalThis.clearTimeout;
        globalThis.__kinetiqFireTimer = function(id) {
            const key = String(id);
            const task = timers[key];
            if (!task) return;
            if (!task.repeat) delete timers[key];
            try {
                task.callback.apply(undefined, task.args);
            } catch (error) {
                // A provider timer error must not corrupt the runtime queue.
                if (globalThis.console && typeof console.error === 'function') {
                    console.error('Module timer callback failed');
                }
            } finally {
                if (task.repeat && timers[key] === task &&
                    !__kinetiqScheduleTimer(key, task.delay)) {
                    delete timers[key];
                }
            }
        };

        globalThis.fetchv2 = function(
            url,
            headers,
            method,
            body,
            options
        ) {
            return new Promise((resolve, reject) => {
                const requestID = String(++nextRequestID);

                pending[requestID] = {
                    resolve: resolve,
                    reject: reject
                };

                let serializedHeaders = "{}";
                let serializedOptions = "{}";

                try {
                    serializedHeaders = JSON.stringify(headers || {});
                    // Only known transport controls; ignore arbitrary module
                    // options instead of evaluating or stringifying raw data.
                    const opts = options && typeof options === 'object' ? options : {};
                    serializedOptions = JSON.stringify({
                        followRedirects: opts.followRedirects !== false,
                        maxBytesHint: typeof opts.maxBytesHint === 'number' &&
                            Number.isFinite(opts.maxBytesHint)
                            ? Math.max(1024, Math.min(8000000, Math.floor(opts.maxBytesHint)))
                            : undefined,
                        timeoutMs: typeof opts.timeoutMs === 'number' &&
                            Number.isFinite(opts.timeoutMs)
                            ? Math.max(500, Math.min(30000, Math.floor(opts.timeoutMs)))
                            : undefined
                    });
                } catch (error) {
                    delete pending[requestID];
                    reject(new Error("Invalid fetchv2 options or headers"));
                    return;
                }

                try {
                    __kinetiqFetch(
                        String(url),
                        serializedHeaders,
                        String(method || "GET"),
                        body == null ? "" : String(body),
                        serializedOptions,
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
                // Some modules index response.headers['content-type'] directly;
                // others call .get('Content-Type'). Support both contracts.
                const responseHeaders = Object.create(null);
                for (const key of Object.keys(rawHeaders)) {
                    const value = String(rawHeaders[key]);
                    responseHeaders[key] = value;
                    responseHeaders[key.toLowerCase()] = value;
                }
                Object.defineProperties(responseHeaders, {
                    get: { value: function(name) {
                        const wanted = String(name).toLowerCase();
                        return Object.prototype.hasOwnProperty.call(this, wanted)
                            ? this[wanted] : null;
                    }},
                    has: { value: function(name) {
                        return this.get(name) !== null;
                    }},
                    forEach: { value: function(callback) {
                        for (const key of Object.keys(rawHeaders)) {
                            callback(String(rawHeaders[key]), key.toLowerCase(), this);
                        }
                    }},
                    entries: { value: function() {
                        return Object.keys(rawHeaders).map(
                            key => [key.toLowerCase(), String(rawHeaders[key])]
                        )[Symbol.iterator]();
                    }}
                });

                const response = {
                    status: Number(raw.status || 0),
                    ok: Boolean(raw.ok),
                    url: String(raw.url || ""),
                    body: String(raw.body || ""),
                    headers: responseHeaders,
                    // Standard Fetch byte API. For binary responses the body is
                    // byte-preserving Latin-1; other responses are encoded as UTF-8.
                    arrayBuffer: async function() {
                        const body = String(raw.body || '');
                        if (raw.binary) {
                            const bytes = new Uint8Array(body.length);
                            for (let i = 0; i < body.length; i++) {
                                bytes[i] = body.charCodeAt(i) & 255;
                            }
                            return bytes.buffer;
                        }
                        const encoded = unescape(encodeURIComponent(body));
                        const bytes = new Uint8Array(encoded.length);
                        for (let i = 0; i < encoded.length; i++) {
                            bytes[i] = encoded.charCodeAt(i);
                        }
                        return bytes.buffer;
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

        // A small standards-compatible fetch() adapter for modules ported
        // from browser environments. Both fetch and fetchv2 share the same
        // HTTPS-only native client, transient cookies and response caps.
        function normalizeFetchHeaders(input) {
            if (!input) return {};
            if (typeof input.forEach === 'function') {
                const result = {};
                input.forEach((value, key) => { result[String(key)] = String(value); });
                return result;
            }
            if (Array.isArray(input)) {
                const result = {};
                input.forEach(pair => {
                    if (pair && pair.length >= 2) result[String(pair[0])] = String(pair[1]);
                });
                return result;
            }
            return input;
        }
        if (typeof globalThis.fetch !== 'function') {
            globalThis.fetch = function(input, init) {
                const options = init || {};
                const target = input && typeof input === 'object' && input.url
                    ? input.url : input;
                const requestHeaders = options.headers ||
                    (input && typeof input === 'object' ? input.headers : undefined);
                return globalThis.fetchv2(
                    String(target),
                    normalizeFetchHeaders(requestHeaders),
                    String(options.method || (input && input.method) || 'GET'),
                    options.body === undefined || options.body === null
                        ? '' : String(options.body),
                    { followRedirects: options.redirect !== 'manual' }
                );
            };
        }

        // Minimal base64 APIs needed by some module extraction scripts.
        // These operate on binary strings, matching window.atob/btoa.
        const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        if (typeof globalThis.atob !== 'function') {
            globalThis.atob = function(input) {
                const normalized = String(input).replace(/[\\t\\n\\f\\r ]/g, '');
                if (normalized.length % 4 === 1 ||
                    /[^A-Za-z0-9+/=]/.test(normalized) ||
                    /=/.test(normalized.replace(/={0,2}$/, ''))) {
                    throw new TypeError('Invalid base64');
                }
                const data = normalized.replace(/=+$/, '');
                let buffer = 0, bits = 0, output = '';
                for (const character of data) {
                    buffer = (buffer << 6) | alphabet.indexOf(character);
                    bits += 6;
                    if (bits >= 8) {
                        bits -= 8;
                        output += String.fromCharCode((buffer >>> bits) & 255);
                    }
                }
                return output;
            };
        }
        if (typeof globalThis.btoa !== 'function') {
            globalThis.btoa = function(input) {
                const data = String(input);
                let output = '';
                for (let i = 0; i < data.length; i += 3) {
                    const a = data.charCodeAt(i);
                    const b = i + 1 < data.length ? data.charCodeAt(i + 1) : 0;
                    const c = i + 2 < data.length ? data.charCodeAt(i + 2) : 0;
                    if (a > 255 || b > 255 || c > 255) {
                        throw new TypeError('Invalid binary string');
                    }
                    output += alphabet[a >>> 2];
                    output += alphabet[((a & 3) << 4) | (b >>> 4)];
                    output += i + 1 < data.length
                        ? alphabet[((b & 15) << 2) | (c >>> 6)] : '=';
                    output += i + 2 < data.length ? alphabet[c & 63] : '=';
                }
                return output;
            };
        }

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
        // Source extractors may probe several CDNs or retry slow providers.
        // Keep normal browsing responsive, but allow a bounded longer budget
        // for the episode-to-stream step (cold starts can exceed 30 seconds).
        // This does not weaken the network client's per-request size/timeout
        // caps, nor let an extractor execute indefinitely.
        let timeout = handler == "extractStreamUrl"
            ? max(timeoutMilliseconds, 60_000)
            : timeoutMilliseconds

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
    let synopsis: String?

    init(
        id: String,
        title: String,
        href: String,
        imageURL: URL?,
        synopsis: String? = nil
    ) {
        self.id = id
        self.title = title
        self.href = href
        self.imageURL = imageURL
        self.synopsis = synopsis
    }
}

// MARK: - Artwork Cache and Poster

/// A source-neutral, bounded HTTPS artwork cache for module posters.
/// No cookies, credentials, stream URLs or module-provided request headers
/// are used for artwork requests. Cache file names contain only SHA-256
/// hashes of the URLs and the data is kept in the app's Caches directory.
actor ModuleAnimeArtworkCache {
    static let shared = ModuleAnimeArtworkCache()

    private let maximumImageBytes = 6_000_000
    private let maximumDiskBytes = 60_000_000
    private let maximumDiskFiles = 240

    private let memory = NSCache<NSString, NSData>()
    private let session: URLSession
    private let directory: URL?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
        directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "KinetiqModuleArtwork/v1",
            isDirectory: true
        )
        memory.countLimit = 75
        memory.totalCostLimit = 28_000_000
    }

    func imageData(for url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }

        let key = Self.cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSString) {
            return cached as Data
        }

        if let directory {
            let file = directory.appendingPathComponent(key + ".img")
            if let data = try? Data(contentsOf: file),
               data.count > 0,
               data.count <= maximumImageBytes {
                memory.setObject(data as NSData, forKey: key as NSString,
                                 cost: data.count)
                return data
            }
        }

        guard !Task.isCancelled else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/avif,image/webp,image/*;q=0.9",
                         forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.url?.scheme?.lowercased() == "https",
                  response.mimeType?.lowercased().hasPrefix("image/") == true,
                  response.mimeType?.lowercased() != "image/svg+xml",
                  !data.isEmpty,
                  data.count <= maximumImageBytes else {
                return nil
            }

            memory.setObject(data as NSData, forKey: key as NSString,
                             cost: data.count)

            if let directory {
                try? FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let destination = directory.appendingPathComponent(key + ".img")
                try? data.write(to: destination, options: [.atomic])
                // Enforce the disk budget on every successful insert.
                pruneDiskCache(in: directory)
            }
            return data
        } catch {
            return nil
        }
    }

    private static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func pruneDiskCache(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else { return }

        let filesByAge = files.compactMap { url -> (URL, Int, Date)? in
            guard let attributes = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey
            ]) else { return nil }
            return (
                url,
                max(0, attributes.fileSize ?? 0),
                attributes.contentModificationDate ?? .distantPast
            )
        }.sorted { $0.2 < $1.2 }

        var totalBytes = filesByAge.reduce(0) { $0 + $1.1 }
        var totalFiles = filesByAge.count
        for file in filesByAge {
            guard totalBytes > maximumDiskBytes ||
                  totalFiles > maximumDiskFiles else { break }
            try? FileManager.default.removeItem(at: file.0)
            totalBytes -= file.1
            totalFiles -= 1
        }
    }
}

/// A reusable poster for Search, Explore, Favorites and Continue Watching.
/// When artwork is missing or unavailable, always shows real fallback UI.
struct ModuleAnimeArtworkView: View {
    let url: URL?
    @State private var artwork: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KinetiqPalette.cyan.opacity(0.20),
                    KinetiqPalette.violet.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artwork {
                GeometryReader { geometry in
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width,
                               height: geometry.size.height)
                        .clipped()
                }
                .accessibilityHidden(true)
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(KinetiqPalette.accent.opacity(0.85))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url?.absoluteString) {
            artwork = nil
            guard let url else { return }
            let data = await ModuleAnimeArtworkCache.shared.imageData(for: url)
            guard !Task.isCancelled,
                  let data,
                  let image = UIImage(data: data) else { return }
            artwork = image
        }
    }
}

struct ModuleAnimeEpisode: Identifiable {
    let id: String
    let number: String
    let href: String
    let subAvailable: Bool
    let dubAvailable: Bool
}

struct ModuleRemoteSubtitleTrack: Identifiable, Sendable {
    let url: URL
    let label: String
    let language: String?
    let format: ExternalSubtitleFormat?
    let headers: [String: String]
    var cookies: [ModuleStreamCookie] = []

    // The opaque UI identity never exposes a signed URL or request headers.
    var id: String {
        let fields = headers.keys.sorted().map { [$0, headers[$0] ?? ""] }
        let identity: [Any] = [url.absoluteString, language ?? "", fields]
        let data = (try? JSONSerialization.data(withJSONObject: identity)) ?? Data(url.absoluteString.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Optional Kinetiq metadata support. This does not change the documented
/// Synthetiq direct-URL / flat [label, URL] stream contract.
enum ModuleRemoteSubtitleDecoder {
    static func tracks(
        root: [String: Any], entry: [String: Any]?,
        streamURL: URL, streamHeaders: [String: String], baseURL: URL
    ) -> [ModuleRemoteSubtitleTrack] {
        var result: [ModuleRemoteSubtitleTrack] = []
        var seen = Set<String>()
        // Prefer server-specific metadata when the same track is also global.
        let containers = [entry, root].compactMap { $0 }
        for container in containers {
            for key in ["subtitles", "tracks", "captions"] {
                for candidate in candidates(container[key]) {
                    guard result.count < 24 else { return result }
                    let dictionary = candidate as? [String: Any] ?? [:]
                    if let kind = text(dictionary, keys: ["kind"])?.lowercased(),
                       !["captions", "subtitles", "subtitle"].contains(kind) { continue }
                    let rawURL = (candidate as? String) ??
                        text(dictionary, keys: ["url", "file", "src", "href"])
                    guard let rawURL, rawURL.utf8.count <= 8_192,
                          let url = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL,
                          ModuleSubtitleRequestPolicy.isAllowed(url) else { continue }

                    let declared = text(dictionary, keys: ["format", "mimeType"])
                        ?? text(dictionary, keys: ["type"])
                    let explicitFormat = declared.flatMap(format)
                    if let declared,
                       !["captions", "subtitles", "subtitle"].contains(declared.lowercased()),
                       explicitFormat == nil { continue }
                    let extensionFormat = ExternalSubtitleFormat(fileExtension: url.pathExtension)
                    if ["ass", "ssa", "ttml", "dfxp", "m3u8", "json", "jpg", "png"].contains(url.pathExtension.lowercased()) {
                        continue
                    }

                    let rawLanguage = text(dictionary, keys: ["language", "lang", "srclang"])
                    let language = rawLanguage?.lowercased().replacingOccurrences(of: "_", with: "-")
                    let safeLanguage = language.flatMap { value -> String? in
                        guard !value.isEmpty, value.count <= 35,
                              value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
                        return value
                    }
                    let rawLabel = text(dictionary, keys: ["label", "name", "title"]) ?? safeLanguage?.uppercased() ?? "Source subtitles"
                    let label = safeLabel(rawLabel)
                    let inherited = ModuleSubtitleRequestPolicy.sameOrigin(url, streamURL)
                        ? streamHeaders : [:]
                    var headers = ModuleSubtitleRequestPolicy.cleanHeaders(inherited)
                    for (name, value) in ModuleSubtitleRequestPolicy.cleanHeaders(dictionary["headers"] as? [String: String] ?? [:]) {
                        headers[name] = value
                    }
                    let track = ModuleRemoteSubtitleTrack(
                        url: url, label: label, language: safeLanguage,
                        format: explicitFormat ?? extensionFormat, headers: headers
                    )
                    if seen.insert(track.id).inserted { result.append(track) }
                }
            }
        }
        return result
    }

    static func format(_ value: String) -> ExternalSubtitleFormat? {
        switch value.lowercased().split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "srt", "subrip", "application/x-subrip": return .srt
        case "vtt", "webvtt", "text/vtt": return .vtt
        default: return nil
        }
    }

    private static func candidates(_ value: Any?) -> [Any] {
        if let array = value as? [Any] { return Array(array.prefix(48)) }
        if let string = value as? String { return [string] }
        guard let mapping = value as? [String: Any] else { return [] }
        if text(mapping, keys: ["url", "file", "src", "href"]) != nil { return [mapping] }
        return mapping.keys.sorted().prefix(48).compactMap { key -> Any? in
            if let url = mapping[key] as? String { return ["url": url, "label": key] }
            if var track = mapping[key] as? [String: Any] {
                if track["label"] == nil { track["label"] = key }
                return track
            }
            return nil
        }
    }

    private static func text(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func safeLabel(_ label: String) -> String {
        let lowered = label.lowercased()
        guard !lowered.contains("://"), !lowered.contains("token="),
              !lowered.contains("signature="), !lowered.contains("authorization"),
              !lowered.contains("api_key="), !lowered.contains("cookie="),
              !label.contains("?"), !label.hasPrefix("/") else {
            return "Source subtitles"
        }
        let sanitized = String(label.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }.map(String.init).joined().prefix(80))
        return sanitized.isEmpty ? "Source subtitles" : sanitized
    }
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
    var subtitles: [ModuleRemoteSubtitleTrack] = []

    /// Never display the full URL: it may contain signed query tokens.
    var hostName: String { url.host ?? "Unknown host" }

    /// Only explicit web/embed variants or known embed paths bypass AVPlayer.
    /// Ordinary HLS and MP4 links remain native even when hosted by a web CDN.
    var isWebEmbed: Bool {
        let kind = streamType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["embed", "iframe", "web", "webview", "html", "browser", "playerpage"]
            .contains(kind) { return true }
        if ["mp4", "m3u8", "mov", "m4v", "mpd", "webm", "mkv"]
            .contains(url.pathExtension.lowercased()) { return false }
        return url.pathComponents.contains { part in
            ["embed", "iframe"].contains(part.lowercased())
        }
    }
}

/// Restrict the optional web player to remote HTTPS pages. No app cookies,
/// module Authorization headers, or native AVURLAsset credentials are copied
/// to WebKit; browser playback deliberately runs in an ephemeral data store.
enum ModuleWebFallbackPolicy {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return false
        }
        if host == "::1" || host == "[::1]" || host == "0:0:0:0:0:0:0:1" {
            return false
        }
        let octets = host.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ Int($0) != nil }) {
            let numbers = octets.compactMap { UInt8($0) }
            guard numbers.count == 4 else { return false }
            // Block loopback, private, link-local and multicast ranges.
            let a = numbers[0], b = numbers[1]
            if a == 0 || a == 10 || a == 127 || a >= 224 ||
                (a == 169 && b == 254) ||
                (a == 172 && (16...31).contains(b)) ||
                (a == 192 && b == 168) ||
                (a == 100 && (64...127).contains(b)) { return false }
        }
        return true
    }
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
    @Published private(set) var resolutionDiagnosticEvents: [String] = []
    @Published private(set) var resolutionFailureCode: String?
    @Published private(set) var diagnosticEpisodeNumber: String?
    @Published private(set) var diagnosticLanguage = "sub"
    @Published private(set) var diagnosticCandidateCount = 0
    @Published private(set) var playerFailureDiagnostics: String?
    @Published private(set) var playerFailureReason: String?

    /// Preserve a native-player failure even after the full-screen view closes.
    func recordPlayerFailure(diagnostics: String, reason: String) {
        playerFailureDiagnostics = diagnostics.components(separatedBy: "\n")
            .prefix(75)
            .map { ModulePlaybackDiagnostics.redact($0) }
            .joined(separator: "\n")
        playerFailureReason = ModulePlaybackDiagnostics.redact(reason)
    }

    func clearPlayerFailure() {
        playerFailureDiagnostics = nil
        playerFailureReason = nil
    }

    /// Available before the AVPlayer screen exists (Error 01 and handler failures).
    var diagnosticSummary: String {
        let header = [
            "Kinetiq module diagnostics · Batch 05K playback triage",
            "Source: \(ModulePlaybackDiagnostics.redact(sourceName, limit: 80))",
            "Module version: \(ModulePlaybackDiagnostics.redact(runtime.moduleVersion, limit: 48))",
            "Package SHA-256 prefix: \(runtime.packageSHA256Prefix)",
            "Episode number: \(ModulePlaybackDiagnostics.redact(diagnosticEpisodeNumber ?? currentEpisode?.number ?? "Unknown", limit: 30))",
            "Language: \(diagnosticLanguage)",
            "Failure code: \(resolutionFailureCode ?? "none")",
            "Accepted server candidates: \(diagnosticCandidateCount)",
            "Error: \(ModulePlaybackDiagnostics.redact(playbackError ?? "none"))",
            "Resolution trace:"
        ]
        return (header + resolutionDiagnosticEvents + [
            "Privacy: URLs, headers, cookies, tokens and raw responses omitted."
        ]).joined(separator: "\n")
    }

    private func trace(_ message: String) {
        resolutionDiagnosticEvents.append(ModulePlaybackDiagnostics.redact(message))
        if resolutionDiagnosticEvents.count > 30 {
            resolutionDiagnosticEvents.removeFirst(resolutionDiagnosticEvents.count - 30)
        }
    }

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
        language: String,
        forceRefresh: Bool = false
    ) async -> Bool {
        if !forceRefresh {
            resolutionDiagnosticEvents = []
            playerFailureDiagnostics = nil
            playerFailureReason = nil
        }
        resolutionFailureCode = nil
        diagnosticCandidateCount = 0
        diagnosticLanguage = language.lowercased()
        diagnosticEpisodeNumber = episode.number
        trace("Resolution requested; language=\(diagnosticLanguage); refresh=\(forceRefresh)")

        guard let index = episodes.firstIndex(
            where: { $0.id == episode.id }
        ) else {
            playbackError = "This episode is no longer in the episode list."
            resolutionFailureCode = "EPISODE_NOT_FOUND"
            trace("Episode validation failed: not in queue")
            return false
        }

        guard supports(language, for: episode) else {
            playbackError = "This episode is not available in the selected language."
            resolutionFailureCode = "EPISODE_LANGUAGE_UNAVAILABLE"
            trace("Episode validation failed: language unavailable")
            return false
        }

        guard !isResolving else {
            trace("Skipped duplicate concurrent resolve request")
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
            var didRetryEmptyResult = false

            for rawReference in references {
                let reference = rawReference.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !reference.isEmpty,
                      attempted.insert(reference).inserted else {
                    continue
                }

                let attemptStart = Date()
                do {
                    let parameterKind = reference == episode.href ? "href" : "id"
                    trace("Calling extractStreamUrl with \(parameterKind) reference")
                    let parameters: [Any] = forceRefresh
                        ? [reference, language.lowercased(), true]
                        : [reference, language.lowercased()]
                    let response = try await runtime.call(
                        handler: "extractStreamUrl",
                        arguments: parameters
                    )
                    guard activeRequestID == requestID else { return false }
                    trace("Handler completed in \(String(format: "%.1f", Date().timeIntervalSince(attemptStart))) seconds")
                    trace("Handler returned: \(ModulePlaybackDiagnostics.responseShape(response))")
                    trace("Provider state: \(ModulePlaybackDiagnostics.sourceResponseStatus(response))")
                    trace("Source network: \(await runtime.networkDiagnosticSummary())")
                    let decoded: [ModuleResolvedStream]
                    do {
                        decoded = try ModuleRuntimeDecoder.streams(
                            from: response,
                            title: episodeTitle,
                            baseURL: runtime.baseURL,
                            defaultHeaders: runtime.defaultStreamHeaders
                        )
                    } catch {
                        resolutionFailureCode = ModulePlaybackDiagnostics.code(for: error)
                        trace("No accepted candidates on initial extraction: \(resolutionFailureCode ?? "unknown")")
                        // This is distinct from a player startup error: the
                        // source has not supplied anything AVPlayer can open.
                        // One explicit refresh may bypass stale provider cache
                        // and lets the module retry cold-start servers.
                        let isEmptyOrUnrecognized: Bool
                        if let moduleError = error as? ModuleRuntimeError {
                            switch moduleError {
                            case .invalidStream, .sourceNoMedia:
                                isEmptyOrUnrecognized = true
                            default:
                                isEmptyOrUnrecognized = false
                            }
                        } else {
                            isEmptyOrUnrecognized = false
                        }
                        guard !forceRefresh, !didRetryEmptyResult,
                              isEmptyOrUnrecognized else {
                            throw error
                        }
                        didRetryEmptyResult = true
                        trace("Retrying extractStreamUrl once with refresh=true")
                        let fresh = try await runtime.call(
                            handler: "extractStreamUrl",
                            arguments: [reference, language.lowercased(), true]
                        )
                        guard activeRequestID == requestID else { return false }
                        trace("Refresh returned: \(ModulePlaybackDiagnostics.responseShape(fresh))")
                        trace("Refresh provider state: \(ModulePlaybackDiagnostics.sourceResponseStatus(fresh))")
                        trace("Source network after refresh: \(await runtime.networkDiagnosticSummary())")
                        do {
                            decoded = try ModuleRuntimeDecoder.streams(
                                from: fresh, title: episodeTitle,
                                baseURL: runtime.baseURL,
                                defaultHeaders: runtime.defaultStreamHeaders
                            )
                            trace("Refresh found \(decoded.count) playable candidate(s)")
                        } catch {
                            trace("Refresh still returned no accepted stream")
                            throw error
                        }
                    }
                    var choices = decoded
                    diagnosticCandidateCount = choices.count
                    trace("Decoder accepted \(choices.count) stream(s); native=\(choices.filter { !$0.isWebEmbed }.count), web=\(choices.filter(\.isWebEmbed).count)")
                    let knownHeaderNames = Set(choices.flatMap { $0.headers.keys.map { $0.lowercased() } })
                    trace("Playback request context: module default headers=\(runtime.defaultStreamHeaders.count), effective header names=\(knownHeaderNames.count), user-agent=\(knownHeaderNames.contains("user-agent")), referer=\(knownHeaderNames.contains("referer")), origin=\(knownHeaderNames.contains("origin"))")

                    guard activeRequestID == requestID else {
                        return false
                    }

                    // Capture cookies only for each HTTPS stream host;
                    // never pass source-domain cookies to unrelated CDNs.
                    var subtitleCookies: [URL: [ModuleStreamCookie]] = [:]
                    for index in choices.indices {
                        let streamURL = choices[index].url
                        let sourceCookies = await runtime.cookies(
                            for: streamURL
                        )
                        choices[index].cookies = sourceCookies
                        for subtitleIndex in choices[index].subtitles.indices {
                            let url = choices[index].subtitles[subtitleIndex].url
                            if subtitleCookies[url] == nil {
                                subtitleCookies[url] = await runtime.cookies(for: url)
                            }
                            choices[index].subtitles[subtitleIndex].cookies = subtitleCookies[url] ?? []
                        }
                    }

                    guard activeRequestID == requestID else {
                        return false
                    }

                    // Batch 05D: use recent, verified playback results to
                    // avoid repeatedly opening known-broken hosts. New hosts
                    // keep their source-provided order; native precedes web.
                    choices = ModuleServerHealthStore.shared.ordered(
                        choices,
                        sourceID: sourceID,
                        sourceName: sourceName
                    )
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
                    resolutionFailureCode = nil
                    trace("Selected \(preferredStream.isWebEmbed ? "web embed" : "native stream") using server-health ranking")
                    KinetiqModuleHealthStore.shared.record(
                        sourceID: sourceID, version: runtime.moduleVersion,
                        packagePrefix: runtime.packageSHA256Prefix,
                        succeeded: true
                    )
                    return true
                } catch {
                    resolutionFailureCode = ModulePlaybackDiagnostics.code(for: error)
                    trace("\(reference == episode.href ? "href" : "id") attempt failed after \(String(format: "%.1f", Date().timeIntervalSince(attemptStart)))s: \(resolutionFailureCode ?? "unknown")")
                    if let moduleError = error as? ModuleRuntimeError {
                        if case .handlerTimedOut = moduleError { throw moduleError }
                        if case .handlerFailed(let providerText) = moduleError {
                            let category = ModulePlaybackDiagnostics.providerErrorCategory(providerText)
                            trace("Handler failure class: \(category)")
                            // Retrying another identifier after explicit 429,
                            // 403 or a challenge can multiply denied requests.
                            if ["SOURCE_RATE_LIMITED", "SOURCE_ACCESS_DENIED",
                                "SOURCE_CHALLENGE"].contains(category) {
                                throw moduleError
                            }
                        }
                    }
                    trace("Source network at failure: \(await runtime.networkDiagnosticSummary())")
                    lastError = error
                }
            }

            throw lastError ?? ModuleRuntimeError.invalidStream
        } catch {
            guard activeRequestID == requestID else {
                return false
            }

            resolutionFailureCode = ModulePlaybackDiagnostics.code(for: error)
            playbackError = error.localizedDescription
            trace("Resolution stopped: \(resolutionFailureCode ?? "unknown")")
            KinetiqModuleHealthStore.shared.record(
                sourceID: sourceID, version: runtime.moduleVersion,
                packagePrefix: runtime.packageSHA256Prefix,
                succeeded: false, failureCode: resolutionFailureCode
            )
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
            language: selectedLanguage,
            forceRefresh: true
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

                let synopsis = string(
                    item,
                    keys: ["description", "synopsis", "summary", "overview"]
                ).map { String($0.prefix(3500)) }

                return ModuleAnimeItem(
                    id: id,
                    title: title,
                    href: href,
                    imageURL: resolvedURL(
                        image,
                        baseURL: baseURL
                    ),
                    synopsis: synopsis
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

        let synopsis = string(
            dictionary,
            keys: ["description", "synopsis", "summary", "overview", "plot"]
        ).map { String($0.prefix(3500)) } ?? fallback.synopsis

        return ModuleAnimeItem(
            id: id,
            title: title,
            href: href,
            imageURL: resolvedURL(
                image,
                baseURL: baseURL
            ) ?? fallback.imageURL,
            synopsis: synopsis
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

    /// Recognize the Synthetiq direct URL/pair contract and bounded nested
    /// server, source, mirror and quality containers. Providers do not all
    /// serialize their options at the same nesting level. Only URLs already
    /// supplied by the selected module are offered; Kinetiq never invents a
    /// stream or silently switches to a different module/source.
    static func streams(
        from value: Any,
        title: String,
        baseURL: URL,
        defaultHeaders: [String: String] = [:]
    ) throws -> [ModuleResolvedStream] {
        // Some modules serialize a valid streams/servers JSON object into a
        // string. Decode only bounded JSON containers; never evaluate code,
        // guess opaque provider tokens, or alter normal HTTPS/MP4/HLS URLs.
        func jsonContainer(_ value: String) -> Any? {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (text.hasPrefix("{") || text.hasPrefix("[")),
                  text.utf8.count <= 524_288,
                  let data = text.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data),
                  result is [String: Any] || result is [Any] else { return nil }
            return result
        }
        if let text = value as? String,
           let nested = jsonContainer(text) {
            return try streams(
                from: nested, title: title, baseURL: baseURL,
                defaultHeaders: defaultHeaders
            )
        }
        let root = value as? [String: Any] ?? [:]
        let maximumChoices = 24
        let maximumDepth = 6
        var choices: [ModuleResolvedStream] = []
        var seen = Set<String>()

        func asHeaders(_ object: Any?) -> [String: String] {
            guard let dictionary = object as? [String: Any] else { return [:] }
            var result: [String: String] = [:]
            for (name, value) in dictionary {
                guard let text = value as? String,
                      name.count <= 80,
                      text.count <= 2_048,
                      !name.contains("\r"), !name.contains("\n"),
                      !text.contains("\r"), !text.contains("\n") else { continue }
                result[name] = text
            }
            return result
        }

        func mergeHeaders(
            _ parent: [String: String],
            _ child: [String: String]
        ) -> [String: String] {
            var merged = parent
            // Header names are case-insensitive; a child override must not
            // accidentally send two differing Referer/Authorization fields.
            for (key, value) in child {
                if let existing = merged.keys.first(where: {
                    $0.caseInsensitiveCompare(key) == .orderedSame
                }) {
                    merged.removeValue(forKey: existing)
                }
                merged[key] = value
            }
            return merged
        }

        func labelLooksLikeName(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let low = trimmed.lowercased()
            return !trimmed.contains("/") && !trimmed.contains("://")
                && !low.contains(".m3u8") && !low.contains(".mp4")
        }

        let additionalURLKeys = [
            "videoUrl", "videoURL", "video_url", "stream_url", "playUrl",
            "playURL", "play_url", "playbackUrl", "playbackURL",
            "manifestUrl", "manifestURL", "hlsUrl", "hlsURL",
            "masterUrl", "masterURL", "playlistUrl", "playlistURL",
            "hls", "m3u8", "mp4"
        ]
        let directURLKeys = [
            "url", "streamUrl", "streamURL", "file", "src", "link", "href"
        ] + additionalURLKeys
        let streamContainerKeys = [
            "streams", "sources", "servers", "links", "mirrors", "qualities",
            "variants", "videos", "files", "data", "result", "stream", "source", "video",
            "playback", "playlist", "media", "serverList", "server_list",
            "availableStreams", "available_servers", "urlList", "url_list"
        ]

        func append(
            urlString: String?,
            label: String?,
            headers: [String: String],
            streamType: String,
            subtitleContainer: [String: Any]?
        ) {
            guard choices.count < maximumChoices,
                  let urlString else { return }
            let candidate = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = candidate.lowercased()
            // Bare opaque provider IDs are not media URLs and must not become
            // fabricated URLs relative to the module homepage.
            let isUsableReference = lower.hasPrefix("https://") ||
                lower.hasPrefix("http://") || candidate.hasPrefix("/") ||
                candidate.contains("/") || [".m3u8", ".mp4", ".m4v", ".mov", ".ts"]
                    .contains(where: { lower.hasPrefix($0) || lower.hasSuffix($0) })
            guard isUsableReference,
                  let url = resolvedURL(candidate, baseURL: baseURL),
                  url.user == nil, url.password == nil else { return }

            // Reject insecure or local provider pages before listing them.
            let isEmbedPage = ["embed", "iframe", "web", "webview", "html", "browser", "playerpage"]
                .contains(streamType.lowercased()) || url.pathComponents.contains {
                    ["embed", "iframe"].contains($0.lowercased())
                }
            if isEmbedPage && !ModuleWebFallbackPolicy.allows(url) { return }

            let incomingLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lowerLabel = incomingLabel.lowercased()
            let hiddenToken = lowerLabel.contains("://")
                || lowerLabel.contains("token=")
                || lowerLabel.contains("signature=")
                || lowerLabel.contains("key=")
            let safeLabel = incomingLabel.isEmpty || hiddenToken
                ? (url.host ?? "Auto")
                : String(incomingLabel.prefix(80))

            let headerSignature = headers.keys.sorted(by: {
                $0.lowercased() < $1.lowercased()
            }).map { "\($0.lowercased())=\(headers[$0] ?? "")" }
                .joined(separator: "&")
            let fingerprint = url.absoluteString + "|" + headerSignature
            guard seen.insert(fingerprint).inserted else { return }

            choices.append(ModuleResolvedStream(
                title: title,
                label: safeLabel,
                url: url,
                headers: headers,
                streamType: streamType,
                subtitles: ModuleRemoteSubtitleDecoder.tracks(
                    root: root,
                    entry: subtitleContainer,
                    streamURL: url,
                    streamHeaders: headers,
                    baseURL: baseURL
                )
            ))
        }

        let initialHeaders = mergeHeaders(
            defaultHeaders,
            mergeHeaders(asHeaders(root["requestHeaders"]), asHeaders(root["headers"]))
        )
        let initialType = string(root, keys: ["streamType", "type"]) ?? "auto"

        // Each branch inherits its *own* headers, rather than applying
        // another server's credentials or Referer to unrelated mirrors.
        func walk(
            _ entry: Any,
            label: String? = nil,
            headers: [String: String] = [:],
            type: String = "auto",
            depth: Int = 0
        ) {
            guard depth <= maximumDepth, choices.count < maximumChoices else { return }

            if let direct = entry as? String {
                if let nested = jsonContainer(direct) {
                    walk(nested, label: label, headers: headers,
                         type: type, depth: depth + 1)
                    return
                }
                append(urlString: direct, label: label, headers: headers,
                       streamType: type, subtitleContainer: nil)
                return
            }

            if let list = entry as? [Any] {
                // Synthetiq contract: alternating quality and stream URL.
                // Treat the array as pairs, not unlabeled independent URLs.
                let pairs = list.count >= 2 && list.count % 2 == 0 &&
                    stride(from: 0, to: list.count, by: 2).allSatisfy { i in
                        guard let name = list[i] as? String,
                              let address = list[i + 1] as? String else { return false }
                        return labelLooksLikeName(name) &&
                            (address.hasPrefix("https://") || address.hasPrefix("/"))
                    }
                if pairs {
                    for i in stride(from: 0, to: min(list.count, maximumChoices * 2), by: 2) {
                        append(urlString: list[i + 1] as? String,
                               label: list[i] as? String,
                               headers: headers, streamType: type,
                               subtitleContainer: nil)
                    }
                } else {
                    for item in list.prefix(maximumChoices) {
                        walk(item, label: label, headers: headers,
                             type: type, depth: depth + 1)
                    }
                }
                return
            }

            guard let object = entry as? [String: Any] else { return }
            let ownHeaders = mergeHeaders(
                headers,
                mergeHeaders(asHeaders(object["requestHeaders"]), asHeaders(object["headers"]))
            )
            let ownType = string(object, keys: ["streamType", "type"]) ?? type
            let ownLabel = string(object, keys: ["label", "name", "title", "server", "quality", "provider"])
                ?? label
            let ownURL = string(object, keys: directURLKeys)
            if ownURL != nil {
                append(urlString: ownURL, label: ownLabel, headers: ownHeaders,
                       streamType: ownType, subtitleContainer: object)
            }
            // Web-only providers return a player page rather than a media
            // file. Keep those choices visible, but tag them so AVPlayer
            // never tries to decode an HTML document as video.
            for webKey in ["embedUrl", "embedURL", "iframeUrl", "iframeURL",
                           "playerUrl", "playerURL", "webUrl", "webURL",
                           "playerPage", "player_page", "embed", "iframe"] {
                if let page = object[webKey] as? String {
                    append(urlString: page, label: ownLabel, headers: [:],
                           streamType: "embed", subtitleContainer: nil)
                } else if let pages = object[webKey] as? [Any] {
                    walk(pages, label: ownLabel, headers: [:], type: "embed", depth: depth + 1)
                } else if let webEntry = object[webKey] as? [String: Any] {
                    walk(webEntry, label: ownLabel, headers: [:], type: "embed", depth: depth + 1)
                }
            }

            // Some modules wrap maps of server names in `data` / `result`
            // without a `servers` key. Only accept entries that look like
            // playable stream URLs or nested stream dictionaries.
            let containerKeys = streamContainerKeys
            let excludedMetadata = Set([
                "poster", "image", "cover", "thumbnail", "artwork", "banner", "icon",
                "subtitles", "captions", "tracks", "description", "title", "name",
                "headers", "requestheaders", "type", "streamtype", "provider",
                "language", "lang", "id", "episode", "quality", "duration", "metadata"
            ])
            if ownURL == nil,
               !object.keys.contains(where: { containerKeys.contains($0) }),
               depth < maximumDepth {
                for name in object.keys.sorted().prefix(maximumChoices) {
                    guard !excludedMetadata.contains(name.lowercased()),
                          let candidate = object[name] else { continue }
                    if let urlString = candidate as? String,
                       let url = resolvedURL(urlString, baseURL: baseURL),
                       !["jpg", "jpeg", "png", "webp", "gif", "svg", "avif", "vtt", "srt"]
                          .contains(url.pathExtension.lowercased()) {
                        append(urlString: urlString, label: name, headers: ownHeaders,
                               streamType: ownType, subtitleContainer: object)
                    } else if let nested = candidate as? [String: Any],
                              nested.keys.contains(where: {
                                  (directURLKeys + streamContainerKeys).contains($0)
                              }) {
                        walk(nested, label: name, headers: ownHeaders,
                             type: ownType, depth: depth + 1)
                    }
                }
            }

            // Ordered streams first; qualities and mirrors are used as
            // additional playable alternatives if their entries have URLs.
            for key in containerKeys {
                guard let nested = object[key] else { continue }
                if let mapping = nested as? [String: Any],
                   !mapping.keys.contains(where: {
                       (directURLKeys + streamContainerKeys).contains($0)
                   }) {
                    // e.g. { "Vidstream": {"url": "..."}, "Mirror": "https://..." }
                    for name in mapping.keys.sorted().prefix(maximumChoices) {
                        guard let candidate = mapping[name] else { continue }
                        walk(candidate, label: name, headers: ownHeaders,
                             type: ownType, depth: depth + 1)
                    }
                } else {
                    walk(nested, label: ownLabel, headers: ownHeaders,
                         type: ownType, depth: depth + 1)
                }
            }
        }

        if root.isEmpty {
            walk(value, label: "Auto", headers: initialHeaders, type: initialType)
        } else {
            // Preserve the source's ordering of viable streams, followed by
            // server alternatives, then the direct URL as a last resort.
            for key in streamContainerKeys {
                if let group = root[key] {
                    walk(group, headers: initialHeaders, type: initialType)
                }
            }
            if let direct = string(root, keys: directURLKeys) {
                append(urlString: direct,
                       label: string(root, keys: ["label", "name", "quality"]) ?? "Auto",
                       headers: initialHeaders,
                       streamType: initialType,
                       subtitleContainer: root)
            }
            for webKey in ["embedUrl", "embedURL", "iframeUrl", "iframeURL",
                           "playerUrl", "playerURL", "webUrl", "webURL",
                           "playerPage", "player_page", "embed", "iframe"] {
                if let page = root[webKey] as? String {
                    append(urlString: page,
                           label: string(root, keys: ["label", "name", "quality"]) ?? "Web player",
                           headers: [:], streamType: "embed", subtitleContainer: nil)
                } else if let pages = root[webKey] as? [Any] {
                    walk(pages, label: "Web player", headers: [:], type: "embed")
                } else if let webEntry = root[webKey] as? [String: Any] {
                    walk(webEntry, label: "Web player", headers: [:], type: "embed")
                }
            }
        }

        guard !choices.isEmpty else {
            // Some source APIs distinguish a genuinely unavailable episode
            // from a malformed response with an explicit empty array.
            // Return no fabricated media URL, and retain this distinction in
            // the on-device failure report.
            let containsExplicitEmpty = ["streams", "sources", "servers"]
                .contains { key in
                    if let entries = root[key] as? [Any] { return entries.isEmpty }
                    return false
                }
            if root["error"] != nil || root["errors"] != nil ||
               root["success"] as? Bool == false {
                // Error and empty-stream fields may coexist. Preserve
                // access-denied/rate-limit/host-failure diagnostics instead
                // of flattening every provider error to "no media".
                let providerClass = ModulePlaybackDiagnostics.sourceResponseStatus(root)
                if containsExplicitEmpty && providerClass.contains("SOURCE_NO_MEDIA") {
                    throw ModuleRuntimeError.sourceNoMedia
                }
                throw ModuleRuntimeError.sourceReportedFailure
            }
            if containsExplicitEmpty {
                throw ModuleRuntimeError.sourceNoMedia
            }
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

// 05L: Trust follows the *repository* and its pinned catalogue identity, not
// each package hash. Native ZIP SHA-256 verification remains mandatory and
// publisher signatures are NEVER inferred from the repository's own claims.
@MainActor
enum ModuleRuntimeTrustStore {
    static func isTrusted(_ record: InstalledModuleRecord) -> Bool {
        guard let repository = ModuleSourceStore.shared.repositories.first(where: {
            $0.url.absoluteString == record.repositoryURL
        }) else { return false }
        let trust = KinetiqRepositoryTrustStore.shared
        return trust.allowsRuntime(for: repository, installedModuleID: record.moduleID)
    }

    static func trust(_ record: InstalledModuleRecord) {
        guard let repository = ModuleSourceStore.shared.repositories.first(where: {
            $0.url.absoluteString == record.repositoryURL
        }) else { return }
        KinetiqRepositoryTrustStore.shared.approve(repository)
    }
}


// Shared anime collection models and persistence now live in MainTabView.swift.

private enum ModuleCatalogueSection: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case search = "Search"
    case favorites = "Favorites"
    case recent = "Recent"
    var id: String { rawValue }
}

private enum ModuleCatalogueSort: String, CaseIterable, Identifiable {
    case source = "Source order"
    case title = "Title A–Z"
    case reverseTitle = "Title Z–A"
    var id: String { rawValue }
}

// MARK: - Module Browser Preferences

private enum ModuleBrowserPreferences {
    private static let key = "kinetiq.modules.catalogueSections.v1"

    static func section(for sourceID: String) -> ModuleCatalogueSection {
        let entries = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return ModuleCatalogueSection(rawValue: entries[sourceID] ?? "") ?? .explore
    }

    static func save(_ section: ModuleCatalogueSection, for sourceID: String) {
        guard !sourceID.isEmpty else { return }
        var entries = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        if entries.count >= 100 && entries[sourceID] == nil {
            entries.removeValue(forKey: entries.keys.sorted().first ?? "")
        }
        entries[sourceID] = section.rawValue
        UserDefaults.standard.set(entries, forKey: key)
    }
}

// MARK: - Module Browser

struct ModuleBrowserView: View {

    let source: ModuleSourceOption

    @StateObject private var packageStore =
        ModulePackageStore.shared
    @StateObject private var repositoryTrustStore =
        KinetiqRepositoryTrustStore.shared
    @StateObject private var sourceStore = ModuleSourceStore.shared

    @State private var runtime: SynthetiqModuleRuntime?

    @State private var searchQuery = ""
    @State private var results: [ModuleAnimeItem] = []

    @State private var selectedItem: ModuleAnimeItem?
    @State private var catalogueSection: ModuleCatalogueSection = .explore
    @State private var catalogueSort: ModuleCatalogueSort = .source
    @AppStorage("kinetiq.modules.discovery.posterGrid")
    private var usesPosterGrid = true
    @State private var completedSearchQuery: String?
    @StateObject private var animeCollection = ModuleAnimeCollectionStore.shared

    @State private var isPreparingRuntime = false
    @State private var isSearching = false
    @State private var runtimePreparationError: String?
    @State private var searchFailure: String?
    @State private var lastSearchDiagnostics: String?
    @State private var activePreparationID: UUID?
    @State private var activeSearchID: UUID?

    @State private var showingTrustConfirmation = false

    private var installedRecord: InstalledModuleRecord? {
        packageStore.installedModule(for: source)
    }

    private var runtimeIdentity: String {
        guard let record = installedRecord else {
            return "not-installed"
        }

        return "\(record.sourceID)|\(record.packageSHA256)|\(isTrusted)"
    }

    private var isTrusted: Bool {
        guard let record = installedRecord,
              let repository = sourceStore.repositories.first(where: {
                  $0.url.absoluteString == record.repositoryURL
              }) else { return false }
        return repositoryTrustStore.allowsRuntime(
            for: repository, installedModuleID: record.moduleID
        )
    }

    // 05N: A repository may advertise a newer package while the last-known-
    // good version remains installed. Keep that version playable until the
    // user updates it; do not force new downloads or erase playback history.
    private func hasInstalledFiles(_ record: InstalledModuleRecord) -> Bool {
        FileManager.default.fileExists(atPath: record.entryScriptPath)
            && FileManager.default.fileExists(atPath: record.manifestPath)
    }

    var body: some View {
        Group {
            if source.module.contentType?.lowercased() != "video" {
                unsupportedContent
            } else if let record = installedRecord,
                      !hasInstalledFiles(record) {
                notInstalled
            } else if installedRecord == nil {
                notInstalled
            } else if !isTrusted {
                trustRequired
            } else if let runtimePreparationError {
                VStack(spacing: 12) {
                    KinetiqAsyncStateView(
                        kind: .failure,
                        title: "Module Could Not Load",
                        message: runtimePreparationError,
                        actionTitle: "Retry Module Loading"
                    ) {
                        Task { await prepareRuntime() }
                    }
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = [
                            "Kinetiq module diagnostics · Batch 05F",
                            "Source: \(ModulePlaybackDiagnostics.redact(source.title, limit: 80))",
                            "Phase: initialize runtime",
                            "Details: \(ModulePlaybackDiagnostics.redact(runtimePreparationError))"
                        ].joined(separator: "\n")
                    }
                    .buttonStyle(.bordered)
                }
            } else if runtime == nil {
                runtimeLoading
            } else {
                animeCatalogue
            }
        }
        .task(id: runtimeIdentity) {
            catalogueSection = ModuleBrowserPreferences.section(for: source.id)
            await prepareRuntime()
        }
        .onChange(of: catalogueSection) { _, section in
            ModuleBrowserPreferences.save(section, for: source.id)
        }
        .onDisappear {
            activeSearchID = nil
            activePreparationID = nil
            isSearching = false
            isPreparingRuntime = false
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
            "Trust this repository?",
            isPresented: $showingTrustConfirmation
        ) {
            Button("Trust Repository and Load") {
                trustAndLoad()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Approving the repository lets its installed modules run without asking again for every version or source. ZIP SHA-256 integrity is still checked; community approval does not cryptographically authenticate the publisher."
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
                "Repository Trust Required",
                systemImage: "hand.raised.fill"
            )
        } description: {
            Text(
                "Approve this community repository once before running its installed modules. Publisher identity changes will require review."
            )
        } actions: {
            Button {
                showingTrustConfirmation = true
            } label: {
                Label(
                    "Trust Repository",
                    systemImage: "checkmark.shield"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(KinetiqPalette.accent)
        }
    }

    // MARK: Runtime Loading

    private var runtimeLoading: some View {
        KinetiqAsyncStateView(
            kind: .loading,
            title: "Loading \(source.title)",
            message: "Preparing the installed module runtime."
        )
    }

    @MainActor
    private func prepareRuntime() async {
        let requestID = UUID()
        activePreparationID = requestID
        activeSearchID = nil
        isSearching = false
        runtime = nil
        results = []
        searchQuery = ""
        completedSearchQuery = nil
        runtimePreparationError = nil
        searchFailure = nil
        lastSearchDiagnostics = nil

        guard let record = installedRecord,
              hasInstalledFiles(record),
              ModuleRuntimeTrustStore.isTrusted(record) else {
            return
        }

        isPreparingRuntime = true
        defer {
            if activePreparationID == requestID {
                isPreparingRuntime = false
            }
        }

        do {
            let loadedRuntime = try SynthetiqModuleRuntime(record: record)
            guard !Task.isCancelled,
                  activePreparationID == requestID,
                  runtimeIdentity == "\(record.sourceID)|\(record.packageSHA256)|\(isTrusted)" else { return }
            runtime = loadedRuntime
        } catch {
            guard !Task.isCancelled,
                  activePreparationID == requestID else { return }
            runtimePreparationError = error.localizedDescription
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
        VStack(alignment: .leading, spacing: 0) {
            Picker("Anime collection", selection: $catalogueSection) {
                ForEach(ModuleCatalogueSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .accessibilityLabel("Anime collection section")

            switch catalogueSection {
            case .explore:
                exploreContent

            case .search:
                searchBar
                if isSearching {
                    ProgressView("Searching \(source.title)…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                } else if let searchFailure {
                    VStack(spacing: 10) {
                        KinetiqAsyncStateView(
                            kind: .failure,
                            title: "Search Failed",
                            message: searchFailure,
                            actionTitle: "Retry Search"
                        ) {
                            Task { await searchAnime(queryOverride: completedSearchQuery) }
                        }
                        Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = lastSearchDiagnostics
                                ?? "No search diagnostics available."
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 20)
                } else if results.isEmpty {
                    VStack(spacing: 10) {
                        KinetiqAsyncStateView(
                            kind: .empty,
                            title: completedSearchQuery == nil ? "Search Anime" : "No Matches",
                            message: completedSearchQuery == nil
                                ? "Enter a title or choose a topic from Explore."
                                : "The source returned no results for \"\(completedSearchQuery ?? "")\". Try another search."
                        )
                        if let lastSearchDiagnostics {
                            Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = lastSearchDiagnostics
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 20)
                } else {
                    collectionResults(
                        results,
                        title: "Search results",
                        showRecent: false,
                        allowSorting: true
                    )
                }

            case .favorites:
                if animeCollection.favorites(for: source.id).isEmpty {
                    ContentUnavailableView(
                        "No Saved Anime",
                        systemImage: "heart",
                        description: Text("Tap the heart on an anime to save it from this source.")
                    )
                    .padding(.top, 22)
                } else {
                    collectionResults(
                        animeCollection.favorites(for: source.id).map(\.anime),
                        title: "Saved from \(source.title)",
                        showRecent: false,
                        allowSorting: false
                    )
                }

            case .recent:
                if animeCollection.recentEpisodes(for: source.id).isEmpty {
                    ContentUnavailableView(
                        "No Recent Episodes",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Episodes you open from this source appear here.")
                    )
                    .padding(.top, 22)
                } else {
                    collectionResults(
                        animeCollection.recentEpisodes(for: source.id).map(\.anime),
                        title: "Recently opened",
                        showRecent: true,
                        allowSorting: false
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Compatible modules can provide genuine, source-owned Home shelves.
    // Older modules retain saved entries and explicitly labeled search
    // shortcuts; Kinetiq never invents trending or rating data.
    private var exploreContent: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DISCOVER ON YOUR SOURCE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(KinetiqPalette.accent)

                Text("Explore anime")
                    .font(.system(size: 27, weight: .bold))

                Text("Search results come directly from \(source.title). Choose a topic or search for a title.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let runtime {
                KinetiqSourceDiscoveryView(
                    runtime: runtime,
                    sourceID: source.id,
                    sourceName: source.title
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Explore by search", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)

                Text("These are search suggestions, not source-provided trending rankings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(["Romance", "Action", "Fantasy", "Comedy", "Mystery", "Adventure"], id: \.self) { term in
                        Button {
                            startSuggestedSearch(term)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .bold))
                                Text(term)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .frame(height: 51)
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search \(term) on \(source.title)")
                    }
                }
            }

            let inProgress = animeCollection.continueWatching.filter {
                $0.sourceID == source.id && !$0.isCompleted
            }
            if !inProgress.isEmpty {
                exploreShelf(
                    inProgress,
                    title: "Continue watching",
                    subtitle: "Continue a previously started episode"
                )
            }

            let saved = animeCollection.favorites(for: source.id)
            if !saved.isEmpty {
                exploreShelf(
                    Array(saved.prefix(12)),
                    title: "Your saved anime",
                    subtitle: "Favorites from this source"
                )
            }

            Button {
                catalogueSection = .search
            } label: {
                Label("Search \(source.title)", systemImage: "magnifyingglass")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinetiqPalette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
    }

    private func exploreShelf(
        _ entries: [ModuleAnimeCollectionEntry],
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 19, weight: .bold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            selectedItem = entry.anime
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ModuleAnimeArtworkView(url: entry.anime.imageURL)
                                    .frame(width: 124, height: 164)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                Text(entry.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(width: 124, alignment: .leading)
                                if entry.playbackFraction > 0, !entry.isCompleted {
                                    ProgressView(value: entry.playbackFraction)
                                        .tint(KinetiqPalette.accent)
                                        .frame(width: 124)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(entry.title)")
                    }
                }
            }
        }
    }

    private func startSuggestedSearch(_ term: String) {
        searchQuery = term
        catalogueSection = .search
        Task { await searchAnime() }
    }

    private func collectionResults(
        _ originalItems: [ModuleAnimeItem],
        title: String,
        showRecent: Bool,
        allowSorting: Bool
    ) -> some View {
        // Some modules return the same anime more than once in a search.
        // Dedupe by the provider's real identity without renaming results.
        var seen = Set<String>()
        let unique = originalItems.filter { seen.insert($0.id).inserted }

        let items: [ModuleAnimeItem]
        if allowSorting && catalogueSort == .title {
            items = unique.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        } else if allowSorting && catalogueSort == .reverseTitle {
            items = unique.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedDescending
            }
        } else {
            items = unique
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(items.count) \(items.count == 1 ? "title" : "titles")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if allowSorting {
                    Menu {
                        ForEach(ModuleCatalogueSort.allCases) { option in
                            Button {
                                catalogueSort = option
                            } label: {
                                if option == catalogueSort {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .accessibilityLabel("Sort anime")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usesPosterGrid.toggle()
                    }
                } label: {
                    Image(systemName: usesPosterGrid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 38)
                }
                .accessibilityLabel(usesPosterGrid ? "Switch to list" : "Switch to grid")
            }

            if usesPosterGrid {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12),
                              GridItem(.flexible(), spacing: 12)],
                    alignment: .center,
                    spacing: 13
                ) {
                    ForEach(items) { item in
                        animeGridCard(item, showRecent: showRecent)
                    }
                }
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(items) { item in
                        animeListCard(item, showRecent: showRecent)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private func animeGridCard(
        _ item: ModuleAnimeItem,
        showRecent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                selectedItem = item
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ModuleAnimeArtworkView(url: item.imageURL)
                        .frame(height: 199)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(item.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(height: 37, alignment: .topLeading)
                    if showRecent,
                       let entry = animeCollection.recentEpisodes(for: source.id)
                        .first(where: { $0.animeID == item.id }) {
                        Text(entry.playbackLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button {
                    toggleFavorite(item)
                } label: {
                    Image(systemName: isFavorite(item) ? "heart.fill" : "heart")
                        .frame(width: 38, height: 34)
                        .foregroundStyle(KinetiqPalette.accent)
                }
                .accessibilityLabel(isFavorite(item) ? "Remove favorite" : "Save to favorites")

                Spacer(minLength: 0)

                if showRecent {
                    Button(role: .destructive) {
                        animeCollection.removeRecent(
                            sourceID: source.id, animeID: item.id
                        )
                    } label: {
                        Image(systemName: "xmark.circle")
                            .frame(width: 38, height: 34)
                    }
                    .accessibilityLabel("Remove recent episode")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 27)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    private func animeListCard(
        _ item: ModuleAnimeItem,
        showRecent: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedItem = item
            } label: {
                HStack(spacing: 12) {
                    ModuleAnimeArtworkView(url: item.imageURL)
                        .frame(width: 75, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Text(source.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(KinetiqPalette.accent)
                        if showRecent,
                           let entry = animeCollection.recentEpisodes(for: source.id)
                            .first(where: { $0.animeID == item.id }) {
                            Text(entry.playbackLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 12) {
                Button {
                    toggleFavorite(item)
                } label: {
                    Image(systemName: isFavorite(item) ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(KinetiqPalette.accent)
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel(isFavorite(item) ? "Remove favorite" : "Save to favorites")

                if showRecent {
                    Button(role: .destructive) {
                        animeCollection.removeRecent(
                            sourceID: source.id, animeID: item.id
                        )
                    } label: {
                        Image(systemName: "xmark.circle")
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Remove recent episode")
                }
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    private func isFavorite(_ item: ModuleAnimeItem) -> Bool {
        animeCollection.isFavorite(sourceID: source.id, animeID: item.id)
    }

    private func toggleFavorite(_ item: ModuleAnimeItem) {
        animeCollection.toggleFavorite(
            sourceID: source.id,
            sourceName: source.title,
            anime: item
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search anime…", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await searchAnime() } }

            Button {
                Task { await searchAnime() }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 23))
                    .foregroundStyle(KinetiqPalette.accent)
            }
            .disabled(searchQuery.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty)
            .accessibilityLabel("Search anime")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 5)
    }

    @MainActor
    private func searchAnime(queryOverride: String? = nil) async {
        let query = (queryOverride ?? searchQuery).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty, let runtime else { return }

        let requestID = UUID()
        activeSearchID = requestID
        isSearching = true
        completedSearchQuery = query
        results = []
        searchFailure = nil
        lastSearchDiagnostics = nil
        defer {
            if activeSearchID == requestID {
                isSearching = false
            }
        }

        do {
            let response = try await runtime.call(
                handler: "searchResults", arguments: [query]
            )
            guard !Task.isCancelled,
                  activeSearchID == requestID,
                  self.runtime === runtime else { return }
            results = ModuleRuntimeDecoder.searchResults(
                from: response,
                baseURL: runtime.baseURL,
                maximumResults: runtime.maximumHomeResults
            )
            if results.isEmpty {
                lastSearchDiagnostics = [
                    "Kinetiq module diagnostics · Batch 05F",
                    "Source: \(ModulePlaybackDiagnostics.redact(source.title, limit: 80))",
                    "Phase: searchResults",
                    "Handler returned: \(ModulePlaybackDiagnostics.responseShape(response))",
                    "Decoded search results: 0",
                    "Query length: \(query.count) characters (text omitted)",
                    "Possible cause: no results or incompatible response format"
                ].joined(separator: "\n")
            }
        } catch {
            guard !Task.isCancelled,
                  activeSearchID == requestID,
                  self.runtime === runtime else { return }
            searchFailure = error.localizedDescription
            lastSearchDiagnostics = ModulePlaybackDiagnostics.simpleReport(
                source: source.title, phase: "searchResults", error: error
            )
        }
    }

}

// MARK: - Anime Details and Episodes

private enum ModuleEpisodeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unwatched = "Unwatched"
    case watched = "Watched"

    var id: String { rawValue }
}

@MainActor
struct ModuleAnimeDetailsView: View {

    let item: ModuleAnimeItem
    let runtime: SynthetiqModuleRuntime
    let sourceID: String
    let sourceName: String

    @StateObject private var animeCollection = ModuleAnimeCollectionStore.shared

    @Environment(\.dismiss) private var dismiss

    @State private var details: ModuleAnimeItem?
    @State private var episodes: [ModuleAnimeEpisode] = []
    @State private var episodeSearch = ""
    @State private var episodeFilter: ModuleEpisodeFilter = .all

    @State private var playbackSession: ModuleEpisodePlaybackSession?
    @State private var selectedPlaybackSession: ModuleEpisodePlaybackSession?

    @State private var isLoading = true
    @State private var isResolvingStream = false

    @State private var detailsFailure: String?
    @State private var detailsFailureDiagnostics: String?
    @State private var activeDetailsRequestID: UUID?
    @State private var errorMessage: String?
    @State private var lastPlaybackDiagnostics: String?
    @State private var lastPlaybackFailure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsHeader

                    if let lastPlaybackDiagnostics {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Last playback failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(lastPlaybackFailure ?? "The module could not resolve this episode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                UIPasteboard.general.string = lastPlaybackDiagnostics
                            } label: {
                                Label("Copy Diagnostics", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(KinetiqPalette.accent)
                            .accessibilityLabel("Copy the last failed playback diagnostics")
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }

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
            .fullScreenCover(item: $selectedPlaybackSession, onDismiss: {
                if let report = playbackSession?.playerFailureDiagnostics {
                    lastPlaybackDiagnostics = report
                    lastPlaybackFailure = playbackSession?.playerFailureReason
                }
            }) { session in
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
                Button("Copy Diagnostics") {
                    UIPasteboard.general.string = lastPlaybackDiagnostics
                        ?? "No playback diagnostic report is available."
                    errorMessage = nil
                }
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "The request failed.")
            }
        }
    }

    // MARK: Details Header

    private var continuation: ModuleEpisodeContinuation? {
        animeCollection.continuation(
            sourceID: sourceID, animeID: item.id, episodes: episodes
        )
    }

    private var watchedEpisodeCount: Int {
        episodes.filter { hasWatched($0) }.count
    }

    private var visibleEpisodes: [ModuleAnimeEpisode] {
        let query = episodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return episodes.filter { episode in
            let matchesSearch = query.isEmpty ||
                "Episode \(episode.number)".localizedCaseInsensitiveContains(query)
            let watched = hasWatched(episode)
            let matchesFilter = episodeFilter == .all ||
                (episodeFilter == .watched && watched) ||
                (episodeFilter == .unwatched && !watched)
            return matchesSearch && matchesFilter
        }
    }

    private func hasWatched(_ episode: ModuleAnimeEpisode) -> Bool {
        animeCollection.hasWatched(sourceID: sourceID, animeID: item.id, episode: episode)
    }

    private func progress(
        for episode: ModuleAnimeEpisode, language: String
    ) -> ModuleEpisodeProgress? {
        animeCollection.progress(
            sourceID: sourceID, animeID: item.id,
            episodeID: episode.id, language: language
        )
    }

    private var detailsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleAnimeArtworkView(url: details?.imageURL ?? item.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if let synopsis = details?.synopsis ?? item.synopsis,
               !synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Synopsis")
                        .font(.system(size: 16, weight: .bold))
                    Text(synopsis)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(details?.title ?? item.title)
                .font(.system(size: 23, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            if let continuation {
                Button {
                    Task {
                        await play(
                            episode: continuation.episode,
                            language: continuation.language
                        )
                    }
                } label: {
                    Label(
                        "\(continuation.isResume ? "Resume" : "Play") Episode \(continuation.episode.number) · \(continuation.language.uppercased())",
                        systemImage: "play.circle.fill"
                    )
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(KinetiqPalette.accent)
                .disabled(isResolvingStream || isLoading)
            } else if !episodes.isEmpty, watchedEpisodeCount == episodes.count {
                Label("All available episodes watched", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KinetiqPalette.accent)
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

                Text("\(watchedEpisodeCount) / \(episodes.count) watched")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !episodes.isEmpty {
                Picker("Episode filter", selection: $episodeFilter) {
                    ForEach(ModuleEpisodeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find episode number", text: $episodeSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !episodeSearch.isEmpty {
                        Button { episodeSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .accessibilityLabel("Clear episode search")
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))

                Text("Watched in either Sub or Dub. Resume positions are saved separately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isLoading && episodes.isEmpty {
                KinetiqAsyncStateView(
                    kind: .loading,
                    title: "Loading Episodes",
                    message: "Retrieving details and episodes from \(sourceName)."
                )
                .frame(minHeight: 150)
            } else if let detailsFailure {
                VStack(spacing: 10) {
                    KinetiqAsyncStateView(
                        kind: .failure,
                        title: "Episodes Unavailable",
                        message: detailsFailure,
                        actionTitle: "Retry Episodes"
                    ) {
                        Task { await loadDetailsAndEpisodes() }
                    }
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = detailsFailureDiagnostics
                            ?? "Episode diagnostics were unavailable."
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minHeight: 150)
            } else if episodes.isEmpty {
                VStack(spacing: 10) {
                    KinetiqAsyncStateView(
                        kind: .empty,
                        title: "No Episodes",
                        message: "This source did not return any episodes for this title."
                    )
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = [
                            "Kinetiq module diagnostics · Batch 05F",
                            "Source: \(ModulePlaybackDiagnostics.redact(sourceName, limit: 80))",
                            "Phase: extractEpisodes",
                            "Outcome: no episodes decoded",
                            "Note: source may be empty or its schema may be incompatible"
                        ].joined(separator: "\n")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minHeight: 150)
            } else if visibleEpisodes.isEmpty {
                ContentUnavailableView(
                    "No Matching Episodes",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try another number or episode filter.")
                )
                .frame(minHeight: 150)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visibleEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
    }

    private func episodeRow(
        _ episode: ModuleAnimeEpisode
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(
                    "Episode \(episode.number)",
                    systemImage: hasWatched(episode) ? "checkmark.circle.fill" : "play.circle"
                )
                .font(.system(size: 14, weight: .semibold))

                Spacer()

                if episode.subAvailable { episodePlayButton(episode, language: "sub") }
                if episode.dubAvailable { episodePlayButton(episode, language: "dub") }

                Menu {
                    if episode.subAvailable { watchedAction(episode, language: "sub") }
                    if episode.dubAvailable { watchedAction(episode, language: "dub") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19))
                        .frame(minWidth: 36, minHeight: 44)
                }
                .disabled(isResolvingStream || (!episode.subAvailable && !episode.dubAvailable))
                .accessibilityLabel("Manage Episode \(episode.number) progress")
            }

            if episode.subAvailable { episodeProgressLabel(episode, language: "sub") }
            if episode.dubAvailable { episodeProgressLabel(episode, language: "dub") }
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

    private func episodePlayButton(
        _ episode: ModuleAnimeEpisode, language: String
    ) -> some View {
        let saved = progress(for: episode, language: language)
        let action = saved?.isCompleted == true ? "Replay" :
            ((saved?.resumePosition ?? 0) > 0 ? "Resume" : "Play")
        return Button(language == "sub" ? "Sub" : "Dub") {
            Task { await play(episode: episode, language: language) }
        }
        .buttonStyle(.bordered)
        .tint(KinetiqPalette.accent)
        .disabled(isResolvingStream)
        .accessibilityLabel("\(action) Episode \(episode.number), \(language.uppercased())")
    }

    @ViewBuilder
    private func episodeProgressLabel(
        _ episode: ModuleAnimeEpisode, language: String
    ) -> some View {
        if let saved = progress(for: episode, language: language) {
            if saved.isCompleted {
                Label("\(language.uppercased()) · Watched", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(KinetiqPalette.accent)
            } else if saved.resumePosition > 0 {
                HStack(spacing: 10) {
                    Text("\(language.uppercased()) · \(Int(saved.fraction * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: saved.fraction)
                        .tint(KinetiqPalette.accent)
                }
            }
        }
    }

    private func watchedAction(
        _ episode: ModuleAnimeEpisode, language: String
    ) -> some View {
        let watched = progress(for: episode, language: language)?.isCompleted == true
        return Button {
            animeCollection.setWatched(
                !watched, sourceID: sourceID, sourceName: sourceName,
                anime: item, episode: episode, language: language
            )
        } label: {
            Label(
                "\(language.uppercased()): \(watched ? "Mark Unwatched (Reset Progress)" : "Mark Watched")",
                systemImage: watched ? "arrow.counterclockwise" : "checkmark.circle"
            )
        }
    }

    // MARK: Load Details and Episodes

    @MainActor
    private func loadDetailsAndEpisodes() async {
        let requestID = UUID()
        activeDetailsRequestID = requestID
        isLoading = true
        episodes = []
        detailsFailure = nil
        detailsFailureDiagnostics = nil

        defer {
            if activeDetailsRequestID == requestID {
                isLoading = false
            }
        }

        do {
            let detailsResponse = try await runtime.call(
                handler: "extractDetails",
                arguments: [item.href]
            )

            guard !Task.isCancelled,
                  activeDetailsRequestID == requestID else { return }

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

                    guard !Task.isCancelled,
                          activeDetailsRequestID == requestID else { return }
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

            guard !Task.isCancelled,
                  activeDetailsRequestID == requestID else { return }
            if let lastError {
                throw lastError
            }

            detailsFailure =
                "The source did not return a recognizable episode list."
            detailsFailureDiagnostics = [
                "Kinetiq module diagnostics · Batch 05F",
                "Source: \(ModulePlaybackDiagnostics.redact(sourceName, limit: 80))",
                "Phase: extractEpisodes",
                "Result: no decodable episodes after \(attempted.count) reference(s)",
                "Handler errors: none (returned empty/unrecognized lists)"
            ].joined(separator: "\n")
        } catch {
            guard !Task.isCancelled,
                  activeDetailsRequestID == requestID else { return }
            detailsFailure = error.localizedDescription
            detailsFailureDiagnostics = ModulePlaybackDiagnostics.simpleReport(
                source: sourceName, phase: "extractDetails / extractEpisodes", error: error
            )
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
        lastPlaybackDiagnostics = nil
        lastPlaybackFailure = nil
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
            // Record the selected episode only after stream resolution.
            // The native module player separately persists real play position.
            animeCollection.recordEpisode(
                sourceID: sourceID,
                sourceName: sourceName,
                anime: item,
                episode: episode,
                language: language
            )
            selectedPlaybackSession = session
        } else {
            lastPlaybackDiagnostics = session.diagnosticSummary
            lastPlaybackFailure = ModulePlaybackDiagnostics.redact(
                session.playbackError ?? "The episode stream could not be resolved."
            )
            errorMessage = session.playbackError
                ?? "The episode stream could not be resolved."
        }
    }
}


// MARK: - Batch 05D: Privacy-Safe Server Health History

/// Keeps small, expiring reliability samples for a module's video hosts.
/// Persisted keys are SHA-256 digests of module identity + host + playback
/// kind. URLs, paths, query tokens, cookies, headers, and stream titles are
/// NEVER persisted. This is only a ranking hint, not a network probe.
@MainActor
final class ModuleServerHealthStore {
    static let shared = ModuleServerHealthStore()

    private struct Sample: Codable {
        var successes = 0
        var failures = 0
        var lastSuccess: TimeInterval = 0
        var lastFailure: TimeInterval = 0
        var updatedAt: TimeInterval = 0
        var meanStartupSeconds: Double = 0
    }

    private let storageKey = "kinetiq.module.serverHealth.v1"
    private let retentionSeconds: TimeInterval = 14 * 24 * 60 * 60
    private let maximumRecords = 192
    private let defaults: UserDefaults
    private var samples: [String: Sample]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: Sample].self, from: data) {
            let cutoff = Date().timeIntervalSince1970 - retentionSeconds
            samples = stored.filter { key, sample in
                key.count == 64 && sample.updatedAt >= cutoff
            }
        } else {
            samples = [:]
        }
        prune()
    }

    private func identity(
        _ stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String
    ) -> String? {
        guard let host = stream.url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        let scope = ((sourceID?.isEmpty == false ? sourceID : nil) ?? sourceName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !scope.isEmpty else { return nil }
        let mediaKind = stream.isWebEmbed ? "embed" : "native"
        let raw = scope + "\u{1F}" + host + "\u{1F}" + mediaKind
        return SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sample(
        for stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Sample? {
        guard let key = identity(stream, sourceID: sourceID, sourceName: sourceName),
              let value = samples[key],
              now - value.updatedAt < retentionSeconds else { return nil }
        return value
    }

    /// Positive means playback has previously advanced; negative means
    /// the host recently exhausted its retries. Unknown stays neutral so
    /// fresh modules retain their source-provided order.
    func score(
        _ stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String
    ) -> Double {
        guard let value = sample(for: stream, sourceID: sourceID, sourceName: sourceName) else {
            return 0
        }
        let now = Date().timeIntervalSince1970
        let successAge = now - value.lastSuccess
        let failureAge = now - value.lastFailure
        var score = 0.0
        if value.successes > 0 && successAge < retentionSeconds {
            let freshness = successAge < 48 * 3_600 ? 1.0 : 0.55
            score += min(Double(value.successes), 4) * 2.25 * freshness
            if value.meanStartupSeconds > 0 && value.meanStartupSeconds < 8 {
                score += 0.35
            }
        }
        if value.failures > 0 && failureAge < retentionSeconds {
            let freshness = failureAge < 48 * 3_600 ? 1.0 : 0.35
            score -= min(Double(value.failures), 4) * 3.5 * freshness
        }
        // Most recent verified observation wins on mixed-history hosts.
        if value.lastSuccess > value.lastFailure { score += 1.5 }
        if value.lastFailure > value.lastSuccess { score -= 1.5 }
        return score
    }

    func ordered(
        _ choices: [ModuleResolvedStream],
        sourceID: String?,
        sourceName: String
    ) -> [ModuleResolvedStream] {
        let scored = choices.enumerated().map { index, stream in
            (index, stream, score(stream, sourceID: sourceID, sourceName: sourceName))
        }
        return scored.sorted { a, b in
            // A working native player is always preferred to a web embed.
            if a.1.isWebEmbed != b.1.isWebEmbed { return !a.1.isWebEmbed }
            if abs(a.2 - b.2) > 0.001 { return a.2 > b.2 }
            return a.0 < b.0
        }.map(\.1)
    }

    func nextUntried(
        from choices: [ModuleResolvedStream],
        excluding attempted: Set<UUID>,
        avoidingHost: String?,
        sourceID: String?,
        sourceName: String
    ) -> ModuleResolvedStream? {
        let remaining = ordered(choices.filter { !attempted.contains($0.id) },
                                sourceID: sourceID, sourceName: sourceName)
        // Preserve native-first behavior even when the next native variant
        // shares a host with the failed stream. WebKit is the last resort.
        let native = remaining.filter { !$0.isWebEmbed }
        let candidates = native.isEmpty ? remaining : native
        if let host = avoidingHost?.lowercased(),
           let independent = candidates.first(where: { $0.hostName.lowercased() != host }) {
            return independent
        }
        return candidates.first
    }

    func status(
        for stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String
    ) -> String {
        guard let value = sample(for: stream, sourceID: sourceID, sourceName: sourceName) else {
            return "Not tested"
        }
        if value.lastSuccess > value.lastFailure {
            return "Previously played successfully"
        }
        if value.failures > 0 {
            return "Recent playback failures"
        }
        return "Not tested"
    }

    func startupTimeout(
        for stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String
    ) -> Double {
        guard let value = sample(for: stream, sourceID: sourceID, sourceName: sourceName) else {
            return 24
        }
        if value.lastSuccess > value.lastFailure,
           value.meanStartupSeconds > 17 {
            // Known cold-start servers deserve a larger budget.
            return min(42, max(24, value.meanStartupSeconds * 1.7))
        }
        if value.lastFailure > value.lastSuccess && value.failures >= 2 {
            return 16
        }
        return 24
    }

    func recordSuccess(
        _ stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String,
        startupSeconds: Double
    ) {
        guard !stream.isWebEmbed,
              let key = identity(stream, sourceID: sourceID, sourceName: sourceName) else { return }
        let now = Date().timeIntervalSince1970
        var value = samples[key] ?? Sample()
        let latency = min(max(startupSeconds.isFinite ? startupSeconds : 0, 0), 120)
        value.meanStartupSeconds = value.meanStartupSeconds > 0
            ? value.meanStartupSeconds * 0.65 + latency * 0.35
            : latency
        value.successes = min(value.successes + 1, 20)
        value.lastSuccess = now
        value.updatedAt = now
        samples[key] = value
        persist()
    }

    func recordFailure(
        _ stream: ModuleResolvedStream,
        sourceID: String?,
        sourceName: String
    ) {
        guard !stream.isWebEmbed,
              let key = identity(stream, sourceID: sourceID, sourceName: sourceName) else { return }
        let now = Date().timeIntervalSince1970
        var value = samples[key] ?? Sample()
        value.failures = min(value.failures + 1, 20)
        value.lastFailure = now
        value.updatedAt = now
        samples[key] = value
        persist()
    }

    /// Explicit user action; does not affect installed modules or history.
    func resetAll() {
        samples.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func prune() {
        let cutoff = Date().timeIntervalSince1970 - retentionSeconds
        samples = samples.filter { $0.value.updatedAt >= cutoff }
        if samples.count > maximumRecords {
            let keep = samples.sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(maximumRecords)
            samples = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func persist() {
        prune()
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
