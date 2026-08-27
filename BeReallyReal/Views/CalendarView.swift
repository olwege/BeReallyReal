//
//  CalendarView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    @State private var photoPendingDeletion: DailyPhoto?
    @State private var showingFirstPhotoDeleteConfirmation = false
    @State private var showingSecondPhotoDeleteConfirmation = false

    @State private var showingFirstClearConfirm = false
    @State private var showingSecondClearConfirm = false
    @State private var showingTypedClearConfirm = false
    @State private var clearConfirmationText = ""

    @State private var showingSettings = false

    @State private var monthDays: [CalendarDayItem] = []

    private let gridColumnSpacing: CGFloat = 10
    private let gridHorizontalPadding: CGFloat = 16

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground),
                        Color(.secondarySystemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                GeometryReader { proxy in
                    let cellWidth = gridCellWidth(for: proxy.size.width)
                    let columns = Array(
                        repeating: GridItem(.fixed(cellWidth), spacing: gridColumnSpacing),
                    count: 7
                )

                    ScrollView {
                        VStack(spacing: 18) {
                            monthHeader
                                .padding(.top, 8)

                            weekdayHeader(cellWidth: cellWidth)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(monthDays) { item in
                                    DayCell(date: item.date, cellWidth: cellWidth)
                                        .environmentObject(store)
                                        .onTapGesture {
                                            guard let date = item.date else { return }
                                            if store.hasEntry(for: date) {
                                                selectedDate = date
                                            }
                                        }
                                        .contextMenu {
                                            if let date = item.date {
                                                ForEach(store.photos(for: date)) { photo in
                                                    Button(role: .destructive) {
                                                        requestDelete(photo)
                                                    } label: {
                                                        Label(
                                                            "Delete \(photo.capturedAt.formatted(date: .omitted, time: .shortened))",
                                                            systemImage: "trash"
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, gridHorizontalPadding)

                            Spacer(minLength: 24)
                        }
                    }
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        goToToday()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }

                        Divider()

                        ShareLink(items: store.shareURLs(inMonthOf: displayedMonth)) {
                            Label("Share this month", systemImage: "square.and.arrow.up")
                        }

                        ShareLink(items: store.shareURLs(inYearOf: displayedMonth)) {
                            Label("Share this year", systemImage: "square.and.arrow.up")
                        }

                        ShareLink(items: store.allShareURLs()) {
                            Label("Share everything", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button("Clear all data", role: .destructive) {
                            showingFirstClearConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete this photo?", isPresented: $showingFirstPhotoDeleteConfirmation) {
                Button("Continue", role: .destructive) {
                    showingSecondPhotoDeleteConfirmation = true
                }

                Button("Cancel", role: .cancel) {
                    photoPendingDeletion = nil
                }
            } message: {
                Text("This will permanently delete this memory from the app.")
            }
            .alert("Are you absolutely sure?", isPresented: $showingSecondPhotoDeleteConfirmation) {
                Button("Delete photo", role: .destructive) {
                    confirmDeletePhoto()
                }

                Button("Cancel", role: .cancel) {
                    photoPendingDeletion = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Delete all photos?", isPresented: $showingFirstClearConfirm) {
                Button("Continue", role: .destructive) {
                    showingSecondClearConfirm = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete every memory stored in the app.")
            }
            .alert("Are you absolutely sure?", isPresented: $showingSecondClearConfirm) {
                Button("Continue", role: .destructive) {
                    clearConfirmationText = ""
                    showingTypedClearConfirm = true
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("There is no undo. You will need to type a confirmation phrase next.")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView {
                    showingSettings = false
                }
            }
            .sheet(isPresented: $showingTypedClearConfirm) {
                ClearAllConfirmationView(
                    confirmationText: $clearConfirmationText,
                    cancel: {
                        clearConfirmationText = ""
                        showingTypedClearConfirm = false
                    },
                    delete: {
                        store.deleteAll()
                        clearConfirmationText = ""
                        showingTypedClearConfirm = false
                    }
                )
            }
            .sheet(item: Binding(
                get: { selectedDate.map { IdentifiableDate(date: $0) } },
                set: { selectedDate = $0?.date }
            )) { wrapped in
                DayDetailView(date: wrapped.date)
                    .environmentObject(store)
            }
        }
        .onAppear {
            monthDays = CalendarView.generateDays(for: displayedMonth)
        }
        .onChange(of: displayedMonth) {
            monthDays = CalendarView.generateDays(for: displayedMonth)
        }
    }

    // MARK: Header Views

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }

            VStack(spacing: 2) {
                Text(displayedMonth, format: .dateTime.month(.wide))
                    .font(.title2.weight(.bold))

                Text(displayedMonth, format: .dateTime.year())
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }

    private func weekdayHeader(cellWidth: CGFloat) -> some View {
        HStack(spacing: gridColumnSpacing) {
            ForEach(weekdaySymbols(), id: \.self) { symbol in
                Text(symbol.prefix(1))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: cellWidth)
            }
        }
        .padding(.horizontal, gridHorizontalPadding)
    }

    // MARK: Helper Actions

    private func goToToday() {
        displayedMonth = Date()
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func weekdaySymbols() -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private func gridCellWidth(for availableWidth: CGFloat) -> CGFloat {
        let totalHorizontalPadding = gridHorizontalPadding * 2
        let totalSpacing = gridColumnSpacing * 6
        let usableWidth = availableWidth - totalHorizontalPadding - totalSpacing
        return max(floor(usableWidth / 7), 1)
    }

    // MARK: Day-generation

    private static let sharedCalendar = Calendar.current

    private static let dayKeyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt
    }()

    private static func generateDays(for month: Date) -> [CalendarDayItem] {
        let calendar = sharedCalendar

        guard
            let range = calendar.range(of: .day, in: .month, for: month),
            let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7

        var items: [CalendarDayItem] = (0..<leadingEmptyDays).map {
            CalendarDayItem(id: "empty-\($0)", date: nil)
        }

        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let id = dayKeyFormatter.string(from: date)
            items.append(CalendarDayItem(id: id, date: date))
        }

        return items
    }

    // MARK: Delete workflow

    private func requestDelete(_ photo: DailyPhoto) {
        photoPendingDeletion = photo
        showingFirstPhotoDeleteConfirmation = true
    }

    private func confirmDeletePhoto() {
        guard let photoPendingDeletion else { return }
        store.delete(photoPendingDeletion)
        self.photoPendingDeletion = nil
    }
}

private struct DayCell: View {
    @EnvironmentObject var store: PhotoStore

    let date: Date?
    let cellWidth: CGFloat

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Group {
            if let date {
                let photos = store.photos(for: date)
                let hasPhotos = !photos.isEmpty
                let isToday = Calendar.current.isDateInToday(date)

                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(hasPhotos ? Color.clear : Color(.secondarySystemGroupedBackground))

                        if let img = thumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: cellWidth, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .clipped()
                        }
                    }
                    .frame(width: cellWidth, height: 58)
                    .overlay(alignment: .topTrailing) {
                        if photos.count > 1 {
                            Text("\(photos.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.65))
                                .clipShape(Capsule())
                                .padding(4)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isToday ? Color.accentColor : Color.black.opacity(0.06),
                                lineWidth: 2
                            )
                    }

                    Text(date, format: .dateTime.day())
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundColor(isToday ? .accentColor : .secondary)
                        .frame(width: cellWidth)
                }
                .frame(width: cellWidth, height: 82)
                .contentShape(Rectangle())
                .task(id: photos.first?.id) {
                    guard let first = photos.first else {
                        thumbnail = nil
                        return
                    }

                    if let thumb = await store.thumbnail(for: first) {
                        thumbnail = thumb
                    }
                }
            } else {
                Color.clear
                    .frame(width: cellWidth, height: 82)
            }
        }
    }
}

private struct CalendarDayItem: Identifiable {
    let id: String
    let date: Date?
}

private struct ClearAllConfirmationView: View {
    @Binding var confirmationText: String

    let cancel: () -> Void
    let delete: () -> Void

    private let requiredPhrase = "delete all memories"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("To permanently delete all photos, type:")
                    Text(requiredPhrase)
                        .font(.headline)
                        .textSelection(.enabled)

                    TextField("Confirmation phrase", text: $confirmationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("This removes every stored memory from the app and cannot be undone.")
                }
            }
            .navigationTitle("Final Confirmation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete All", role: .destructive) {
                        delete()
                    }
                    .disabled(confirmationText != requiredPhrase)
                }
            }
        }
    }
}

private struct IdentifiableDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
