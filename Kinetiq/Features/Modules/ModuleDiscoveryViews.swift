import SwiftUI
import UIKit

// MARK: - Real module discovery UI (Batch 05J)
// Source-provided sections only; suggestions and saved collections remain
// available in ModuleBrowserView as independent fallbacks.

@MainActor
struct KinetiqSourceDiscoveryView: View {
    let runtime: SynthetiqModuleRuntime
    let sourceID: String
    let sourceName: String

    @State private var shelves: [ModuleDiscoveryShelf] = []
    @State private var isLoading = true
    @State private var failure: String?
    @State private var activeRequest: UUID?
    @State private var selectedItem: ModuleAnimeItem?
    @State private var selectedFeed: ModuleDiscoveryFeedSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading \(sourceName) Home…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !shelves.isEmpty {
                HStack {
                    Label("From \(sourceName)", systemImage: "sparkles.tv")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh source Home")
                }
                ForEach(shelves) { shelf in
                    shelfView(shelf)
                }
            } else if let failure, !failure.isEmpty {
                // Optional discovery must never turn a usable Search page into
                // a source failure (older modules lack the handler entirely).
                VStack(alignment: .leading, spacing: 5) {
                    Text("Source Home is temporarily unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button("Retry source Home") {
                        Task { await reload() }
                    }
                    .font(.caption)
                }
            }
        }
        .task { await reload() }
        .onDisappear { activeRequest = nil }
        .sheet(item: $selectedItem) { item in
            ModuleAnimeDetailsView(item: item, runtime: runtime,
                                   sourceID: sourceID, sourceName: sourceName)
        }
        .sheet(item: $selectedFeed) { selection in
            KinetiqSourceDiscoveryFeedView(
                runtime: runtime, selection: selection,
                sourceID: sourceID, sourceName: sourceName
            )
        }
    }

    private func shelfView(_ shelf: ModuleDiscoveryShelf) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                Spacer()
                if let feedID = shelf.feedID {
                    Button("See all") {
                        selectedFeed = ModuleDiscoveryFeedSelection(
                            id: feedID, title: shelf.title
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.cards) { card in
                        KinetiqDiscoveryPoster(card: card, width: 128) {
                            selectedItem = card.anime
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func reload() async {
        let requestID = UUID()
        activeRequest = requestID
        isLoading = true
        failure = nil
        defer {
            if activeRequest == requestID { isLoading = false }
        }
        do {
            let response = try await runtime.call(
                handler: "discoveryHome", arguments: []
            )
            guard !Task.isCancelled, activeRequest == requestID else { return }
            shelves = ModuleDiscoveryDecoder.home(
                from: response, baseURL: runtime.baseURL
            )
            if shelves.isEmpty { failure = "empty" }
        } catch {
            guard !Task.isCancelled, activeRequest == requestID else { return }
            shelves = []
            failure = ModulePlaybackDiagnostics.redact(error.localizedDescription)
        }
    }
}

struct ModuleDiscoveryFeedSelection: Identifiable {
    let id: String
    let title: String
}

@MainActor
private struct KinetiqSourceDiscoveryFeedView: View {
    @Environment(\.dismiss) private var dismiss

    let runtime: SynthetiqModuleRuntime
    let selection: ModuleDiscoveryFeedSelection
    let sourceID: String
    let sourceName: String

    @State private var cards: [ModuleDiscoveryCard] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedItem: ModuleAnimeItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 20) {
                    ForEach(cards) { card in
                        KinetiqDiscoveryPoster(card: card, width: nil) {
                            selectedItem = card.anime
                        }
                    }
                }
                .padding(16)

                if loading { ProgressView().padding(20) }
                if let errorText {
                    VStack(spacing: 8) {
                        Text("Could not load the next page")
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadNextPage() } }
                    }
                    .padding(20)
                }
                if hasMore && !loading && errorText == nil {
                    Button("Load more") { Task { await loadNextPage() } }
                        .buttonStyle(.borderedProminent)
                        .padding(20)
                }
                if !hasMore && cards.isEmpty && !loading {
                    ContentUnavailableView("No titles in this feed",
                                           systemImage: "rectangle.stack")
                }
            }
            .navigationTitle(selection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadNextPage() }
            .sheet(item: $selectedItem) { item in
                ModuleAnimeDetailsView(
                    item: item, runtime: runtime,
                    sourceID: sourceID, sourceName: sourceName
                )
            }
        }
    }

    private func loadNextPage() async {
        guard hasMore, !loading, page < 20 else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        let requestedPage = page + 1
        do {
            let response = try await runtime.call(
                handler: "discoveryFeed",
                arguments: [selection.id, requestedPage]
            )
            guard !Task.isCancelled else { return }
            let result = ModuleDiscoveryDecoder.feed(
                from: response, baseURL: runtime.baseURL,
                requestedPage: requestedPage
            )
            var seen = Set(cards.map(\.id))
            cards.append(contentsOf: result.cards.filter { seen.insert($0.id).inserted })
            page = requestedPage
            hasMore = result.hasMore && page < 20
        } catch {
            guard !Task.isCancelled else { return }
            errorText = ModulePlaybackDiagnostics.redact(error.localizedDescription)
        }
    }
}

private struct KinetiqDiscoveryPoster: View {
    let card: ModuleDiscoveryCard
    let width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    ModuleAnimeArtworkView(url: card.anime.imageURL)
                        .frame(height: 177)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if let badge = card.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.72),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .padding(6)
                    }
                }
                Text(card.anime.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
                if let year = card.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(card.anime.title)")
    }
}
