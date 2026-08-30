//
//  PhotoStore.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import UIKit
import Combine
import CoreLocation
import ImageIO

enum PhotoCompositionStyle {
    static let previewAspectRatio: CGFloat = 1.4

    static func overlayMargin(for size: CGSize) -> CGFloat {
        guard size.width.isFinite, size.width > 0 else {
            return 0
        }

        return max(size.width * 0.035, 16)
    }

    static func overlayHeight(for size: CGSize) -> CGFloat {
        guard size.height.isFinite, size.height > 0 else {
            return 1
        }

        return max(size.height * 0.3, 1)
    }

    static func overlayBorderWidth(for size: CGSize) -> CGFloat {
        let shortestSide = min(size.width, size.height)

        guard shortestSide.isFinite, shortestSide > 0 else {
            return 0
        }

        return max(shortestSide * 0.006, 2)
    }

    static func overlayCornerRadius(for overlayWidth: CGFloat) -> CGFloat {
        guard overlayWidth.isFinite, overlayWidth > 0 else {
            return 0
        }

        return overlayWidth * 0.08
    }
}

enum PhotoBackupImportMode {
    case replace
    case merge
}

enum PhotoThumbnailSize: String, Sendable {
    case small
    case medium

    var backMaxPixelSize: CGFloat {
        switch self {
        case .small:
            360
        case .medium:
            640
        }
    }

    var frontMaxPixelSize: CGFloat {
        switch self {
        case .small:
            180
        case .medium:
            320
        }
    }
}

@MainActor
final class PhotoStore: ObservableObject {

    @Published private(set) var photos: [DailyPhoto] = []

