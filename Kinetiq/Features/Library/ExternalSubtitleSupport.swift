import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia

// MARK: - Subtitle Preferences

struct KinetiqSubtitleAppearance: Equatable {
    enum Size: String, CaseIterable { case small = "Small", standard = "Standard", large = "Large" }
    enum Ink: String, CaseIterable { case standard = "Default", yellow = "Yellow", cyan = "Cyan" }
    enum Background: String, CaseIterable { case standard = "Default", clear = "Clear", solid = "Solid" }

    var size: Size = .standard
    var ink: Ink = .standard
    var background: Background = .standard

    var points: CGFloat {
        switch size { case .small: 15; case .standard: 19; case .large: 25 }
    }

    private var rgb: (red: Double, green: Double, blue: Double) {
        switch ink {
        case .standard: (1, 1, 1)
        case .yellow: (1, 0.9, 0.25)
        case .cyan: (0.4, 0.95, 1)
        }
    }

    var textColor: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
    var opacity: Double {
        switch background { case .standard: 0.78; case .clear: 0; case .solid: 1 }
    }

    /// AVPlayer applies these rules to native WebVTT. Omit default attributes
    /// so unmodified fields retain their native presentation.
    var nativeRules: [AVTextStyleRule]? {
        var attributes: [String: Any] = [:]
        if size != .standard {
            attributes[kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight as String] = size == .small ? 3.5 : 6.5
        }
        if ink != .standard {
            attributes[kCMTextMarkupAttribute_ForegroundColorARGB as String] = [1.0, rgb.red, rgb.green, rgb.blue]
        }
        if background != .standard {
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = [opacity, 0.0, 0.0, 0.0]
        }
        guard !attributes.isEmpty, let rule = AVTextStyleRule(textMarkupAttributes: attributes) else { return nil }
        return [rule]
    }
}

/// Metadata for matching a track; signed URLs, headers and track IDs stay out
/// of the saved preference. Display names are only used for known names/tags.
struct KinetiqCaptionLanguage: Equatable {
    let tag: String?
    let name: String

    private static let aliases = [
        "english": "en", "eng": "en", "german": "de", "deutsch": "de", "deu": "de", "ger": "de",
        "japanese": "ja", "jpn": "ja", "日本語": "ja", "turkish": "tr", "türkçe": "tr", "tur": "tr",
        "bulgarian": "bg", "bul": "bg", "french": "fr", "français": "fr", "fra": "fr", "fre": "fr",
        "spanish": "es", "español": "es", "spa": "es", "portuguese": "pt", "por": "pt",
        "italian": "it", "ita": "it", "korean": "ko", "kor": "ko", "arabic": "ar", "ara": "ar",
        "chinese": "zh", "zho": "zh", "chi": "zh"
    ]

    init(tag: String?, name: String) {
        self.name = name
        self.tag = Self.normalized(tag) ?? Self.normalized(name)
    }

    init(_ option: AVMediaSelectionOption) {
        self.init(tag: Self.normalized(option.extendedLanguageTag) ?? Self.normalized(option.locale?.identifier), name: option.displayName)
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
        if let alias = aliases[raw] { return alias }
        guard raw.utf8.count <= 63 else { return nil }
        var parts = raw.components(separatedBy: "-")
        guard let first = parts.first, (2...3).contains(first.utf8.count),
              first.utf8.allSatisfy({ (97...122).contains($0) }), !["und", "mul", "zxx"].contains(first),
              parts.dropFirst().allSatisfy({ subtag in
                  (1...8).contains(subtag.utf8.count) && subtag.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) }
              }) else { return nil }
        parts[0] = aliases[first] ?? first
        return parts.joined(separator: "-")
    }

    static func rank(_ candidate: String?, for desired: String) -> Int? {
        guard let candidate else { return nil }
        if candidate == desired { return 0 }
        let lhs = candidate.split(separator: "-")
        let rhs = desired.split(separator: "-")
        guard lhs.first == rhs.first else { return nil }
        // Avoid substituting an explicitly different writing system.
        if let a = lhs.dropFirst().first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) }),
           let b = rhs.dropFirst().first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) }), a != b { return nil }
        return 1
    }
}

