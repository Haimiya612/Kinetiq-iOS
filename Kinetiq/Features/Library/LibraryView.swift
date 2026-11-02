import SwiftUI
import AVKit
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Local Media

private struct LocalMedia: Identifiable {
    let url: URL

    var id: String {
        url.lastPathComponent
    }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Photo Transfer

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "\(UUID().uuidString).\(fileExtension)"
                )

            try FileManager.default.copyItem(
                at: received.file,
                to: temporaryURL
            )

            return PickedMovie(url: temporaryURL)
        }
    }
}

// MARK: - Library View

struct LibraryView: View {
    @State private var media: [LocalMedia] = []
    @State private var selectedMedia: LocalMedia?

    @State private var showingImporter = false
    @State private var showingSourcePicker = false
    @State private var showingPhotoPicker = false

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mediaDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("KinetiqMedia", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                if media.isEmpty {
                    emptyState
                } else {
                    mediaList
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSourcePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(
                                    colors: [
                                        KinetiqPalette.cyan,
                                        KinetiqPalette.violet
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel("Import media")
                }
            }
            .confirmationDialog(
                "Add to your library",
                isPresented: $showingSourcePicker,
                titleVisibility: .visible
            ) {
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose where you want to import videos from.")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    .movie,
                    .video,
                    .mpeg4Movie,
                    .quickTimeMovie
                ],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 20,
                matching: .videos,
                preferredItemEncoding: .compatible
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }

                Task {
                    await importPhotos(newItems)
                }
            }
            .sheet(item: $selectedMedia) { item in
                LocalVideoPlayerView(url: item.url)
            }
            .alert(
                "Import Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .onAppear {
                loadMedia()

                withAnimation(
                    reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.85)
                ) {
                    appeared = true
                }
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(KinetiqPalette.cyan.opacity(0.09))
                    .frame(width: 112, height: 112)

                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 43, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.cyan,
                                KinetiqPalette.violet
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Your library starts here.")
                    .font(.system(size: 23, weight: .bold, design: .rounded))

                Text("Bring your own media into Kinetiq.\nYour imported videos stay on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                showingSourcePicker = true
            } label: {
                Label("Import videos", systemImage: "plus")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.cyan,
                                KinetiqPalette.blue,
                                KinetiqPalette.violet
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
        }
        .padding(30)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: Media List

    private var mediaList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR COLLECTION")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(KinetiqPalette.cyan)

                        Text("\(media.count) videos")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                    }

                    Spacer()
                }
                .padding(.bottom, 8)

                ForEach(media) { item in
                    Button {
                        selectedMedia = item
                    } label: {
                        mediaCard(item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteMedia(item)
                        } label: {
                            Label("Remove from library", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    private func mediaCard(_ item: LocalMedia) -> some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(
                        LinearGradient(
                            colors: [
                                KinetiqPalette.cyan.opacity(0.2),
                                KinetiqPalette.violet.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(KinetiqPalette.cyan)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.url.pathExtension.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)

                Label("On this device", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 29))
                .foregroundStyle(KinetiqPalette.cyan)
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
    }

    // MARK: File Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importFiles(urls)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true
            )

            for sourceURL in urls {
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()

                defer {
                    if hasAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let filename = UUID().uuidString
                    + "."
                    + sourceURL.pathExtension

                let destinationURL = mediaDirectory
                    .appendingPathComponent(filename)

                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: destinationURL
                )
            }

            loadMedia()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Photo Library Import

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let movie = try await item.loadTransferable(
                    type: PickedMovie.self
                ) else {
                    continue
                }

                importFiles([movie.url])

                try? FileManager.default.removeItem(at: movie.url)

            } catch {
                errorMessage = error.localizedDescription
            }
        }

        selectedPhotoItems = []
    }

    // MARK: Storage

    private func loadMedia() {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true
            )

            let files = try FileManager.default.contentsOfDirectory(
                at: mediaDirectory,
                includingPropertiesForKeys: nil
            )

            media = files
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare(
                        $1.lastPathComponent
                    ) == .orderedAscending
                }
                .map { LocalMedia(url: $0) }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMedia(_ item: LocalMedia) {
        do {
            try FileManager.default.removeItem(at: item.url)
            loadMedia()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Video Player

private struct LocalVideoPlayerView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .background(.black)
                } else {
                    ProgressView("Preparing playback...")
                }
            }
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                guard player == nil else { return }

                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                newPlayer.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
}