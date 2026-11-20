import SwiftUI
import Foundation
import CoreFoundation
import UIKit

// MARK: - M04 SubStudio: independent, source-backed subtitle layers

/// The original selected subtitle track remains owned by AVFoundation or
/// ModuleExternalSubtitleController. These two supplemental timelines never
/// alter the native PiP handoff or the player's primary caption preference.
enum KinetiqSubStudioSlot: String, CaseIterable, Identifiable {
    case secondary = "Second subtitle"
    case tertiary = "Third subtitle"
    var id: String { rawValue }
}

@MainActor
final class KinetiqSubStudioController: ObservableObject {
    @Published private(set) var tracks: [ModuleRemoteSubtitleTrack] = []
    @Published private(set) var secondaryTrackID: String?
    @Published private(set) var tertiaryTrackID: String?
    @Published private(set) var secondaryText: String?
    @Published private(set) var tertiaryText: String?
    @Published private(set) var secondaryError: String?
    @Published private(set) var tertiaryError: String?
    @Published private(set) var isLoadingSecondary = false
    @Published private(set) var isLoadingTertiary = false
    @Published var timingOffset: Double {
        didSet {
            let safe = max(-10, min(10, timingOffset.isFinite ? timingOffset : 0))
            if safe != timingOffset { timingOffset = safe; return }
            defaults.set(safe, forKey: "kinetiq.substudio.extraOffset.m04.v1")
            refresh()
        }
    }