enum KinetiqCaptionTarget: Equatable {
    case automatic, off, embedded(Int), source(Int), manualSource

    func apply(to item: AVPlayerItem, group: AVMediaSelectionGroup?) -> AVMediaSelectionOption? {
        guard let group else { return nil }
        switch self {
        case .automatic: item.selectMediaOptionAutomatically(in: group)
        case .embedded(let index):
            if group.options.indices.contains(index) { item.select(group.options[index], in: group) }
        case .off, .source, .manualSource:
            if group.allowsEmptySelection { item.select(nil, in: group) }
        }
        return item.currentMediaSelection.selectedMediaOption(in: group)
    }
}

enum KinetiqCaptionChoice: Equatable {
    case settings, off, embedded(KinetiqCaptionLanguage), source

    func target(preference: String, embedded: [KinetiqCaptionLanguage], sources: [KinetiqCaptionLanguage] = []) -> KinetiqCaptionTarget {
        let desired: String
        let includeSources: Bool
        switch self {
        case .off: return .off
        case .source: return .manualSource
        case .embedded(let track):
            if let index = embedded.firstIndex(of: track) { return .embedded(index) }
            guard let tag = track.tag else { return .off }
            desired = tag
            includeSources = false
        case .settings:
            if preference == "automatic" { return .automatic }
            guard preference != "off", let tag = KinetiqCaptionLanguage.normalized(preference) else { return .off }
            desired = tag
            includeSources = true
        }
        // Exact tags win across both groups. Ties prefer native captions.
        for rank in 0...1 {
            if let index = embedded.firstIndex(where: { KinetiqCaptionLanguage.rank($0.tag, for: desired) == rank }) { return .embedded(index) }
            if includeSources, let index = sources.firstIndex(where: { KinetiqCaptionLanguage.rank($0.tag, for: desired) == rank }) { return .source(index) }
        }
        return .off
    }
}

@MainActor
final class KinetiqSubtitleSettings: ObservableObject {
    static let shared = KinetiqSubtitleSettings()
    static let commonLanguages = ["en", "de", "ja", "tr", "bg", "fr", "es", "pt", "it", "ko", "ar", "zh-hans", "zh-hant"]

    @Published private(set) var language: String
    @Published var appearance: KinetiqSubtitleAppearance {
        didSet {
            defaults.set(appearance.size.rawValue, forKey: Self.key + "size")
            defaults.set(appearance.ink.rawValue, forKey: Self.key + "ink")
            defaults.set(appearance.background.rawValue, forKey: Self.key + "background")
        }
    }
    private static let key = "kinetiq.subtitles.v1."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.key + "language")
        language = saved == "off" ? "off" : KinetiqCaptionLanguage.normalized(saved) ?? "automatic"
        appearance = KinetiqSubtitleAppearance(
            size: .init(rawValue: defaults.string(forKey: Self.key + "size") ?? "") ?? .standard,
            ink: .init(rawValue: defaults.string(forKey: Self.key + "ink") ?? "") ?? .standard,
            background: .init(rawValue: defaults.string(forKey: Self.key + "background") ?? "") ?? .standard
        )
    }

    @discardableResult
    func setLanguage(_ value: String) -> Bool {
        let tag: String
        if ["automatic", "off"].contains(value) { tag = value }
        else if let normalized = KinetiqCaptionLanguage.normalized(value) { tag = normalized }
        else { return false }
        language = tag
        defaults.set(tag, forKey: Self.key + "language")
        return true
    }

    static func title(for tag: String) -> String {
        switch tag {
        case "automatic": "Automatic"
        case "off": "Off"
        default: Locale.current.localizedString(forIdentifier: tag) ?? tag
        }
    }
}

@MainActor
struct KinetiqCaptionText: View {
    let text: String
    @ObservedObject private var settings = KinetiqSubtitleSettings.shared

    init(text: String) { self.text = text }

