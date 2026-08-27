//
//  ReminderTimeWindowSettingsView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI

struct SettingsView: View {
    private let defaultWeekdayStart = 6
    private let defaultWeekdayEnd = 22
    private let defaultWeekendStart = 8
    private let defaultWeekendEnd = 24

    @AppStorage("includeLocationByDefault") private var includeLocationByDefault = true
    @AppStorage("weekdayReminderStartHour") private var weekdayStartHour = 6
    @AppStorage("weekdayReminderEndHour") private var weekdayEndHour = 22
    @AppStorage("weekendReminderStartHour") private var weekendStartHour = 8
    @AppStorage("weekendReminderEndHour") private var weekendEndHour = 24

    let done: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $includeLocationByDefault) {
                        Label("Add location by default", systemImage: "map")
                    }
                }

                Section {
                    HourRangeEditor(
                        title: "Weekdays",
                        startHour: $weekdayStartHour,
                        endHour: $weekdayEndHour
                    )

                    HourRangeEditor(
                        title: "Weekends",
                        startHour: $weekendStartHour,
                        endHour: $weekendEndHour
                    )
                } footer: {
                    Text("A reminder will be scheduled at a random time inside the selected window.")
                }

                Section {
                    Button(role: .destructive) {
                        restoreDefaults()
                    } label: {
                        Label("Restore Default Times", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        normalizeHours()
                        NotificationScheduler.scheduleNext()
                        done()
                    }
                }
            }
            .onAppear {
                normalizeHours()
            }
            .onDisappear {
                normalizeHours()
                NotificationScheduler.scheduleNext()
            }
        }
    }

    private func normalizeHours() {
        weekdayStartHour = min(max(weekdayStartHour, 0), 23)
        weekdayEndHour = min(max(weekdayEndHour, 1), 24)

        if weekdayStartHour >= weekdayEndHour {
            weekdayStartHour = defaultWeekdayStart
            weekdayEndHour = defaultWeekdayEnd
        }

        weekendStartHour = min(max(weekendStartHour, 0), 23)
        weekendEndHour = min(max(weekendEndHour, 1), 24)

        if weekendStartHour >= weekendEndHour {
            weekendStartHour = defaultWeekendStart
            weekendEndHour = defaultWeekendEnd
        }
    }

    private func restoreDefaults() {
        weekdayStartHour = defaultWeekdayStart
        weekdayEndHour = defaultWeekdayEnd
        weekendStartHour = defaultWeekendStart
        weekendEndHour = defaultWeekendEnd
    }
}