    private let defaults: UserDefaults
    private var secondaryTimeline: ModuleSubtitleTimeline?
    private var tertiaryTimeline: ModuleSubtitleTimeline?
    private var secondaryRequest: UUID?
    private var tertiaryRequest: UUID?
    private var secondaryTask: Task<Void, Never>?
    private var tertiaryTask: Task<Void, Never>?
    private var currentTime: Double = .nan

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: "kinetiq.substudio.extraOffset.m04.v1")
        timingOffset = saved.isFinite ? max(-10, min(10, saved)) : 0
    }

    func configure(tracks: [ModuleRemoteSubtitleTrack]) {
        stop()
        // The server decides what translations actually exist. Never carry a
        // timed track to a different stream or invent a matching language.
        self.tracks = tracks
    }

    func selectedTrack(for slot: KinetiqSubStudioSlot) -> ModuleRemoteSubtitleTrack? {
        let id = slot == .secondary ? secondaryTrackID : tertiaryTrackID
        return tracks.first { $0.id == id }
    }

    func select(_ track: ModuleRemoteSubtitleTrack?, for slot: KinetiqSubStudioSlot) {
        if let track {
            guard tracks.contains(where: { $0.id == track.id }) else { return }
            let otherID = slot == .secondary ? tertiaryTrackID : secondaryTrackID
            guard track.id != otherID else { return }
        }
        switch slot {
        case .secondary:
            secondaryTask?.cancel()
            secondaryTask = nil
            secondaryRequest = nil
            secondaryTimeline = nil
            secondaryText = nil
            secondaryError = nil
            secondaryTrackID = track?.id
            isLoadingSecondary = track != nil
        case .tertiary:
            tertiaryTask?.cancel()
            tertiaryTask = nil
            tertiaryRequest = nil
            tertiaryTimeline = nil
            tertiaryText = nil
            tertiaryError = nil
            tertiaryTrackID = track?.id
            isLoadingTertiary = track != nil
        }
        guard let track else { return }
        let token = UUID()
        switch slot {
        case .secondary: secondaryRequest = token
        case .tertiary: tertiaryRequest = token
        }
        let task = Task { @MainActor [weak self] in
            do {
                let timeline = try await ModuleSubtitleLoader.load(track)
                guard !Task.isCancelled, let self else { return }
                switch slot {
                case .secondary:
                    guard self.secondaryRequest == token else { return }
                    self.secondaryTimeline = timeline
                    self.isLoadingSecondary = false
                case .tertiary:
                    guard self.tertiaryRequest == token else { return }
                    self.tertiaryTimeline = timeline
                    self.isLoadingTertiary = false
                }
                self.refresh()
            } catch {
                guard !Task.isCancelled, let self else { return }
                let message = (error as? ModuleSubtitleError)?.errorDescription
                    ?? "This source subtitle track could not be loaded."
                switch slot {
                case .secondary:
                    guard self.secondaryRequest == token else { return }
                    self.isLoadingSecondary = false
                    self.secondaryError = message
                case .tertiary:
                    guard self.tertiaryRequest == token else { return }
                    self.isLoadingTertiary = false
                    self.tertiaryError = message
                }
            }
        }
        switch slot {
        case .secondary: secondaryTask = task
        case .tertiary: tertiaryTask = task
        }
    }

    func updatePlaybackTime(_ seconds: Double) {
        guard seconds != currentTime else { return }
        currentTime = seconds
        refresh()
    }

    private func refresh() {
        let time = currentTime + KinetiqSubtitleSettings.shared.sourceTimingOffset + timingOffset
        let second = secondaryTimeline?.text(at: time)
        let third = tertiaryTimeline?.text(at: time)
        if second != secondaryText { secondaryText = second }
        if third != tertiaryText { tertiaryText = third }
    }

    func transcript(for slot: KinetiqSubStudioSlot) -> String? {
        let timeline = slot == .secondary ? secondaryTimeline : tertiaryTimeline
        guard let timeline, !timeline.isEmpty else { return nil }
        return timeline.bridgeCues.map { cue in
            "[\(Self.timestamp(cue.startTime))] \(cue.text)"
        }.joined(separator: "\n")
    }

    func search(_ phrase: String, in slot: KinetiqSubStudioSlot) -> [ExternalSubtitleCue] {
        let query = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 120 else { return [] }
        let cues = (slot == .secondary ? secondaryTimeline : tertiaryTimeline)?.bridgeCues ?? []
        return Array(cues.lazy.filter { $0.text.localizedStandardContains(query) }.prefix(16))
    }

    /// This heuristic is local, inspectable and never described as a guarantee
    /// of translation accuracy or a provider quality rating.
    func readabilityPercentage(for slot: KinetiqSubStudioSlot) -> Int? {
        let cues = (slot == .secondary ? secondaryTimeline : tertiaryTimeline)?.bridgeCues ?? []
        guard !cues.isEmpty else { return nil }
        let readable = cues.filter { cue in
            let seconds = max(cue.endTime - cue.startTime, 0.1)
            let cps = Double(cue.text.count) / seconds
            return cps <= 24 && cue.text.components(separatedBy: "\n").count <= 4
        }.count
        return Int((Double(readable) / Double(cues.count) * 100).rounded())
    }

    func nearbyCue(after seconds: Double, direction: Int,
                   slot: KinetiqSubStudioSlot) -> ExternalSubtitleCue? {
        let cues = (slot == .secondary ? secondaryTimeline : tertiaryTimeline)?.bridgeCues ?? []
        return direction > 0 ? cues.first(where: { $0.startTime > seconds + 0.2 }) :
            cues.last(where: { $0.startTime < seconds - 0.2 })
    }

    private static func timestamp(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600,
                      (value % 3600) / 60, value % 60)
    }

    func stop() {
        secondaryTask?.cancel()
        tertiaryTask?.cancel()
        secondaryTask = nil
        tertiaryTask = nil
        secondaryRequest = nil
        tertiaryRequest = nil
        secondaryTimeline = nil
        tertiaryTimeline = nil
        secondaryText = nil
        tertiaryText = nil
        secondaryTrackID = nil
        tertiaryTrackID = nil
        secondaryError = nil
        tertiaryError = nil
        isLoadingSecondary = false
        isLoadingTertiary = false
        tracks = []
        currentTime = .nan
    }
}