    var body: some View {
        let style = settings.appearance
        Text(verbatim: text)
            .font(.system(size: style.points, weight: .semibold, design: .rounded))
            .foregroundStyle(style.textColor)
            .multilineTextAlignment(.center)
            .lineLimit(8)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(Color.black.opacity(style.opacity), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Subtitle Cue

struct ExternalSubtitleCue: Identifiable, Equatable, Sendable {
    let id: Int
    let startTime: Double
    let endTime: Double
    let text: String

    func contains(_ time: Double) -> Bool {
        time >= startTime && time < endTime
    }
}

// MARK: - Subtitle Format

enum ExternalSubtitleFormat: String, Sendable {
    case srt
    case vtt

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "srt":
            self = .srt
        case "vtt":
            self = .vtt
        default:
            return nil
        }
    }
}

// MARK: - Subtitle Errors

enum ExternalSubtitleError: LocalizedError {
    case unsupportedFormat
    case unreadableFile
    case invalidEncoding
    case invalidTimestamp
    case noValidCues
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Only SRT and WebVTT subtitle files are supported."

        case .unreadableFile:
            return "Kinetiq could not read this subtitle file."

        case .invalidEncoding:
            return "The subtitle file uses an unsupported text encoding."

        case .invalidTimestamp:
            return "The subtitle file contains invalid timestamps."

        case .noValidCues:
            return "No valid subtitle entries were found in this file."

        case .storageUnavailable:
            return "Kinetiq could not access its subtitle storage."
        }
    }
}

// MARK: - Subtitle Parser

enum ExternalSubtitleParser {

    static func parse(
        data: Data,
        fileExtension: String
    ) throws -> [ExternalSubtitleCue] {

        guard let format = ExternalSubtitleFormat(
            fileExtension: fileExtension
        ) else {
            throw ExternalSubtitleError.unsupportedFormat
        }

        guard let decoded = decode(data) else {
            throw ExternalSubtitleError.invalidEncoding
        }

        let normalized = decoded
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized
            .components(separatedBy: "\n")
            .reduce(into: [[String]]()) { result, line in

                if line.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    if result.isEmpty || result.last?.isEmpty == false {
                        result.append([])
                    }
                } else {
                    if result.isEmpty {
                        result.append([])
                    }

                    result[result.count - 1].append(line)
                }
            }
            .filter { !$0.isEmpty }

        var cues: [ExternalSubtitleCue] = []

        for block in blocks {
            if let cue = parseBlock(
                block,
                format: format,
                id: cues.count
            ) {
                cues.append(cue)
            }
        }

        guard !cues.isEmpty else {
            throw ExternalSubtitleError.noValidCues
        }

