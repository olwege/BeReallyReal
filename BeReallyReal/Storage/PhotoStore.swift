//
//  PhotoStore.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import UIKit
import Combine

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

    func save(backImage: UIImage, frontImage: UIImage, date: Date = Date()) {
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
            frontImageFilename: frontName
        )
        photos.append(entry)
        persistIndex()
    }

    func loadImage(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func write(image: UIImage, filename: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = photosDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
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
    
    func images(inMonthOf date: Date) -> [UIImage] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
            .flatMap { [loadImage(filename: $0.backImageFilename), loadImage(filename: $0.frontImageFilename)] }
            .compactMap { $0 }
    }

    func images(inYearOf date: Date) -> [UIImage] {
        let cal = Calendar.current
        return photos.filter { cal.isDate($0.date, equalTo: date, toGranularity: .year) }
            .flatMap { [loadImage(filename: $0.backImageFilename), loadImage(filename: $0.frontImageFilename)] }
            .compactMap { $0 }
    }

    func allImages() -> [UIImage] {
        photos.flatMap { [loadImage(filename: $0.backImageFilename), loadImage(filename: $0.frontImageFilename)] }
            .compactMap { $0 }
    }
    
    func deleteAll() {
        for photo in photos {
            try? fileManager.removeItem(at: photosDirectory.appendingPathComponent(photo.backImageFilename))
            try? fileManager.removeItem(at: photosDirectory.appendingPathComponent(photo.frontImageFilename))
        }
        photos.removeAll()
        persistIndex()
    }
}
