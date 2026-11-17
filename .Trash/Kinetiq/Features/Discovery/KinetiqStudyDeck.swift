import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum KinetiqStudyGrade: String, CaseIterable, Identifiable {
    case again = "Again"
    case hard = "Hard"
    case good = "Good"
    case easy = "Easy"

    var id: String { rawValue }
}

/// A learning card created by the viewer, not an automatically translated or
/// copyright-scraped subtitle. The optional scene anchor has no media URL.
struct KinetiqStudyCard: Codable, Identifiable, Equatable {
    let id: UUID
    let series: String
    let phrase: String
    let meaning: String
    let context: String
    let anchor: KinetiqSceneAnchor?
    let createdAt: Date
    var dueAt: Date
    var reviewCount: Int
    var intervalDays: Int

    init(series: String, phrase: String, meaning: String, context: String,
         anchor: KinetiqSceneAnchor?, now: Date = Date()) {
        id = UUID()
        self.series = String(series.prefix(160))
        self.phrase = String(phrase.prefix(280))
        self.meaning = String(meaning.prefix(450))
        self.context = String(context.prefix(450))
        self.anchor = anchor?.isValid == true ? anchor : nil
        createdAt = now
        dueAt = now
        reviewCount = 0
        intervalDays = 0
    }

    var isValid: Bool {
        !series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        series.count <= 160 && phrase.count <= 280 && meaning.count <= 450 &&
        context.count <= 450 && reviewCount >= 0 && reviewCount <= 10_000 &&
        intervalDays >= 0 && intervalDays <= 365 &&
        (anchor == nil || anchor?.isValid == true)
    }
}

/// Lightweight deterministic spaced repetition that works entirely offline.
/// A poor grade reschedules in 10 minutes; successful grades extend intervals.
enum KinetiqStudyScheduler {
    static func reviewed(_ card: KinetiqStudyCard, grade: KinetiqStudyGrade,
                         at date: Date) -> KinetiqStudyCard {
        var updated = card
        updated.reviewCount = min(10_000, card.reviewCount + 1)
        switch grade {
        case .again:
            updated.intervalDays = 0
            updated.dueAt = date.addingTimeInterval(600)
        case .hard:
            updated.intervalDays = max(1, min(365, card.intervalDays == 0 ? 1 :
                Int((Double(card.intervalDays) * 1.2).rounded(.up))))
            updated.dueAt = date.addingTimeInterval(Double(updated.intervalDays) * 86_400)
        case .good:
            updated.intervalDays = max(1, min(365, card.intervalDays == 0 ? 1 :
                Int((Double(card.intervalDays) * 2.3).rounded(.up))))
            updated.dueAt = date.addingTimeInterval(Double(updated.intervalDays) * 86_400)
        case .easy:
            updated.intervalDays = max(3, min(365, card.intervalDays == 0 ? 3 :
                Int((Double(card.intervalDays) * 3.1).rounded(.up))))
            updated.dueAt = date.addingTimeInterval(Double(updated.intervalDays) * 86_400)
        }
        return updated
    }
}

enum KinetiqStudyCSV {
    static func escaped(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prevent spreadsheet formula injection on any user-entered text.
        let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + cleaned : cleaned
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func export(_ cards: [KinetiqStudyCard]) -> String {
        let heading = "Series,Phrase,Meaning,Context,Episode,Time Seconds,Due Date,Reviews"
        let lines = cards.map { card -> String in
            let columns = [card.series, card.phrase, card.meaning, card.context,
                           card.anchor?.episodeNumber ?? "",
                           card.anchor.map { String(Int($0.seconds)) } ?? "",
                           ISO8601DateFormatter().string(from: card.dueAt),
                           String(card.reviewCount)]
            return columns.map(escaped).joined(separator: ",")
        }
        return ([heading] + lines).joined(separator: "\r\n") + "\r\n"
    }
}

struct KinetiqStudyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var csv: String

    init(csv: String) { self.csv = csv }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= 3_000_000, let decoded = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        csv = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}

@MainActor
final class KinetiqStudyStore: ObservableObject {
    static let shared = KinetiqStudyStore()
    @Published private(set) var cards: [KinetiqStudyCard] = []

    private let defaults: UserDefaults
    private let key = "kinetiq.study.cards.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: key), bytes.count <= 2_000_000,
           let restored = try? JSONDecoder().decode([KinetiqStudyCard].self, from: bytes) {
            cards = Array(restored.filter(\.isValid).prefix(1_000))
        }
    }

    func add(series: String, phrase: String, meaning: String,
             context: String, anchor: KinetiqSceneAnchor?) {
        let newCard = KinetiqStudyCard(
            series: series.trimmingCharacters(in: .whitespacesAndNewlines),
            phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines),
            meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
            context: context.trimmingCharacters(in: .whitespacesAndNewlines),
            anchor: anchor
        )
        guard newCard.isValid else { return }
        // Protect manually written translations from accidental duplicate taps.
        guard !cards.contains(where: {
            $0.series == newCard.series && $0.phrase == newCard.phrase &&
            $0.anchor?.episodeID == newCard.anchor?.episodeID &&
            abs(($0.anchor?.seconds ?? 0) - (newCard.anchor?.seconds ?? 0)) < 1
        }) else { return }
        cards.insert(newCard, at: 0)
        if cards.count > 1_000 { cards.removeLast(cards.count - 1_000) }
        save()
    }

    func review(id: UUID, grade: KinetiqStudyGrade, at date: Date = Date()) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index] = KinetiqStudyScheduler.reviewed(cards[index], grade: grade, at: date)
        save()
    }

    func remove(id: UUID) {
        cards.removeAll { $0.id == id }
        save()
    }

    func due(at date: Date = Date()) -> [KinetiqStudyCard] {
        cards.filter { $0.dueAt <= date }.sorted { $0.dueAt < $1.dueAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cards) { defaults.set(data, forKey: key) }
    }
}