        return cues.sorted {
            if $0.startTime == $1.startTime {
                return $0.id < $1.id
            }

            return $0.startTime < $1.startTime
        }
    }

    // MARK: Text Decoding

    private static func decode(_ data: Data) -> String? {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let string = String(data: data, encoding: .utf16) {
            return string
        }

        if let string = String(
            data: data,
            encoding: .windowsCP1252
        ) {
            return string
        }

        return nil
    }

    // MARK: Cue Parsing

    private static func parseBlock(
        _ lines: [String],
        format: ExternalSubtitleFormat,
        id: Int
    ) -> ExternalSubtitleCue? {

        guard !lines.isEmpty else {
            return nil
        }

        let firstLine = lines[0]
            .trimmingCharacters(in: .whitespaces)

        if format == .vtt {
            if firstLine.hasPrefix("WEBVTT")
                || firstLine.hasPrefix("NOTE")
                || firstLine == "STYLE"
                || firstLine == "REGION" {
                return nil
            }
        }

        guard let timestampIndex = lines.firstIndex(
            where: { $0.contains("-->") }
        ) else {
            return nil
        }

        let timestampLine = lines[timestampIndex]

        let components = timestampLine.components(
            separatedBy: "-->"
        )

        guard components.count == 2 else {
            return nil
        }

        let startString = components[0]
            .trimmingCharacters(in: .whitespaces)

        // WebVTT cue settings may follow the ending timestamp.
        let endString = components[1]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""

        guard let start = parseTimestamp(startString),
              let end = parseTimestamp(endString),
              end > start else {
            return nil
        }

        let rawText = lines
            .dropFirst(timestampIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            return nil
        }

        let cleanedText = cleanSubtitleText(rawText)

        guard !cleanedText.isEmpty else {
            return nil
        }

        return ExternalSubtitleCue(
            id: id,
            startTime: start,
            endTime: end,
            text: cleanedText
        )
    }

    // MARK: Timestamp Parsing

    private static func parseTimestamp(
        _ value: String
    ) -> Double? {

        let normalized = value
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")

        let components = normalized.split(
            separator: ":",
            omittingEmptySubsequences: false
        )

        guard components.count == 2
                || components.count == 3 else {
            return nil
        }

        let secondsComponents = components
            .last?
            .split(
                separator: ".",
                omittingEmptySubsequences: false
            )

        guard let secondsComponents,
              secondsComponents.count == 2,
              let seconds = Double(secondsComponents[0]),
              seconds >= 0 else {
            return nil
        }

        let fractionString = String(secondsComponents[1])

        guard fractionString.allSatisfy(\.isNumber),
              fractionString.count <= 3 else {
            return nil
        }

        let milliseconds = Double(
            fractionString.padding(
                toLength: 3,
                withPad: "0",
                startingAt: 0
            )
        ) ?? 0

        let timeComponents = components.dropLast()

        let hours: Double
        let minutes: Double

        if components.count == 3 {
            guard let parsedHours = Double(timeComponents[0]),
                  let parsedMinutes = Double(timeComponents[1]),
                  parsedHours >= 0,
                  parsedMinutes >= 0,
                  parsedMinutes < 60,
                  seconds < 60 else {
                return nil
            }

            hours = parsedHours
            minutes = parsedMinutes
        } else {
            guard let parsedMinutes = Double(timeComponents[0]),
                  parsedMinutes >= 0,
                  seconds < 60 else {
                return nil
            }

            hours = 0
            minutes = parsedMinutes
        }

        let result =
            (hours * 3600)
            + (minutes * 60)
            + seconds
            + (milliseconds / 1000)

        return result.isFinite ? result : nil
    }

    // MARK: Text Cleanup

    private static func cleanSubtitleText(
        _ text: String
    ) -> String {

        var result = text

        // Remove WebVTT and common subtitle formatting tags.
        result = result.replacingOccurrences(
            of: "<[^>]*>",
            with: "",
            options: .regularExpression
        )

        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " ")
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(
                of: entity,
                with: replacement
            )
        }

        return result.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}

// MARK: - Subtitle Track

struct ExternalSubtitleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
    let format: ExternalSubtitleFormat
}

// MARK: - Subtitle Controller

@MainActor
final class ExternalSubtitleController: ObservableObject {

    static let shared = ExternalSubtitleController()

    @Published private(set) var tracks: [ExternalSubtitleTrack] = []

    @Published private(set) var selectedTrackID: String?

    @Published private(set) var currentCue: ExternalSubtitleCue?

    @Published var errorMessage: String?

    private var currentMediaID: String?

    private var currentTime: Double = 0

    private var cueCache: [
        String: [ExternalSubtitleCue]
    ] = [:]

    private let fileManager = FileManager.default

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: Storage

    private var storageDirectory: URL? {
        guard let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return base.appendingPathComponent(
            "Kinetiq/ExternalSubtitles",
            isDirectory: true
        )
    }