    private static let storageJPEGQuality: CGFloat = 0.97
    private static let shareJPEGQuality: CGFloat = 0.98

    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private var photosDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DailyPhotos", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL {
        photosDirectory.appendingPathComponent("index.json")
    }

    init() {
        imageCache.countLimit = 4
        imageCache.totalCostLimit = 16 * 1024 * 1024

        thumbnailCache.countLimit = 80
        thumbnailCache.totalCostLimit = 24 * 1024 * 1024

        load()
    }

    func hasEntry(for date: Date) -> Bool {
        let key = DailyPhoto.dayKeyFormatter.string(from: date)
        return photos.contains { $0.dayKey == key }
    }

    func photos(for date: Date) -> [DailyPhoto] {
        let key = DailyPhoto.dayKeyFormatter.string(from: date)
        return photos
            .filter { $0.dayKey == key }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    func save(
        backImage: UIImage,
        frontImage: UIImage,
        caption: String? = nil,
        location: CLLocationCoordinate2D? = nil,
        date: Date = Date()
    ) {
        let id = UUID()
        let backName = "\(id.uuidString)_back.jpg"
        let frontName = "\(id.uuidString)_front.jpg"

        write(image: backImage, filename: backName)
        write(image: frontImage, filename: frontName)

        let entry = DailyPhoto(
            id: id,
            date: Calendar.current.startOfDay(for: date),
            capturedAt: date,
            backImageFilename: backName,
            frontImageFilename: frontName,
            caption: caption,
            latitude: location?.latitude,
            longitude: location?.longitude
        )

        photos.append(entry)
        persistIndex()
    }

    func delete(_ photo: DailyPhoto) {
        removeImageFile(named: photo.backImageFilename)
        removeImageFile(named: photo.frontImageFilename)
        thumbnailCache.removeAllObjects()

        photos.removeAll { $0.id == photo.id }
        persistIndex()
    }

    func deleteAll() {
        for photo in photos {
            removeImageFile(named: photo.backImageFilename)
            removeImageFile(named: photo.frontImageFilename)
        }

        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        photos.removeAll()
        persistIndex()
    }

    func loadImage(filename: String) -> UIImage? {
        let cacheKey = filename as NSString

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let url = photosDirectory.appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let image = UIImage(data: data) else {
            return nil
        }

        imageCache.setObject(image, forKey: cacheKey, cost: image.memoryCost)
        return image
    }

    func combinedImage(for photo: DailyPhoto, frontImageIsLarge: Bool = false) -> UIImage? {
        autoreleasepool {
            guard let backImage = loadImage(filename: photo.backImageFilename),
                  let frontImage = loadImage(filename: photo.frontImageFilename) else {
                return nil
            }

            return Self.combinedImage(
                backImage: backImage,
                frontImage: frontImage,
                frontImageIsLarge: frontImageIsLarge
            )
        }
    }

    func shareURL(for photo: DailyPhoto, frontImageIsLarge: Bool = false) -> URL? {
        autoreleasepool {
            guard let image = combinedImage(for: photo, frontImageIsLarge: frontImageIsLarge) else {
                return nil
            }

            return writeTemporaryJPEG(image)
        }
    }

    func shareURLs(inMonthOf date: Date) -> [URL] {
        photos(forMonth: date).compactMap { shareURL(for: $0) }
    }

    func shareURLs(inYearOf date: Date) -> [URL] {
        photos(forYear: date).compactMap { shareURL(for: $0) }
    }

    func allShareURLs() -> [URL] {
        photos.compactMap { shareURL(for: $0) }
    }

    func images(inMonthOf date: Date) -> [UIImage] {
        photos(forMonth: date).flatMap { photo in
            [loadImage(filename: photo.backImageFilename),
             loadImage(filename: photo.frontImageFilename)]
        }
        .compactMap { $0 }
    }

    func images(inYearOf date: Date) -> [UIImage] {
        photos(forYear: date).flatMap { photo in
            [loadImage(filename: photo.backImageFilename),
             loadImage(filename: photo.frontImageFilename)]
        }
        .compactMap { $0 }
    }

    func allImages() -> [UIImage] {
        photos.flatMap { photo in
            [loadImage(filename: photo.backImageFilename),
             loadImage(filename: photo.frontImageFilename)]
        }
        .compactMap { $0 }
    }

    func thumbnail(for photo: DailyPhoto, size: PhotoThumbnailSize = .small) async -> UIImage? {
        let cacheKey = thumbnailCacheKey(for: photo, size: size)

        if let cachedThumbnail = thumbnailCache.object(forKey: cacheKey) {
            return cachedThumbnail
        }

        let backURL = photosDirectory.appendingPathComponent(photo.backImageFilename)
        let frontURL = photosDirectory.appendingPathComponent(photo.frontImageFilename)
        let backMaxPixelSize = size.backMaxPixelSize
        let frontMaxPixelSize = size.frontMaxPixelSize

        let thumbnail = await Task.detached(priority: .utility) { () -> UIImage? in
            autoreleasepool {
                guard let backImage = downsampleImage(at: backURL, maxPixelSize: backMaxPixelSize),
                      let frontImage = downsampleImage(at: frontURL, maxPixelSize: frontMaxPixelSize) else {
                    return nil
                }

                return Self.combinedImage(
                    backImage: backImage,
                    frontImage: frontImage,
                    frontImageIsLarge: false
                )
            }
        }.value

        if let thumbnail {
            thumbnailCache.setObject(thumbnail, forKey: cacheKey, cost: thumbnail.memoryCost)
        }

        return thumbnail
    }

    func createBackupPackage() throws -> URL {
        let backupURL = fileManager.temporaryDirectory
            .appendingPathComponent("BeReallyReal Backup-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("bereallyrealbackup")

        let imagesDirectory = backupURL.appendingPathComponent("Images", isDirectory: true)

        try fileManager.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )

        let manifest = PhotoBackupManifest(
            formatVersion: 2,
            exportedAt: Date(),
            photos: photos
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let manifestData = try encoder.encode(manifest)

        try manifestData.write(
            to: backupURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let referencedFilenames = Set(
            photos.flatMap { photo in
                [
                    photo.backImageFilename,
                    photo.frontImageFilename
                ]
            }
        )

        for filename in referencedFilenames.sorted() {
            guard isSafeStoredImageFilename(filename) else {
                continue
            }

            let sourceURL = photosDirectory.appendingPathComponent(filename)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = imagesDirectory.appendingPathComponent(filename)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return backupURL
    }

    func importBackup(at url: URL, mode: PhotoBackupImportMode) throws {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])

        if resourceValues.isDirectory == true {
            try importBackupPackage(at: url, mode: mode)
        } else {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try importBackupData(data, mode: mode)
        }
    }

    func exportBackupData() throws -> Data {
        let referencedFilenames = Set(
            photos.flatMap { photo in
                [
                    photo.backImageFilename,
                    photo.frontImageFilename
                ]
            }
        )

        let imageFiles = try referencedFilenames
            .sorted()
            .compactMap { filename -> BackupImageFile? in
                let url = photosDirectory.appendingPathComponent(filename)

                guard fileManager.fileExists(atPath: url.path) else {
                    return nil
                }

                let data = try Data(contentsOf: url)
                return BackupImageFile(filename: filename, data: data)
            }

        let backup = PhotoBackup(
            formatVersion: 1,
            exportedAt: Date(),
            photos: photos,
            imageFiles: imageFiles
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        return try encoder.encode(backup)
    }

    func importBackupData(_ data: Data, mode: PhotoBackupImportMode) throws {
        let decoder = PropertyListDecoder()
        let backup = try decoder.decode(PhotoBackup.self, from: data)

        switch mode {
        case .replace:
            removeEverythingInPhotosDirectory()

            for imageFile in backup.imageFiles {
                try writeImageData(imageFile.data, filename: imageFile.filename)
            }

            imageCache.removeAllObjects()
            thumbnailCache.removeAllObjects()
            photos = backup.photos.sorted { $0.capturedAt < $1.capturedAt }
            persistIndex()

        case .merge:
            let existingIDs = Set(photos.map(\.id))
            let importedPhotos = backup.photos.filter { !existingIDs.contains($0.id) }

            let neededFilenames = Set(
                importedPhotos.flatMap { photo in
                    [
                        photo.backImageFilename,
                        photo.frontImageFilename
                    ]
                }
            )

            for imageFile in backup.imageFiles where neededFilenames.contains(imageFile.filename) {
                try writeImageData(imageFile.data, filename: imageFile.filename)
            }

            photos.append(contentsOf: importedPhotos)
            photos.sort { $0.capturedAt < $1.capturedAt }
            persistIndex()
        }
    }

    private func importBackupPackage(at url: URL, mode: PhotoBackupImportMode) throws {
        let manifestURL = url.appendingPathComponent("manifest.json")
        let imagesDirectory = url.appendingPathComponent("Images", isDirectory: true)

        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest = try JSONDecoder().decode(PhotoBackupManifest.self, from: manifestData)

        switch mode {
        case .replace:
            removeEverythingInPhotosDirectory()

            try copyBackupImageFiles(
                for: manifest.photos,
                from: imagesDirectory
            )

            imageCache.removeAllObjects()
            thumbnailCache.removeAllObjects()
            photos = manifest.photos.sorted { $0.capturedAt < $1.capturedAt }
            persistIndex()

        case .merge:
            let existingIDs = Set(photos.map(\.id))
            let importedPhotos = manifest.photos.filter { !existingIDs.contains($0.id) }

            try copyBackupImageFiles(
                for: importedPhotos,
                from: imagesDirectory
            )

            imageCache.removeAllObjects()
            thumbnailCache.removeAllObjects()
            photos.append(contentsOf: importedPhotos)
            photos.sort { $0.capturedAt < $1.capturedAt }
            persistIndex()
        }
    }

    private func copyBackupImageFiles(
        for importedPhotos: [DailyPhoto],
        from sourceImagesDirectory: URL
    ) throws {
        let neededFilenames = Set(
            importedPhotos.flatMap { photo in
                [
                    photo.backImageFilename,
                    photo.frontImageFilename
                ]
            }
        )

        for filename in neededFilenames {
            guard isSafeStoredImageFilename(filename) else {
                continue
            }

            let sourceURL = sourceImagesDirectory.appendingPathComponent(filename)
            let destinationURL = photosDirectory.appendingPathComponent(filename)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            imageCache.removeObject(forKey: filename as NSString)
        }
    }

    private func photos(forMonth date: Date) -> [DailyPhoto] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    private func photos(forYear date: Date) -> [DailyPhoto] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .year) }
    }

    private func thumbnailCacheKey(for photo: DailyPhoto, size: PhotoThumbnailSize) -> NSString {
        "thumbnail-\(size.rawValue)-\(photo.id.uuidString)" as NSString
    }

    private func write(image: UIImage, filename: String) {
        guard let data = image.jpegData(compressionQuality: Self.storageJPEGQuality) else { return }

        let url = photosDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            imageCache.removeObject(forKey: filename as NSString)
            thumbnailCache.removeAllObjects()
        } catch {
            return
        }
    }

    private func writeImageData(_ data: Data, filename: String) throws {
        guard isSafeStoredImageFilename(filename) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let url = photosDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        imageCache.removeObject(forKey: filename as NSString)
        thumbnailCache.removeAllObjects()
    }

    private func removeImageFile(named filename: String) {
        let url = photosDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
        imageCache.removeObject(forKey: filename as NSString)
    }

    private func removeEverythingInPhotosDirectory() {
        let directory = photosDirectory
        let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        for url in contents ?? [] {
            try? fileManager.removeItem(at: url)
        }

        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        photos.removeAll()
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DailyPhoto].self, from: data) else { return }
        photos = decoded
    }

    private func writeTemporaryJPEG(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: Self.shareJPEGQuality) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func isSafeStoredImageFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty else {
            return false
        }

        return filename == URL(fileURLWithPath: filename).lastPathComponent
    }

    // MARK: - Image composition helpers

    private nonisolated static func combinedImage(
        backImage: UIImage,
        frontImage: UIImage,
        frontImageIsLarge: Bool = false
    ) -> UIImage {
        if frontImageIsLarge {
            return combinedImage(largeImage: frontImage, smallImage: backImage)
        } else {
            return combinedImage(largeImage: backImage, smallImage: frontImage)
        }
    }

    private nonisolated static func combinedImage(largeImage: UIImage, smallImage: UIImage) -> UIImage {
        let canvasSize = largeImage.size

        let format = UIGraphicsImageRendererFormat()
        format.scale = largeImage.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            largeImage.draw(in: CGRect(origin: .zero, size: canvasSize))

            let borderWidth = PhotoCompositionStyle.overlayBorderWidth(for: canvasSize)
            let outerMargin = PhotoCompositionStyle.overlayMargin(for: canvasSize)
            let overlayHeight = PhotoCompositionStyle.overlayHeight(for: canvasSize)
            let overlayWidth = overlayHeight / PhotoCompositionStyle.previewAspectRatio
            let cornerRadius = PhotoCompositionStyle.overlayCornerRadius(for: overlayWidth)

            let overlayRect = CGRect(
                x: outerMargin + borderWidth,
                y: outerMargin + borderWidth,
                width: overlayWidth,
                height: overlayHeight
            )

            let borderRect = overlayRect.insetBy(dx: -borderWidth, dy: -borderWidth)
            let borderPath = UIBezierPath(
                roundedRect: borderRect,
                cornerRadius: cornerRadius + borderWidth
            )
            UIColor.black.setFill()
            borderPath.fill()

            let path = UIBezierPath(roundedRect: overlayRect, cornerRadius: cornerRadius)
            context.cgContext.saveGState()
            path.addClip()

            let smallAspect = smallImage.size.width / smallImage.size.height
            let rectAspect = overlayRect.width / overlayRect.height

            let drawRect: CGRect
            if smallAspect > rectAspect {
                let height = overlayRect.height
                let width = height * smallAspect
                drawRect = CGRect(
                    x: overlayRect.midX - width / 2,
                    y: overlayRect.minY,
                    width: width,
                    height: height
                )
            } else {
                let width = overlayRect.width
                let height = width / smallAspect
                drawRect = CGRect(
                    x: overlayRect.minX,
                    y: overlayRect.midY - height / 2,
                    width: width,
                    height: height
                )
            }

            smallImage.draw(in: drawRect)
            context.cgContext.restoreGState()
        }
    }
}

private struct PhotoBackupManifest: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let photos: [DailyPhoto]
}

private struct PhotoBackup: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let photos: [DailyPhoto]
    let imageFiles: [BackupImageFile]
}

private struct BackupImageFile: Codable {
    let filename: String
    let data: Data
}

private func downsampleImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]

    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
        return nil
    }

    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        downsampleOptions as CFDictionary
    ) else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}

private extension UIImage {
    var memoryCost: Int {
        if let cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        return Int(size.width * size.height * scale * scale * 4)
    }
}