@MainActor
struct KinetiqStudyDeckView: View {
    let initialAnchor: KinetiqSceneAnchor?
    let seriesTitle: String
    let onSeek: ((Double) -> Void)?

    @StateObject private var store = KinetiqStudyStore.shared
    @State private var series = ""
    @State private var phrase = ""
    @State private var meaning = ""
    @State private var context = ""
    @State private var showAnswer = false
    @State private var exporting = false
    @State private var exportDocument: KinetiqStudyDocument?
    @State private var notice: String?

    private var dueCards: [KinetiqStudyCard] { store.due() }

    init(initialAnchor: KinetiqSceneAnchor? = nil, seriesTitle: String = "",
         onSeek: ((Double) -> Void)? = nil) {
        self.initialAnchor = initialAnchor
        self.seriesTitle = seriesTitle
        self.onSeek = onSeek
    }

    var body: some View {
        List {
            Section {
                Label("Offline Japanese Study Deck", systemImage: "character.book.closed.fill")
                    .font(.headline)
                Text("Make your own vocabulary cards from a scene. Kinetiq remembers the timecode without recording video, scanning subtitles or sending your notes to AI services.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Cards", value: "\(store.cards.count)")
                LabeledContent("Due now", value: "\(dueCards.count)")
            }

            Section("Add a flashcard") {
                TextField("Anime or film", text: $series)
                    .textInputAutocapitalization(.words)
                TextField("Japanese phrase or word", text: $phrase, axis: .vertical)
                    .lineLimit(1...4)
                TextField("Meaning / translation", text: $meaning, axis: .vertical)
                    .lineLimit(1...4)
                TextField("Context (optional)", text: $context, axis: .vertical)
                    .lineLimit(1...3)
                if let anchor = initialAnchor {
                    Label("Linked to episode \(anchor.episodeNumber) at \(Int(anchor.seconds)) seconds", systemImage: "bookmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save flashcard", systemImage: "plus.circle.fill") {
                    let count = store.cards.count
                    store.add(series: series, phrase: phrase, meaning: meaning,
                              context: context, anchor: initialAnchor)
                    notice = store.cards.count > count ? "Card saved locally." :
                        "Card was already saved or has missing fields."
                    if store.cards.count > count { phrase = ""; meaning = ""; context = "" }
                }
                .disabled(series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Spaced repetition") {
                if let card = dueCards.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(card.series).font(.caption).foregroundStyle(.secondary)
                        Text(card.phrase).font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        if showAnswer {
                            Divider()
                            Text(card.meaning).font(.body)
                                .textSelection(.enabled)
                            if !card.context.isEmpty {
                                Text(card.context).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 5) {
                                ForEach(KinetiqStudyGrade.allCases) { grade in
                                    Button(grade.rawValue) {
                                        store.review(id: card.id, grade: grade)
                                        showAnswer = false
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        } else {
                            Button("Reveal answer", systemImage: "eye") { showAnswer = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    Label("You're caught up. Future cards appear on their due dates.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Saved cards") {
                if store.cards.isEmpty {
                    Text("No cards yet. While watching, open More → Study Deck to attach a scene timestamp.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.cards.prefix(100)) { card in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(card.phrase).font(.headline).textSelection(.enabled)
                        Text(card.meaning).font(.subheadline).textSelection(.enabled)
                        Text("\(card.series) · due \(card.dueAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let anchor = card.anchor {
                            HStack {
                                Text("Episode \(anchor.episodeNumber) · \(Int(anchor.seconds))s")
                                    .font(.caption)
                                if let onSeek, let active = initialAnchor,
                                   active.mediaID == anchor.mediaID &&
                                   active.episodeID == anchor.episodeID &&
                                   active.language == anchor.language {
                                    Button("Jump to scene", systemImage: "arrow.turn.down.right") {
                                        onSeek(anchor.seconds)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.remove(id: card.id) }
                    }
                }
                if store.cards.count > 100 {
                    Text("Showing newest 100 of \(store.cards.count) cards. All cards remain in review scheduling and CSV export.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Portability") {
                Button("Export study cards as CSV", systemImage: "square.and.arrow.up") {
                    exportDocument = KinetiqStudyDocument(csv: KinetiqStudyCSV.export(store.cards))
                    exporting = true
                }
                .disabled(store.cards.isEmpty)
                Text("Export contains your phrases, translations and timestamps, never stream links or Discord credentials. Share it privately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Study Deck")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if series.isEmpty { series = seriesTitle } }
        .fileExporter(isPresented: $exporting, document: exportDocument,
            contentType: .commaSeparatedText, defaultFilename: "Kinetiq-Study-Deck") { result in
                if case .failure = result { notice = "The CSV could not be exported." }
            }
    }
}