    private func directory(
        for mediaID: String
    ) throws -> URL {

        guard let storageDirectory else {
            throw ExternalSubtitleError.storageUnavailable
        }

        let encodedID = Data(mediaID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")

        let folder = storageDirectory.appendingPathComponent(
            encodedID.isEmpty ? "default" : encodedID,
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        return folder
    }

    private func selectionKey(
        for mediaID: String
    ) -> String {
        "kinetiq.externalSubtitles.selected.\(mediaID)"
    }

    // MARK: Load Tracks

    func load(for mediaID: String) {

        currentMediaID = mediaID

        currentCue = nil
        currentTime = 0

        tracks = []
        cueCache = [:]

        do {
            let folder = try directory(for: mediaID)

            let files = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for file in files {
                guard let format = ExternalSubtitleFormat(
                    fileExtension: file.pathExtension
                ) else {
                    continue
                }

                guard let data = try? Data(contentsOf: file),
                      let cues = try? ExternalSubtitleParser.parse(
                        data: data,
                        fileExtension: format.rawValue
                      ) else {
                    continue
                }

                let track = ExternalSubtitleTrack(
                    id: file.lastPathComponent,
                    title: file.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(
                            of: #"^[0-9A-Fa-f-]{36}_"#,
                            with: "",
                            options: .regularExpression
                        ),
                    url: file,
                    format: format
                )

                tracks.append(track)
                cueCache[track.id] = cues
            }

            tracks.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title)
                    == .orderedAscending
            }

            let savedSelection = defaults.string(
                forKey: selectionKey(for: mediaID)
            )

            if let savedSelection,
               tracks.contains(where: { $0.id == savedSelection }) {
                selectedTrackID = savedSelection
            } else {
                selectedTrackID = nil
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        updateCue(at: currentTime)
    }

    // MARK: Import Subtitle

    @discardableResult
    func importSubtitle(
        from sourceURL: URL,
        for mediaID: String
    ) throws -> ExternalSubtitleTrack {

        guard let format = ExternalSubtitleFormat(
            fileExtension: sourceURL.pathExtension
        ) else {
            throw ExternalSubtitleError.unsupportedFormat
        }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data

        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw ExternalSubtitleError.unreadableFile
        }

        let cues = try ExternalSubtitleParser.parse(
            data: data,
            fileExtension: format.rawValue
        )

        guard !cues.isEmpty else {
            throw ExternalSubtitleError.noValidCues
        }

        let folder = try directory(for: mediaID)

        let originalName = sourceURL
            .deletingPathExtension()
            .lastPathComponent

        let filename =
            "\(UUID().uuidString)_\(originalName).\(format.rawValue)"

        let destinationURL = folder.appendingPathComponent(filename)

        do {
            try data.write(
                to: destinationURL,
                options: .atomic
            )
        } catch {
            throw ExternalSubtitleError.storageUnavailable
        }

        let track = ExternalSubtitleTrack(
            id: filename,
            title: originalName,
            url: destinationURL,
            format: format
        )

        if currentMediaID == mediaID {
            tracks.append(track)
            cueCache[track.id] = cues

            select(track)

            updateCue(at: currentTime)
        }

        return track
    }

    // MARK: Remove Subtitle

    func remove(_ track: ExternalSubtitleTrack) {

        try? fileManager.removeItem(at: track.url)

        cueCache.removeValue(forKey: track.id)

        tracks.removeAll {
            $0.id == track.id
        }

        if selectedTrackID == track.id {
            selectedTrackID = nil

            if let currentMediaID {
                defaults.removeObject(
                    forKey: selectionKey(for: currentMediaID)
                )
            }

            currentCue = nil
        }
    }

    // MARK: Selection

    func select(_ track: ExternalSubtitleTrack?) {

        selectedTrackID = track?.id

        if let currentMediaID {
            if let track {
                defaults.set(
                    track.id,
                    forKey: selectionKey(for: currentMediaID)
                )
            } else {
                defaults.removeObject(
                    forKey: selectionKey(for: currentMediaID)
                )
            }
        }

        updateCue(at: currentTime)
    }

    func turnOff() {
        select(nil)
    }

    // MARK: Playback Synchronization

    func updatePlaybackTime(_ seconds: Double) {

        guard seconds.isFinite, seconds >= 0 else {
            currentCue = nil
            return
        }

        currentTime = seconds

        updateCue(at: seconds)
    }

    private func updateCue(at seconds: Double) {

        guard let selectedTrackID,
              let cues = cueCache[selectedTrackID],
              !cues.isEmpty else {
            currentCue = nil
            return
        }

        // Binary search for the last cue that starts at or before
        // the current playback position.

        var lower = 0
        var upper = cues.count

        while lower < upper {
            let middle = (lower + upper) / 2

            if cues[middle].startTime <= seconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        var index = lower - 1

        while index >= 0 {
            let cue = cues[index]

            if cue.contains(seconds) {
                currentCue = cue
                return
            }

            if cue.endTime <= seconds {
                break
            }

            index -= 1
        }

        currentCue = nil
    }

    // MARK: Errors

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Uniform Type Identifiers

extension UTType {

    static let kinetiqSRT = UTType(
        filenameExtension: "srt",
        conformingTo: .plainText
    ) ?? .plainText

    static let kinetiqVTT = UTType(
        filenameExtension: "vtt",
        conformingTo: .plainText
    ) ?? .plainText
}

// MARK: - Subtitle Import Button

struct ExternalSubtitleImportButton: View {

    @ObservedObject var controller: ExternalSubtitleController

    let mediaID: String

    @State private var showingImporter = false

    var body: some View {

        Button {
            showingImporter = true
        } label: {
            Label(
                "Import subtitle file",
                systemImage: "plus.circle"
            )
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                .kinetiqSRT,
                .kinetiqVTT
            ],
            allowsMultipleSelection: false
        ) { result in

            switch result {
            case .success(let urls):

                guard let url = urls.first else {
                    return
                }

                do {
                    try controller.importSubtitle(
                        from: url,
                        for: mediaID
                    )
                } catch {
                    controller.errorMessage =
                        error.localizedDescription
                }

            case .failure(let error):

                controller.errorMessage =
                    error.localizedDescription
            }
        }
        .alert(
            "Subtitle Import",
            isPresented: Binding(
                get: {
                    controller.errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        controller.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                controller.clearError()
            }
        } message: {
            Text(
                controller.errorMessage
                    ?? "Something went wrong."
            )
        }
    }
}

// MARK: - Subtitle Overlay

struct ExternalSubtitleOverlay: View {

    let cue: ExternalSubtitleCue?

    var body: some View {

        Group {
            if let cue {

                Text(cue.text)
                    .font(
                        .system(
                            size: 19,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(.horizontal, 17)
                    .padding(.vertical, 10)
                    .background(
                        Color.black.opacity(0.78),
                        in: RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                        .stroke(
                            .white.opacity(0.12),
                            lineWidth: 1
                        )
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 105)
                    .transition(
                        .opacity.combined(
                            with: .move(edge: .bottom)
                        )
                    )

            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(
            .easeInOut(duration: 0.12),
            value: cue?.id
        )
    }
}

// MARK: - Remote Module Subtitles (Batch 03E)

enum ModuleSubtitleError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case tooLarge
    case unsupportedFormat
    case invalidSubtitles
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "This subtitle link is not a valid HTTPS URL."
        case .httpStatus(let status): return "The subtitle server returned HTTP \(status). Try another track or server."
        case .tooLarge: return "This subtitle file exceeds Kinetiq's size limit."
        case .unsupportedFormat: return "This subtitle format is not supported. Choose SRT or WebVTT."
        case .invalidSubtitles: return "The source did not return a readable SRT or WebVTT subtitle file."
        case .unavailable: return "Subtitles could not be loaded. Check your connection or choose another track."
        }
    }
}

enum ModuleSubtitleRequestPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        return parts.scheme?.lowercased() == "https" &&
            !(parts.host ?? "").isEmpty && parts.user == nil && parts.password == nil &&
            parts.fragment == nil && url.absoluteString.utf8.count <= 8_192
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() &&
        lhs.host?.lowercased() == rhs.host?.lowercased() &&
        (lhs.port ?? 443) == (rhs.port ?? 443)
    }

    static func cleanHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        let blocked: Set<String> = ["host", "content-length", "connection", "transfer-encoding",
                                    "proxy-authorization", "proxy-connection", "accept-encoding"]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        for key in headers.keys.sorted().prefix(40) {
            guard !key.isEmpty, key.count <= 128,
                  key.unicodeScalars.allSatisfy({ allowed.contains($0) }),
                  let value = headers[key], value.utf8.count <= 8_192,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !blocked.contains(key.lowercased()) else { continue }
            result[key.lowercased()] = value
        }
        return result
    }

    /// Build a fresh GET for redirects: never copy URLSession's possibly
    /// inherited credentials to a different origin or downgrade to HTTP.
    static func request(for track: ModuleRemoteSubtitleTrack, destination: URL? = nil) throws -> URLRequest {
        let url = destination ?? track.url
        guard isAllowed(track.url), isAllowed(url) else { throw ModuleSubtitleError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("text/vtt, application/x-subrip, text/plain, application/octet-stream", forHTTPHeaderField: "Accept")
        if sameOrigin(url, track.url) {
            let headers = cleanHeaders(track.headers)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            if headers["cookie"] == nil {
                let cookies = track.cookies.prefix(40).filter { cookie in
                    let domain = cookie.domain.lowercased()
                    let host = url.host?.lowercased() ?? ""
                    let matchesDomain = domain.hasPrefix(".")
                        ? (host == String(domain.dropFirst()) || host.hasSuffix(domain))
                        : host == domain
                    let path = cookie.path.isEmpty ? "/" : cookie.path
                    let requestPath = url.path.isEmpty ? "/" : url.path
                    let matchesPath = requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
                    let safe = !cookie.name.isEmpty && cookie.name.utf8.count <= 256 &&
                        cookie.value.utf8.count <= 8_192 &&
                        !cookie.name.contains("=") && !cookie.name.contains(";") &&
                        !cookie.value.contains(";") &&
                        !(cookie.name + cookie.value).unicodeScalars.contains(where: {
                            CharacterSet.controlCharacters.contains($0)
                        })
                    return matchesDomain && matchesPath && safe
                }
                if !cookies.isEmpty {
                    request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
                }
            }
        }
        return request
    }
}

private final class ModuleSubtitleRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let track: ModuleRemoteSubtitleTrack

    init(track: ModuleRemoteSubtitleTrack) { self.track = track }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url else { completionHandler(nil); return }
        completionHandler(try? ModuleSubtitleRequestPolicy.request(for: track, destination: url))
    }
}

