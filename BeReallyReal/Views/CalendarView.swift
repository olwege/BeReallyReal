//
//  CalendarView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import Combine

struct CalendarView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var showingClearConfirm = false
    @State private var exportMessage: String?

    private func export(_ images: [UIImage]) {
        PhotoExporter.export(images: images) { success in
            exportMessage = success ? "Saved \(images.count) photo(s) to Photos" : "Couldn't save — check Photos permission"
        }
    }

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        NavigationStack {
            VStack {
                monthHeader
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        DayCell(date: date)
                            .environmentObject(store)
                            .onTapGesture {
                                if store.hasEntry(for: date) {
                                    selectedDate = date
                                }
                            }
                    }
                }
                .padding()
                Spacer()
            }
            .navigationTitle("BeReallyReal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Export this month") {
                            export(store.images(inMonthOf: displayedMonth))
                        }
                        Button("Export this year") {
                            export(store.images(inYearOf: displayedMonth))
                        }
                        Button("Export everything") {
                            export(store.allImages())
                        }
                        Divider()
                        Button("Clear all data", role: .destructive) {
                            showingClearConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete all photos? This can't be undone.", isPresented: $showingClearConfirm) {
                Button("Delete", role: .destructive) { store.deleteAll() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(exportMessage ?? "", isPresented: Binding(get: { exportMessage != nil }, set: { _ in exportMessage = nil })) {
                Button("OK", role: .cancel) {}
            }
            .sheet(item: Binding(
                get: { selectedDate.map { IdentifiableDate(date: $0) } },
                set: { selectedDate = $0?.date }
            )) { wrapped in
                DayDetailView(date: wrapped.date, dayPhotos: store.photos(for: wrapped.date))
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }
}

private struct IdentifiableDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct DayCell: View {
    @EnvironmentObject var store: PhotoStore
    let date: Date

    var body: some View {
        VStack {
            if let photo = store.photos(for: date).first, let img = store.loadImage(filename: photo.backImageFilename) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
            }
            Text(date, format: .dateTime.day())
                .font(.caption2)
        }
    }
}
