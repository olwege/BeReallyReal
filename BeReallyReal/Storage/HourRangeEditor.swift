//
//  HourRangeEditor.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI

struct HourRangeEditor: View {
    let title: String

    @Binding var startHour: Int
    @Binding var endHour: Int

    private var startSelection: Binding<Int> {
        Binding {
            startHour
        } set: { newValue in
            startHour = min(max(newValue, 0), 23)

            if startHour >= endHour {
                endHour = min(startHour + 1, 24)
            }
        }
    }

    private var endSelection: Binding<Int> {
        Binding {
            endHour
        } set: { newValue in
            endHour = min(max(newValue, 1), 24)

            if endHour <= startHour {
                startHour = max(endHour - 1, 0)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker(selection: startSelection) {
                ForEach(0..<endHour, id: \.self) { hour in
                    Text(formattedHour(hour))
                        .tag(hour)
                }
            } label: {
                Label("Start", systemImage: "sunrise")
            }

            Picker(selection: endSelection) {
                ForEach((startHour + 1)...24, id: \.self) { hour in
                    Text(formattedHour(hour))
                        .tag(hour)
                }
            } label: {
                Label("End", systemImage: "sunset")
            }
        }
        .padding(.vertical, 6)
        .onAppear(perform: normalizeRange)
        .onChange(of: startHour) {
            normalizeRange()
        }
        .onChange(of: endHour) {
            normalizeRange()
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Text("\(formattedHour(startHour)) - \(formattedHour(endHour))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func normalizeRange() {
        startHour = min(max(startHour, 0), 23)
        endHour = min(max(endHour, 1), 24)

        if startHour >= endHour {
            if endHour < 24 {
                endHour = startHour + 1
            } else {
                startHour = endHour - 1
            }
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        if hour == 24 {
            return "24:00"
        }

        return String(format: "%02d:00", hour)
    }
}