struct ModuleSubtitleTimeline: Sendable {
    private let cues: [ExternalSubtitleCue]
    private let maximumEndTimes: [Double]

    var isEmpty: Bool { cues.isEmpty }

    init(cues: [ExternalSubtitleCue]) {
        self.cues = cues.filter {
            $0.startTime.isFinite && $0.endTime.isFinite &&
            $0.startTime >= 0 && $0.endTime > $0.startTime && !$0.text.isEmpty
        }.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        var ends: [Double] = []
        var maximum: Double = 0
        for cue in self.cues {
            maximum = max(maximum, cue.endTime)
            ends.append(maximum)
        }
        maximumEndTimes = ends
    }

    func text(at seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].startTime <= seconds { lower = middle + 1 }
            else { upper = middle }
        }
        var index = lower - 1
        var active: [String] = []
        // Prefix maxima retain long overlapping cues even when a later,
        // shorter cue has expired. Recompute on every seek, including backwards.
        while index >= 0 && maximumEndTimes[index] > seconds && active.count < 8 {
            if cues[index].contains(seconds) { active.append(String(cues[index].text.prefix(2_000))) }
            index -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }
}

enum ModuleSubtitleLoader {
    static let maximumBytes = 2 * 1_024 * 1_024
    static let maximumCues = 20_000

