//
//  NotificationScheduler.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import UserNotifications

enum NotificationScheduler {

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                scheduleNext()
            }
        }
    }

    /// Schedules a single notification at a random time later today (or tomorrow if today's window has passed).
    static func scheduleNext(windowStartHour: Int = 6, windowEndHour: Int = 23) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["dailyPhotoReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Time for your daily photo"
        content.body = "Capture today's moment 📸"
        content.sound = .default

        if Config.testModeFastNotifications {
            // Fires every 60s, repeating — for testing only.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true)
            let request = UNNotificationRequest(identifier: "dailyPhotoReminder", content: content, trigger: trigger)
            center.add(request)
            return
        }

        // --- normal random-once-daily logic below (unchanged) ---
        let calendar = Calendar.current
        let now = Date()
        var targetDay = calendar.startOfDay(for: now)
        let randomHour = Int.random(in: windowStartHour..<windowEndHour)
        let randomMinute = Int.random(in: 0..<60)
        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        components.hour = randomHour
        components.minute = randomMinute
        var fireDate = calendar.date(from: components) ?? now
        if fireDate <= now {
            targetDay = calendar.date(byAdding: .day, value: 1, to: targetDay) ?? targetDay
            components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = randomHour
            components.minute = randomMinute
            fireDate = calendar.date(from: components) ?? now
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: "dailyPhotoReminder", content: content, trigger: trigger)
        center.add(request)
    }
}
