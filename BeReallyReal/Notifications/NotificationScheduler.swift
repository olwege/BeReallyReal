//
//  NotificationScheduler.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import Foundation
import UserNotifications

enum NotificationScheduler {
    private static let weekdayStartHourKey = "weekdayReminderStartHour"
    private static let weekdayEndHourKey = "weekdayReminderEndHour"
    private static let weekendStartHourKey = "weekendReminderStartHour"
    private static let weekendEndHourKey = "weekendReminderEndHour"

    private static let defaultWeekdayWindow = ReminderWindow(startHour: 6, endHour: 22)
    private static let defaultWeekendWindow = ReminderWindow(startHour: 8, endHour: 24)

    static func requestPermission(hasPhotoToday: Bool = false) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        scheduleNext(hasPhotoToday: hasPhotoToday)
                    }
                }

            case .authorized, .provisional, .ephemeral:
                scheduleNext(hasPhotoToday: hasPhotoToday)

            case .denied:
                break

            @unknown default:
                break
            }
        }
    }

    /// Schedules the next notification at a random time inside the configured window.
    ///
    /// If `hasPhotoToday` is true, today is skipped entirely and the reminder is scheduled
    /// for tomorrow inside the configured window.
    static func scheduleNext(hasPhotoToday: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["dailyPhotoReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Time for your daily photo"
        content.body = "Capture today's moment."
        content.sound = .default

        if Config.testModeFastNotifications && !hasPhotoToday {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true)
            let request = UNNotificationRequest(identifier: "dailyPhotoReminder", content: content, trigger: trigger)
            center.add(request)
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)

        let fireDate: Date

        if hasPhotoToday {
            fireDate = randomFireDate(on: tomorrow, after: nil, calendar: calendar)
                ?? fallbackFireDate(on: tomorrow, calendar: calendar)
        } else {
            fireDate = randomFireDate(on: today, after: now, calendar: calendar)
                ?? randomFireDate(on: tomorrow, after: nil, calendar: calendar)
                ?? fallbackFireDate(on: tomorrow, calendar: calendar)
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "dailyPhotoReminder",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    private static func randomFireDate(on day: Date, after minimumDate: Date?, calendar: Calendar) -> Date? {
        let window = reminderWindow(for: day, calendar: calendar)

        guard let windowStart = calendar.date(byAdding: .hour, value: window.startHour, to: day),
              let windowEnd = calendar.date(byAdding: .hour, value: window.endHour, to: day)
        else {
            return nil
        }

        let earliestDate: Date

        if let minimumDate, minimumDate > windowStart {
            earliestDate = startOfNextMinute(after: minimumDate, calendar: calendar)
        } else {
            earliestDate = windowStart
        }

        guard earliestDate < windowEnd else {
            return nil
        }

        let availableMinutes = max(1, Int(windowEnd.timeIntervalSince(earliestDate) / 60))
        let randomOffset = Int.random(in: 0..<availableMinutes)

        return calendar.date(byAdding: .minute, value: randomOffset, to: earliestDate)
    }

    private static func fallbackFireDate(on day: Date, calendar: Calendar) -> Date {
        let window = reminderWindow(for: day, calendar: calendar)

        return calendar.date(byAdding: .hour, value: window.startHour, to: day)
            ?? day.addingTimeInterval(60 * 60)
    }

    private static func reminderWindow(for date: Date, calendar: Calendar) -> ReminderWindow {
        let defaults = UserDefaults.standard

        let fallback = calendar.isDateInWeekend(date) ? defaultWeekendWindow : defaultWeekdayWindow

        let startKey = calendar.isDateInWeekend(date) ? weekendStartHourKey : weekdayStartHourKey
        let endKey = calendar.isDateInWeekend(date) ? weekendEndHourKey : weekdayEndHourKey

        let rawStartHour = defaults.object(forKey: startKey) as? Int ?? fallback.startHour
        let rawEndHour = defaults.object(forKey: endKey) as? Int ?? fallback.endHour

        let startHour = min(max(rawStartHour, 0), 23)
        let endHour = min(max(rawEndHour, 1), 24)

        guard startHour < endHour else {
            return fallback
        }

        return ReminderWindow(startHour: startHour, endHour: endHour)
    }

    private static func startOfNextMinute(after date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let startOfCurrentMinute = calendar.date(from: components) ?? date

        return calendar.date(byAdding: .minute, value: 1, to: startOfCurrentMinute) ?? date.addingTimeInterval(60)
    }
}

private struct ReminderWindow {
    let startHour: Int
    let endHour: Int
}
