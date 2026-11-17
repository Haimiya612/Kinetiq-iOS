import Foundation
import AVFoundation
import CryptoKit
import UIKit

// MARK: - Local Thumbnail Metadata

private struct LocalThumbnailFingerprint: Codable, Equatable {
    let mediaID: String
    let fileSize: Int64
    let modificationDate: TimeInterval
}

private struct LocalThumbnailLoadResult {
    let image: UIImage
    let jpegData: Data?
}

// MARK: - Shared Local Media Thumbnail Cache

/// Persistent artwork cache exclusively for imported local video files.
///
/// The cache is intentionally restricted to direct children of
/// Documents/KinetiqMedia. Remote module artwork must use its own
/// source-provided image URL and must never be sent through this service.
///
/// Artwork belongs to the media file, not playback history:
/// - Completing playback does not remove artwork.
/// - Removing an item from Continue Watching does not remove artwork.
/// - Deleting the local media file invalidates its artwork.
final class LocalMediaThumbnailCache: @unchecked Sendable {

    static let shared = LocalMediaThumbnailCache()

    private let memoryCache = NSCache<NSString, UIImage>()

    private let stateQueue = DispatchQueue(
        label: "com.kinetiq.local-thumbnails.state",
        qos: .utility
    )

    private let generationQueue = DispatchQueue(
        label: "com.kinetiq.local-thumbnails.generation",
        qos: .utility,
        attributes: .concurrent
    )

    /// Serializes reads, writes, and deletion of thumbnail files.
    private let diskQueue = DispatchQueue(
        label: "com.kinetiq.local-thumbnails.disk",
        qos: .utility
    )

    private let localMediaDirectory: URL
    private let thumbnailDirectory: URL
    private let frameGenerator: (URL) -> UIImage?

    // All state below is accessed exclusively on stateQueue.
    private var pendingRequests: [
        String: [CheckedContinuation<UIImage?, Never>]
    ] = [:]

    private var invalidationVersions: [String: UInt64] = [:]
    private var latestFingerprints: [String: LocalThumbnailFingerprint] = [:]
    private var memoryFingerprints: [String: LocalThumbnailFingerprint] = [:]

    // MARK: Initialization

    private init() {
        localMediaDirectory = Self.defaultLocalMediaDirectory
        thumbnailDirectory = Self.defaultThumbnailDirectory
        frameGenerator = { url in
            Self.generateFrame(from: url)
        }

        configureMemoryCache()
    }

    /// Injectable initializer used by the unit tests.
    ///
    /// Tests receive their own media and cache directories and can provide
    /// a deterministic frame generator without needing real video files.
    init(
        localMediaDirectory: URL,
        thumbnailDirectory: URL,
        frameGenerator: @escaping (URL) -> UIImage?
    ) {
        self.localMediaDirectory = localMediaDirectory
        self.thumbnailDirectory = thumbnailDirectory
        self.frameGenerator = frameGenerator

        configureMemoryCache()
    }

    private func configureMemoryCache() {
        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 96 * 1024 * 1024
    }

    // MARK: Load or Generate

    func image(
        for mediaID: String,
        url: URL
    ) async -> UIImage? {
        guard !mediaID.isEmpty else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            stateQueue.async { [self] in
                guard let fingerprint = Self.fingerprint(
                    for: mediaID,
                    url: url,
                    localMediaDirectory: localMediaDirectory
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                // A changed file invalidates its previous in-memory image.
                if let previousFingerprint = latestFingerprints[mediaID],
                   previousFingerprint != fingerprint {
                    invalidationVersions[mediaID, default: 0] &+= 1
                }

                latestFingerprints[mediaID] = fingerprint

                if memoryFingerprints[mediaID] == fingerprint,
                   let cachedImage = memoryCache.object(
                       forKey: mediaID as NSString
                   ) {
                    continuation.resume(returning: cachedImage)
                    return
                }

                memoryCache.removeObject(
                    forKey: mediaID as NSString
                )
                memoryFingerprints.removeValue(forKey: mediaID)

                let requestKey = Self.requestKey(
                    mediaID: mediaID,
                    fingerprint: fingerprint
                )

                // Requests for the same file revision share one operation.
                if pendingRequests[requestKey] != nil {
                    pendingRequests[requestKey, default: []].append(
                        continuation
                    )
                    return
                }

                pendingRequests[requestKey] = [continuation]

                let requestVersion = invalidationVersions[
                    mediaID,
                    default: 0
                ]

                generationQueue.async { [self] in
                    let result = loadOrGenerateImage(
                        mediaID: mediaID,
                        url: url,
                        fingerprint: fingerprint
                    )

                    stateQueue.async { [self] in
                        let isCurrentGeneration =
                            invalidationVersions[
                                mediaID,
                                default: requestVersion
                            ] == requestVersion
                            && latestFingerprints[mediaID] == fingerprint

                        if isCurrentGeneration, let result {
                            let imageCost = result.image.cgImage.map {
                                $0.bytesPerRow * $0.height
                            } ?? 0

                            memoryCache.setObject(
                                result.image,
                                forKey: mediaID as NSString,
                                cost: imageCost
                            )

                            memoryFingerprints[mediaID] = fingerprint

                            // Only newly generated images need a disk write.
                            // The serial disk queue ensures a later deletion
                            // cannot be undone by an older generation.
                            if let jpegData = result.jpegData {
                                diskQueue.async { [self] in
                                    Self.persist(
                                        jpegData,
                                        fingerprint: fingerprint,
                                        thumbnailDirectory: thumbnailDirectory
                                    )
                                }
                            }
                        }

                        let continuations =
                            pendingRequests.removeValue(
                                forKey: requestKey
                            ) ?? []

                        let resolvedImage = isCurrentGeneration
                            ? result?.image
                            : nil

                        continuations.forEach {
                            $0.resume(returning: resolvedImage)
                        }
                    }
                }
            }
        }
    }