enum KinetiqJapaneseReading {
    /// Apple language-aware token transcription is a best-effort reading, not
    /// a canonical pronunciation. In particular, names may need correction.
    static func romaji(for text: String) -> String? {
        guard !text.isEmpty, text.utf16.count < 2_000 else { return nil }
        let original = text as NSString
        let locale = CFLocaleCreate(kCFAllocatorDefault,
            CFLocaleIdentifier("ja_JP" as CFString))
        let options = kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription
        guard let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault,
            text as CFString, CFRange(location: 0, length: original.length), options, locale)
        else { return nil }
        var chunks: [String] = []
        var lastEnd = 0
        var didTranscribe = false
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location >= lastEnd, range.length > 0,
                  range.location + range.length <= original.length else { break }
            if range.location > lastEnd {
                chunks.append(original.substring(with: NSRange(location: lastEnd,
                    length: range.location - lastEnd)))
            }
            let word = original.substring(with: NSRange(location: range.location,
                length: range.length))
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer,
                kCFStringTokenizerAttributeLatinTranscription) as? String
            if let latin, !latin.isEmpty, latin != word {
                chunks.append(latin)
                didTranscribe = true
            } else {
                chunks.append(word)
            }
            lastEnd = range.location + range.length
        }
        if lastEnd < original.length {
            chunks.append(original.substring(from: lastEnd))
        }
        return didTranscribe ? chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}

@MainActor
struct KinetiqSubStudioCaptionStack: View {
    let primary: String?
    let primaryLanguage: String?
    @ObservedObject var studio: KinetiqSubStudioController
    @AppStorage("kinetiq.substudio.romaji.m04.v1") private var showRomaji = false
    @AppStorage("kinetiq.substudio.m05.softColors") private var softColors = true
    @AppStorage("kinetiq.substudio.m05.colorStrength") private var colorStrength = 0.78

