import SwiftUI
import AVFoundation
import AVKit
import UIKit

enum KinetiqQualityPreset: String, CaseIterable, Identifiable {
    case highest = "HEVC · Quality"
    case compact = "HEVC · 1080p"
    var id: String { rawValue }
    var exportPreset: String {
        switch self {
        case .highest: AVAssetExportPresetHEVCHighestQuality
        case .compact: AVAssetExportPresetHEVC1920x1080
        }
    }
}

@MainActor
final class KinetiqQualityForgeController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = "Select a video imported into Kinetiq. The original is never replaced."
    @Published private(set) var result: URL?
    @Published private(set) var originalBytes: Int64 = 0
    @Published private(set) var convertedBytes: Int64 = 0
    private var exportSession: AVAssetExportSession?

    func cancel() {
        exportSession?.cancelExport()
        status = "Canceled. Your original file is still intact."
    }

    func convert(_ item: KinetiqImportedVideo, preset: KinetiqQualityPreset) {
        guard !busy else { return }
        busy = true
        result = nil
        originalBytes = item.bytes
        convertedBytes = 0
        status = "Checking file, battery and thermal conditions…"
        Task { await execute(item, preset: preset) }
    }

    private func execute(_ item: KinetiqImportedVideo, preset: KinetiqQualityPreset) async {
        defer { busy = false; exportSession = nil }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        if level >= 0 && level < 0.15 && device.batteryState != .charging &&
           device.batteryState != .full {
            status = "Battery below 15%. Charge your iPhone before converting video."
            return
        }
        if ProcessInfo.processInfo.thermalState == .serious ||
           ProcessInfo.processInfo.thermalState == .critical {
            status = "iPhone is too warm. Allow it to cool before converting."
            return
        }
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            status = "The imported source is missing."
            return
        }
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        let free = (try? item.url.resourceValues(forKeys: [key]).volumeAvailableCapacityForImportantUsage) ?? 0
        guard free > max(300_000_000, item.bytes) else {
            status = "Not enough spare storage for a second playable copy. No changes made."
            return
        }

        let asset = AVURLAsset(url: item.url)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset.exportPreset),
              exporter.supportedFileTypes.contains(.mov) else {
            status = "This codec/container cannot be converted with Apple's native HEVC exporter."
            return
        }

        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KinetiqMedia", isDirectory: true)
            .appendingPathComponent("Conversions", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { status = "Could not create the conversions directory."; return }

        let output = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        exporter.outputURL = output
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        exportSession = exporter
        status = "Encoding a new HEVC copy. Keep Kinetiq open until complete…"

        // Callback API works on the iOS 17 deployment target. The caller's
        // task awaits completion while the export session performs the work.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }

        if exporter.status == .cancelled {
            try? FileManager.default.removeItem(at: output)
            status = "Conversion canceled. Original preserved."
            return
        }
        guard exporter.status == .completed,
              let bytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize),
              bytes > 0 else {
            try? FileManager.default.removeItem(at: output)
            status = "Conversion failed: \(exporter.error?.localizedDescription ?? "Unsupported input or exporter failure"). Original preserved."
            return
        }

        let newAsset = AVURLAsset(url: output)
        do {
            let before = try await asset.load(.duration).seconds
            let after = try await newAsset.load(.duration).seconds
            guard before.isFinite, after.isFinite, before > 0,
                  abs(before - after) < max(2, before * 0.01) else {
                try? FileManager.default.removeItem(at: output)
                status = "Output failed the runtime verification. Original preserved."
                return
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            status = "Could not verify the new video's duration. Original preserved."
            return
        }
        result = output
        convertedBytes = Int64(bytes)
        let difference = item.bytes - Int64(bytes)
        if difference > 0 {
            status = "Converted copy verified. Saved \(ByteCountFormatter.string(fromByteCount: difference, countStyle: .file)) compared with this original. Check subtitles/audio before relying on it offline."
        } else {
            status = "Converted copy verified, but this setting made the file larger. Original preserved. You can compare both versions."
        }
    }
}

@MainActor
struct KinetiqQualityForgeView: View {
    @StateObject private var worker = KinetiqQualityForgeController()
    @State private var selected: KinetiqImportedVideo?
    @State private var preset: KinetiqQualityPreset = .compact
    @State private var showingConfirmation = false
    @State private var previewURL: URL?

    private var inputs: [KinetiqImportedVideo] { KinetiqPrivateLibraryScanner.importedVideos() }

    var body: some View {
        List {
            Section {
                Label("Quality Forge", systemImage: "wand.and.stars")
                    .font(.title3.weight(.bold))
                Text("Native HEVC re-encoding for your own or authorized imported video. Quality and space savings depend on the source; video ZIP compression cannot magically preserve full quality with dramatic savings.")
                    .font(.subheadline)
                Label("Non-destructive: originals are never deleted", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.green)
            }
            Section("Imported videos") {
                if inputs.isEmpty {
                    Text("Import a supported video into your Kinetiq local library first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inputs) { video in
                    Button {
                        selected = video
                        previewURL = video.url
                    } label: {
                        HStack {
                            Image(systemName: selected?.url == video.url ? "checkmark.circle.fill" : "film")
                            VStack(alignment: .leading) {
                                Text(video.title).lineLimit(2)
                                Text(ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Output") {
                Picker("Encoding", selection: $preset) {
                    ForEach(KinetiqQualityPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("HEVC · Quality retains source dimensions when supported. HEVC · 1080p can reduce dimensions, losing some detail. We cannot estimate size faithfully until encoding finishes.")
                    .font(.caption).foregroundStyle(.secondary)
                if worker.busy {
                    ProgressView("Converting…")
                    Button("Cancel conversion", role: .cancel) { worker.cancel() }
                } else {
                    Button("Create separate compressed copy", systemImage: "square.on.square") {
                        showingConfirmation = true
                    }
                    .disabled(selected == nil)
                }
                Text(worker.status).font(.caption)
                if let output = worker.result {
                    LabeledContent("Source", value: ByteCountFormatter.string(fromByteCount: worker.originalBytes, countStyle: .file))
                    LabeledContent("Converted", value: ByteCountFormatter.string(fromByteCount: worker.convertedBytes, countStyle: .file))
                    Button("Preview converted version", systemImage: "play.rectangle") { previewURL = output }
                    ShareLink(item: output) { Label("Export converted copy", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Quality Forge")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Convert imported video?", isPresented: $showingConfirmation,
                            titleVisibility: .visible) {
            if let selected {
                Button("Convert \(selected.title)") { worker.convert(selected, preset: preset) }
            }
        } message: {
            Text("Exporting may take a long time, use extra storage and battery, and can change video quality or available tracks. Your original stays untouched.")
        }
        .sheet(item: Binding(get: { previewURL.map { PreviewVideo(url: $0) } },
                             set: { previewURL = $0?.url })) { preview in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: preview.url))
                    .navigationTitle(preview.url.lastPathComponent)
                    .toolbar { Button("Done") { previewURL = nil } }
            }
        }
    }

    private struct PreviewVideo: Identifiable {
        let url: URL
        var id: String { url.path }
    }
}