    // MARK: Invalidate One Local Media Item

    /// Call only after the corresponding local media file has been deleted
    /// or intentionally replaced.
    ///
    /// The returned task completes after the disk artifacts are removed.
    @discardableResult
    func invalidate(mediaID: String) -> Task<Void, Never> {
        guard !mediaID.isEmpty else {
            return Task {}
        }

        return Task {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in

                stateQueue.async { [self] in
                    // Prevent an in-flight generation from restoring
                    // deleted artwork.
                    invalidationVersions[mediaID, default: 0] &+= 1

                    latestFingerprints.removeValue(forKey: mediaID)
                    memoryFingerprints.removeValue(forKey: mediaID)

                    memoryCache.removeObject(
                        forKey: mediaID as NSString
                    )

                    diskQueue.async { [self] in
                        Self.removeDiskArtifacts(
                            for: mediaID,
                            thumbnailDirectory: thumbnailDirectory
                        )

                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: Remove Orphaned Local Thumbnails

    /// Cleans cached artwork only when the local media directory is
    /// available and can be read successfully.
    ///
    /// A missing or temporarily inaccessible directory is not treated as
    /// an empty library. Existing artwork is preserved in that situation.
    ///
    /// The returned task completes after cleanup has finished.
    @discardableResult
    func removeOrphans() -> Task<Void, Never> {
        Task {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in

                stateQueue.async { [self] in
                    let fileManager = FileManager.default

                    guard fileManager.fileExists(
                        atPath: localMediaDirectory.path
                    ),
                    let mediaFiles = try? fileManager.contentsOfDirectory(
                        at: localMediaDirectory,
                        includingPropertiesForKeys: [.isRegularFileKey]
                    ) else {
                        continuation.resume()
                        return
                    }

                    let validMediaIDs = Set(
                        mediaFiles.compactMap { fileURL -> String? in
                            guard let values = try? fileURL.resourceValues(
                                forKeys: [
                                    .isRegularFileKey,
                                    .isSymbolicLinkKey
                                ]
                            ),
                            values.isRegularFile == true,
                            values.isSymbolicLink != true else {
                                return nil
                            }

                            return fileURL.lastPathComponent
                        }
                    )

                    // Invalidate in-flight requests for files that no longer
                    // exist.
                    let staleIDs = latestFingerprints.keys.filter {
                        !validMediaIDs.contains($0)
                    }

                    for mediaID in staleIDs {
                        invalidationVersions[mediaID, default: 0] &+= 1

                        latestFingerprints.removeValue(forKey: mediaID)
                        memoryFingerprints.removeValue(forKey: mediaID)

                        memoryCache.removeObject(
                            forKey: mediaID as NSString
                        )
                    }

                    let validCacheStems = Set(
                        validMediaIDs.map(Self.cacheStem)
                    )

                    diskQueue.async { [self] in
                        guard fileManager.fileExists(
                            atPath: thumbnailDirectory.path
                        ),
                        let cachedFiles = try? fileManager.contentsOfDirectory(
                            at: thumbnailDirectory,
                            includingPropertiesForKeys: nil
                        ) else {
                            continuation.resume()
                            return
                        }

                        for fileURL in cachedFiles {
                            let fileExtension =
                                fileURL.pathExtension.lowercased()

                            guard fileExtension == "jpg"
                                    || fileExtension == "json" else {
                                continue
                            }

                            let stem = fileURL
                                .deletingPathExtension()
                                .lastPathComponent

                            if !validCacheStems.contains(stem) {
                                try? fileManager.removeItem(at: fileURL)
                            }
                        }

                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: Local File Validation

    private static func fingerprint(
        for mediaID: String,
        url: URL,
        localMediaDirectory: URL
    ) -> LocalThumbnailFingerprint? {
        guard url.isFileURL,
              url.lastPathComponent == mediaID,
              url.standardizedFileURL.deletingLastPathComponent()
                == localMediaDirectory.standardizedFileURL,
              let values = try? url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return nil
        }

        // Do not use URL.resourceValues for size or modification time here.
        // URL resource values can be cached by Foundation. That becomes
        // problematic when a media file is atomically replaced at the same
        // path: a previously used URL may still report its old attributes.
        //
        // FileManager reads the current attributes from the filesystem.
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ),
        let fileSize = attributes[.size] as? NSNumber,
        let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return LocalThumbnailFingerprint(
            mediaID: mediaID,
            fileSize: fileSize.int64Value,
            modificationDate: modificationDate.timeIntervalSince1970
        )
    }

    private static func requestKey(
        mediaID: String,
        fingerprint: LocalThumbnailFingerprint
    ) -> String {
        [
            mediaID,
            String(fingerprint.fileSize),
            String(fingerprint.modificationDate.bitPattern)
        ]
        .joined(separator: "|")
    }

    // MARK: Storage Locations

    private static var defaultLocalMediaDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "KinetiqMedia",
            isDirectory: true
        )
    }

    private static var defaultThumbnailDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "Kinetiq",
            isDirectory: true
        )
        .appendingPathComponent(
            "Thumbnails",
            isDirectory: true
        )
    }

    private static func cacheStem(for mediaID: String) -> String {
        let digest = SHA256.hash(
            data: Data(mediaID.utf8)
        )

        return digest.map {
            String(format: "%02x", $0)
        }
        .joined()
    }

    private static func imageURL(
        for mediaID: String,
        in directory: URL
    ) -> URL {
        directory
            .appendingPathComponent(cacheStem(for: mediaID))
            .appendingPathExtension("jpg")
    }

    private static func metadataURL(
        for mediaID: String,
        in directory: URL
    ) -> URL {
        directory
            .appendingPathComponent(cacheStem(for: mediaID))
            .appendingPathExtension("json")
    }

    // MARK: Disk Cache

    private func loadOrGenerateImage(
        mediaID: String,
        url: URL,
        fingerprint: LocalThumbnailFingerprint
    ) -> LocalThumbnailLoadResult? {
        // All disk reads and writes are serialized through diskQueue.
        let cachedImage = diskQueue.sync {
            Self.loadDiskImage(
                for: mediaID,
                fingerprint: fingerprint,
                thumbnailDirectory: thumbnailDirectory
            )
        }

        if let cachedImage {
            return LocalThumbnailLoadResult(
                image: cachedImage,
                jpegData: nil
            )
        }

        guard let generatedImage = frameGenerator(url),
              let jpegData = generatedImage.jpegData(
                compressionQuality: 0.88
              ) else {
            return nil
        }

        return LocalThumbnailLoadResult(
            image: generatedImage,
            jpegData: jpegData
        )
    }

    private static func loadDiskImage(
        for mediaID: String,
        fingerprint: LocalThumbnailFingerprint,
        thumbnailDirectory: URL
    ) -> UIImage? {
        let metadataURL = metadataURL(
            for: mediaID,
            in: thumbnailDirectory
        )

        let imageURL = imageURL(
            for: mediaID,
            in: thumbnailDirectory
        )

        guard let metadataData = try? Data(contentsOf: metadataURL),
              let storedFingerprint = try? JSONDecoder().decode(
                LocalThumbnailFingerprint.self,
                from: metadataData
              ),
              storedFingerprint == fingerprint,
              let image = UIImage(contentsOfFile: imageURL.path) else {
            return nil
        }

        return image
    }

    private static func persist(
        _ jpegData: Data,
        fingerprint: LocalThumbnailFingerprint,
        thumbnailDirectory: URL
    ) {
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: thumbnailDirectory,
                withIntermediateDirectories: true
            )

            var directoryURL = thumbnailDirectory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? directoryURL.setResourceValues(resourceValues)

            try jpegData.write(
                to: imageURL(
                    for: fingerprint.mediaID,
                    in: thumbnailDirectory
                ),
                options: .atomic
            )

            let metadataData = try JSONEncoder().encode(fingerprint)

            try metadataData.write(
                to: metadataURL(
                    for: fingerprint.mediaID,
                    in: thumbnailDirectory
                ),
                options: .atomic
            )
        } catch {
            // The in-memory image remains usable. A later request can retry
            // persistence if the application-support directory becomes
            // writable again.
        }
    }

    // MARK: Frame Generation

    private static func generateFrame(from url: URL) -> UIImage? {
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)

        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: 900,
            height: 900
        )

        let duration = asset.duration.seconds

        let sampleTime: Double

        if duration.isFinite, duration > 0 {
            sampleTime = min(
                duration * 0.12,
                max(duration - 0.05, 0)
            )
        } else {
            sampleTime = 1
        }

        let timestamp = CMTime(
            seconds: sampleTime,
            preferredTimescale: 600
        )

        guard let cgImage = try? generator.copyCGImage(
            at: timestamp,
            actualTime: nil
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: Disk Cleanup

    private static func removeDiskArtifacts(
        for mediaID: String,
        thumbnailDirectory: URL
    ) {
        try? FileManager.default.removeItem(
            at: imageURL(
                for: mediaID,
                in: thumbnailDirectory
            )
        )

        try? FileManager.default.removeItem(
            at: metadataURL(
                for: mediaID,
                in: thumbnailDirectory
            )
        )
    }
}