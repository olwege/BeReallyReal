//
//  DailyPhoto.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import Foundation

struct DailyPhoto: Identifiable, Codable {
    let id: UUID
    let date: Date
    let capturedAt: Date
    let backImageFilename: String
    let frontImageFilename: String
    let caption: String?
    let latitude: Double?
    let longitude: Double?

    init(
        id: UUID,
        date: Date,
        capturedAt: Date,
        backImageFilename: String,
        frontImageFilename: String,
        caption: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.capturedAt = capturedAt
        self.backImageFilename = backImageFilename
        self.frontImageFilename = frontImageFilename
        self.caption = caption
        self.latitude = latitude
        self.longitude = longitude
    }

    var dayKey: String {
        DailyPhoto.dayKeyFormatter.string(from: date)
    }

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