    static func load(_ track: ModuleRemoteSubtitleTrack) async throws -> ModuleSubtitleTimeline {
        let request = try ModuleSubtitleRequestPolicy.request(for: track)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        let delegate = ModuleSubtitleRedirectDelegate(track: track)
        defer { session.invalidateAndCancel() }

        let (data, contentType): (Data, String?) = try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse,
                  let url = http.url, ModuleSubtitleRequestPolicy.isAllowed(url) else {
                throw ModuleSubtitleError.invalidURL
            }
            guard (200...299).contains(http.statusCode) else { throw ModuleSubtitleError.httpStatus(http.statusCode) }
            guard http.expectedContentLength <= Int64(maximumBytes) else { throw ModuleSubtitleError.tooLarge }
            var data = Data()
            data.reserveCapacity(min(maximumBytes, max(0, Int(http.expectedContentLength))))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw ModuleSubtitleError.tooLarge }
                data.append(byte)
            }
            return (data, http.mimeType)
        } onCancel: {
            session.invalidateAndCancel()
        }

        let parsing = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let timeline = try parse(data: data, format: track.format, contentType: contentType)
            try Task.checkCancellation()
            return timeline
        }
        return try await withTaskCancellationHandler {
            try await parsing.value
        } onCancel: {
            parsing.cancel()
        }
    }

    static func parse(data: Data, format: ExternalSubtitleFormat?, contentType: String?) throws -> ModuleSubtitleTimeline {
        guard data.count <= maximumBytes else { throw ModuleSubtitleError.tooLarge }
        guard !data.isEmpty else { throw ModuleSubtitleError.invalidSubtitles }
        let type = contentType?.lowercased() ?? ""
        if type.contains("html") || type.contains("json") || type.contains("mpegurl") || type.contains("ttml") {
            throw ModuleSubtitleError.unsupportedFormat
        }
        let prefix = String(decoding: data.prefix(512), as: UTF8.self)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = format ?? ModuleRemoteSubtitleDecoder.format(type) ?? (prefix.hasPrefix("WEBVTT") ? .vtt : .srt)
        do {
            let cues = try ExternalSubtitleParser.parse(data: data, fileExtension: selected.rawValue)
            guard cues.count <= maximumCues else { throw ModuleSubtitleError.tooLarge }
            let timeline = ModuleSubtitleTimeline(cues: cues)
            guard !timeline.isEmpty else { throw ModuleSubtitleError.invalidSubtitles }
            return timeline
        } catch let error as ModuleSubtitleError {
            throw error
        } catch {
            throw ModuleSubtitleError.invalidSubtitles
        }
    }
}

