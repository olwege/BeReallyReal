//
//  DailyPhoto.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import Foundation

struct DailyPhoto: Identifiable, Codable {
    let id: UUID
    let date: Date          // normalized to midnight, used as the "day key"
    let capturedAt: Date    // actual capture timestamp
    let backImageFilename: String
    let frontImageFilename: String

    var dayKey: String {
        DailyPhoto.dayKeyFormatter.string(from: date)
    }

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
