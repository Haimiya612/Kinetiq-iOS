import SwiftUI
import Foundation
import UniformTypeIdentifiers

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