@MainActor
final class ModuleExternalSubtitleController: ObservableObject {
    typealias Loader = @Sendable (ModuleRemoteSubtitleTrack) async throws -> ModuleSubtitleTimeline

    @Published private(set) var tracks: [ModuleRemoteSubtitleTrack] = []
    @Published private(set) var selectedTrackID: String?
    @Published private(set) var currentText: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: Loader
    private var loadTask: Task<Void, Never>?
    private var requestID: UUID?
    private var timeline: ModuleSubtitleTimeline?
    private var currentTime: Double = 0
    private var preference: (id: String, language: String?, label: String)?

    var isRequested: Bool { preference != nil || selectedTrackID != nil }

    init(loader: @escaping Loader = { try await ModuleSubtitleLoader.load($0) }) {
        self.loader = loader
    }

    func configure(tracks: [ModuleRemoteSubtitleTrack]) {
        cancelLoad()
        self.tracks = tracks
        currentTime = .nan
        restoreManualSelection()
    }

    func restoreManualSelection() {
        guard selectedTrackID == nil, let preference else { return }
        let matching = tracks.first { $0.id == preference.id } ?? tracks.first { track in
            if let language = preference.language {
                return track.language == language ||
                    (track.language == nil && track.label.caseInsensitiveCompare(preference.label) == .orderedSame)
            }
            return track.label.caseInsensitiveCompare(preference.label) == .orderedSame
        }
        if let matching { select(matching) }
        else { errorMessage = "Your selected subtitle track is unavailable on this stream. Choose another track or Off." }
    }

    func select(_ track: ModuleRemoteSubtitleTrack, rememberForSession: Bool = true) {
        guard tracks.contains(where: { $0.id == track.id }) else { return }
        cancelLoad()
        preference = rememberForSession ? (track.id, track.language, track.label) : nil
        selectedTrackID = track.id
        let identity = UUID()
        requestID = identity
        isLoading = true
        let loader = self.loader
        loadTask = Task { [weak self] in
            do {
                let loaded = try await loader(track)
                guard !Task.isCancelled, let self,
                      self.requestID == identity else { return }
                self.timeline = loaded
                self.isLoading = false
                self.updatePlaybackTime(self.currentTime)
            } catch {
                guard !Task.isCancelled, let self,
                      self.requestID == identity else { return }
                self.isLoading = false
                self.errorMessage = (error as? ModuleSubtitleError)?.errorDescription
                    ?? ModuleSubtitleError.unavailable.errorDescription
            }
        }
    }

    func turnOff() {
        preference = nil
        cancelLoad()
    }

    func retry() {
        guard let track = tracks.first(where: { $0.id == selectedTrackID }) else { return }
        select(track, rememberForSession: preference != nil)
    }

    func suspendForRequiredEmbeddedTrack() {
        cancelLoad()
        errorMessage = "This stream requires its embedded subtitle track."
    }

    func updatePlaybackTime(_ seconds: Double) {
        currentTime = seconds
        let next = timeline?.text(at: seconds)
        if currentText != next { currentText = next }
    }

    func stop() {
        turnOff()
        tracks = []
        currentTime = 0
    }

    private func cancelLoad() {
        requestID = nil
        loadTask?.cancel()
        loadTask = nil
        timeline = nil
        currentText = nil
        selectedTrackID = nil
        errorMessage = nil
        isLoading = false
    }
}