    private var japaneseText: String? {
        if primaryLanguage?.lowercased().hasPrefix("ja") == true { return primary }
        if studio.selectedTrack(for: .secondary)?.language?.lowercased().hasPrefix("ja") == true {
            return studio.secondaryText
        }
        if studio.selectedTrack(for: .tertiary)?.language?.lowercased().hasPrefix("ja") == true {
            return studio.tertiaryText
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 7) {
            if let primary, !primary.isEmpty {
                KinetiqCaptionText(text: primary)
            }
            if let text = studio.secondaryText, !text.isEmpty {
                line(text, color: .yellow, label: studio.selectedTrack(for: .secondary)?.label)
            }
            if let text = studio.tertiaryText, !text.isEmpty {
                line(text, color: .cyan, label: studio.selectedTrack(for: .tertiary)?.label)
            }
            if showRomaji, let japaneseText,
               let reading = KinetiqJapaneseReading.romaji(for: japaneseText) {
                line(reading, color: .mint, label: "Romaji · approximate reading")
            }
        }
        .frame(maxWidth: 700)
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String, color: Color, label: String?) -> some View {
        let tint = softColors ? Color.white : color
        VStack(spacing: 2) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(color.opacity(softColors ? 0.65 : 0.88))
            }
            Text(verbatim: text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .foregroundStyle(tint.opacity(softColors ? 1 : max(0.5, colorStrength)))
                .shadow(color: .black, radius: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
struct KinetiqSubStudioControls: View {
    @ObservedObject var studio: KinetiqSubStudioController
    let primaryTrackID: String?
    let currentTime: Double
    let onSeek: (Double) -> Void
    @AppStorage("kinetiq.substudio.romaji.m04.v1") private var showRomaji = false
    @AppStorage("kinetiq.substudio.m05.softColors") private var softColors = true
    @AppStorage("kinetiq.substudio.m05.colorStrength") private var colorStrength = 0.78
    @State private var phraseQuery = ""
    @State private var pickingSlot: KinetiqSubStudioSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SUBSTUDIO · MULTI-LANGUAGE", systemImage: "captions.bubble.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(KinetiqPalette.cyan)
            Text("Add a second or third source-provided SRT/WebVTT track. No automatic translation or guessed timing.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.70))

            ForEach(KinetiqSubStudioSlot.allCases) { slot in
                HStack(spacing: 8) {
                    Text(slot.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { pickingSlot = slot } label: {
                        Label(studio.selectedTrack(for: slot)?.label ?? "Choose track",
                              systemImage: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(10)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(studio.tracks.isEmpty)
                }
                if slot == .secondary && studio.isLoadingSecondary ||
                   slot == .tertiary && studio.isLoadingTertiary {
                    ProgressView("Loading subtitle track…")
                        .font(.caption)
                }
                if let failure = slot == .secondary ? studio.secondaryError : studio.tertiaryError {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
                if let transcript = studio.transcript(for: slot) {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = transcript
                        } label: {
                            Label("Copy transcript", systemImage: "doc.on.doc")
                        }
                        Button {
                            if let cue = studio.nearbyCue(after: currentTime,
                                    direction: -1, slot: slot) { onSeek(cue.startTime) }
                        } label: {
                            Label("Previous line", systemImage: "backward.end")
                        }
                        Button {
                            if let cue = studio.nearbyCue(after: currentTime,
                                    direction: 1, slot: slot) { onSeek(cue.startTime) }
                        } label: {
                            Label("Next line", systemImage: "forward.end")
                        }
                    }
                    .font(.caption)
                    .tint(KinetiqPalette.cyan)
                    if let percent = studio.readabilityPercentage(for: slot) {
                        Text("Estimated readable cue timing: \(percent)% (24 characters/sec guideline; not translation accuracy)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
            }

            TextField("Find a subtitle phrase", text: $phraseQuery)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .textFieldStyle(.roundedBorder)
            if phraseQuery.count >= 2 {
                ForEach(KinetiqSubStudioSlot.allCases) { slot in
                    ForEach(studio.search(phraseQuery, in: slot)) { cue in
                        Button {
                            onSeek(cue.startTime)
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d:%02d", Int(cue.startTime) / 60,
                                            Int(cue.startTime) % 60))
                                    .font(.caption.monospacedDigit())
                                Text(cue.text).lineLimit(2)
                                Spacer()
                                Image(systemName: "play.circle")
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }

            Toggle("Romaji for Japanese speech", isOn: $showRomaji)
                .tint(KinetiqPalette.cyan)
                .foregroundStyle(.white)
            Text("Japanese readings are generated on-device when possible. Proper names and kanji readings may be imperfect; unavailable readings are never invented.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.63))

            Toggle("Soft subtitle colors", isOn: $softColors)
                .tint(KinetiqPalette.cyan)
                .foregroundStyle(.white)
            HStack {
                Text("Color intensity")
                Spacer()
                Text("\(Int(colorStrength * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white)
            Slider(value: $colorStrength, in: 0.5...1, step: 0.05)
                .tint(KinetiqPalette.cyan)
                .disabled(softColors)

            HStack {
                Text("Extra-track sync")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%+.2fs", studio.timingOffset))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.white)
            Slider(value: $studio.timingOffset, in: -10...10, step: 0.05)
                .tint(KinetiqPalette.cyan)
            Button("Reset extra-track timing") { studio.timingOffset = 0 }
                .font(.caption.weight(.medium))
                .tint(KinetiqPalette.cyan)
            Text("Multiple custom subtitle overlays display inside Kinetiq. iOS system PiP can only carry supported native tracks; supplemental overlays stay in the app.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .sheet(item: $pickingSlot) { slot in
            NavigationStack {
                List {
                    Button {
                        studio.select(nil, for: slot)
                        UISelectionFeedbackGenerator().selectionChanged()
                        pickingSlot = nil
                    } label: {
                        Label("Off", systemImage: "captions.bubble")
                    }
                    ForEach(studio.tracks.filter { track in
                        track.id != primaryTrackID &&
                        track.id != studio.selectedTrack(for: slot == .secondary
                            ? .tertiary : .secondary)?.id
                    }) { track in
                        Button {
                            studio.select(track, for: slot)
                            UISelectionFeedbackGenerator().selectionChanged()
                            pickingSlot = nil
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.label).font(.body.weight(.medium))
                                    Text(track.language?.uppercased() ?? "Unknown language")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if studio.selectedTrack(for: slot)?.id == track.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                .navigationTitle(slot.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { pickingSlot = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
