//
//  PhotoStore.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import UIKit
import Combine
import CoreLocation

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

@MainActor
final class PhotoStore: ObservableObject {

    @Published private(set) var photos: [DailyPhoto] = []

    private let fileManager = FileManager.default

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

        photos.removeAll { $0.id == photo.id }
        persistIndex()
    }

    func deleteAll() {
        for photo in photos {
            removeImageFile(named: photo.backImageFilename)
            removeImageFile(named: photo.frontImageFilename)
        }

        photos.removeAll()
        persistIndex()
    }

    func loadImage(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func combinedImage(for photo: DailyPhoto, frontImageIsLarge: Bool = false) -> UIImage? {
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

    func shareURL(for photo: DailyPhoto, frontImageIsLarge: Bool = false) -> URL? {
        guard let image = combinedImage(for: photo, frontImageIsLarge: frontImageIsLarge) else {
            return nil
        }

        return writeTemporaryJPEG(image)
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

    func thumbnail(for photo: DailyPhoto) async -> UIImage? {
        let sourceImage = combinedImage(for: photo)
            ?? loadImage(filename: photo.frontImageFilename)
            ?? loadImage(filename: photo.backImageFilename)

        guard let sourceImage else {
            return nil
        }

        let targetSize = CGSize(width: 80, height: 80)

        return await Task.detached(priority: .userInitiated) {
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            return renderer.image { _ in
                sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }.value
    }

    private func photos(forMonth date: Date) -> [DailyPhoto] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    private func photos(forYear date: Date) -> [DailyPhoto] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .year) }
    }

    private func write(image: UIImage, filename: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = photosDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
    }

    private func removeImageFile(named filename: String) {
        let url = photosDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: indexURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DailyPhoto].self, from: data) else { return }
        photos = decoded
    }

    private func writeTemporaryJPEG(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }

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

    // MARK: - Image composition helpers

    private static func combinedImage(
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

    private static func combinedImage(largeImage: UIImage, smallImage: UIImage) -> UIImage {
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
