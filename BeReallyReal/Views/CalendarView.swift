//
//  CalendarView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import UIKit

struct CalendarView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var selectedSection: CalendarSection = .calendar
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date?

    @State private var photoPendingDeletion: DailyPhoto?
    @State private var showingFirstPhotoDeleteConfirmation = false
    @State private var showingSecondPhotoDeleteConfirmation = false

    @State private var showingFirstClearConfirm = false
    @State private var showingSecondClearConfirm = false
    @State private var showingTypedClearConfirm = false
    @State private var clearConfirmationText = ""

    @State private var showingSettings = false
    @State private var showingMonthYearPicker = false

    @State private var preparedBulkShareItem: PreparedBulkShareItem?
    @State private var isPreparingBulkShare = false

    private let gridColumnSpacing: CGFloat = 6
    private let gridHorizontalPadding: CGFloat = 10

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

                Group {
                    switch selectedSection {
                    case .calendar:
                        calendarContent

                    case .yearsAgo:
                        YearsAgoView(selectedDate: $selectedDate)
                            .environmentObject(store)

                    case .timeFeed:
                        TimeFeedView(selectedDate: $selectedDate)
                            .environmentObject(store)

                    case .map:
                        PhotoMapView(selectedDate: $selectedDate)
                            .environmentObject(store)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(CalendarSection.allCases) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                Label(section.title, systemImage: section.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedSection.title)
                                .font(.headline)

                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Choose Calendar view")
                }

                ToolbarItem(placement: .topBarLeading) {
                    if selectedSection == .calendar {
                        Button("Today") {
                            goToToday()
                        }
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

                        Button {
                            prepareBulkShare(.month(displayedMonth))
                        } label: {
                            Label(
                                isPreparingBulkShare ? "Preparing Share" : "Share this month",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(isPreparingBulkShare)

                        Button {
                            prepareBulkShare(.year(displayedMonth))
                        } label: {
                            Label(
                                isPreparingBulkShare ? "Preparing Share" : "Share this year",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(isPreparingBulkShare)

                        Button {
                            prepareBulkShare(.all)
                        } label: {
                            Label(
                                isPreparingBulkShare ? "Preparing Share" : "Share everything",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(isPreparingBulkShare)

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
            .sheet(isPresented: $showingMonthYearPicker) {
                MonthYearPickerView(
                    displayedMonth: Binding(
                        get: {
                            displayedMonth
                        },
                        set: { newMonth in
                            jumpToMonth(newMonth)
                        }
                    )
                )
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
            .sheet(item: $preparedBulkShareItem) { item in
                CalendarActivityView(activityItems: item.urls)
            }
            .sheet(item: Binding(
                get: { selectedDate.map { IdentifiableDate(date: $0) } },
                set: { selectedDate = $0?.date }
            )) { wrapped in
                DayDetailView(date: wrapped.date)
                    .environmentObject(store)
            }
        }
    }

    private var calendarContent: some View {
        GeometryReader { proxy in
            let cellWidth = gridCellWidth(for: proxy.size.width)
            let columns = Array(
                repeating: GridItem(.fixed(cellWidth), spacing: gridColumnSpacing),
                count: 7
            )

            VStack(spacing: 0) {
                monthHeader
                    .padding(.top, 8)

                ScrollView {
                    MonthGridSection(
                        month: displayedMonth,
                        cellWidth: cellWidth,
                        columns: columns,
                        weekdaySymbols: weekdaySymbols(),
                        gridColumnSpacing: gridColumnSpacing,
                        gridHorizontalPadding: gridHorizontalPadding,
                        selectedDate: $selectedDate,
                        requestDelete: { photo in
                            requestDelete(photo)
                        }
                    )
                    .environmentObject(store)
                    .padding(.vertical, 8)
                }
            }
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

            Button {
                showingMonthYearPicker = true
            } label: {
                VStack(spacing: 2) {
                    Text(displayedMonth, format: .dateTime.month(.wide))
                        .font(.title2.weight(.bold))

                    HStack(spacing: 4) {
                        Text(displayedMonth, format: .dateTime.year())
                            .font(.caption.weight(.medium))

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose month and year")

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

    // MARK: Helper Actions

    private func goToToday() {
        jumpToMonth(Date())
    }

    private func shiftMonth(_ delta: Int) {
        guard let newDate = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) else {
            return
        }

        jumpToMonth(newDate)
    }

    private func jumpToMonth(_ month: Date) {
        displayedMonth = startOfMonth(month)
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
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

    private enum BulkShareScope {
        case month(Date)
        case year(Date)
        case all
    }

    private func prepareBulkShare(_ scope: BulkShareScope) {
        guard !isPreparingBulkShare else { return }

        isPreparingBulkShare = true

        Task {
            let urls: [URL]

            switch scope {
            case .month(let date):
                urls = store.shareURLs(inMonthOf: date)

            case .year(let date):
                urls = store.shareURLs(inYearOf: date)

            case .all:
                urls = store.allShareURLs()
            }

            await MainActor.run {
                if !urls.isEmpty {
                    preparedBulkShareItem = PreparedBulkShareItem(urls: urls)
                }

                isPreparingBulkShare = false
            }
        }
    }

    // MARK: Day-generation

    private static let sharedCalendar = Calendar.current

    private static let monthIDFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt
    }()

    fileprivate static func generateDays(for month: Date) -> [CalendarDayItem] {
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

private struct MonthGridSection: View {
    @EnvironmentObject var store: PhotoStore

    let month: Date
    let cellWidth: CGFloat
    let columns: [GridItem]
    let weekdaySymbols: [String]
    let gridColumnSpacing: CGFloat
    let gridHorizontalPadding: CGFloat
    @Binding var selectedDate: Date?

    let requestDelete: (DailyPhoto) -> Void

    private var monthDays: [CalendarDayItem] {
        CalendarView.generateDays(for: month)
    }

    var body: some View {
        VStack(spacing: 8) {
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 8) {
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
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: gridColumnSpacing) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.prefix(1))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: cellWidth)
            }
        }
        .padding(.horizontal, gridHorizontalPadding)
    }
}

private enum CalendarSection: String, CaseIterable, Identifiable {
    case calendar
    case yearsAgo
    case timeFeed
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            "Calendar"
        case .yearsAgo:
            "Years ago"
        case .timeFeed:
            "Time Feed"
        case .map:
            "Map"
        }
    }

    var systemImage: String {
        switch self {
        case .calendar:
            "calendar"
        case .yearsAgo:
            "clock.arrow.circlepath"
        case .timeFeed:
            "rectangle.grid.2x2"
        case .map:
            "map"
        }
    }
}

private struct MonthYearPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var displayedMonth: Date

    @State private var selectedMonth: Int
    @State private var selectedYear: Int

    private let calendar = Calendar.current

    private var monthSymbols: [String] {
        calendar.monthSymbols
    }

    private var yearRange: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 50)...(currentYear + 10))
    }

    init(displayedMonth: Binding<Date>) {
        _displayedMonth = displayedMonth

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth.wrappedValue)

        _selectedMonth = State(initialValue: components.month ?? calendar.component(.month, from: Date()))
        _selectedYear = State(initialValue: components.year ?? calendar.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthSymbols[month - 1])
                                .tag(month)
                        }
                    }

                    Picker("Year", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { year in
                            Text(String(year))
                                .tag(year)
                        }
                    }
                }

                Section {
                    Button {
                        let today = Date()
                        selectedMonth = calendar.component(.month, from: today)
                        selectedYear = calendar.component(.year, from: today)
                    } label: {
                        Label("Jump to current month", systemImage: "calendar")
                    }
                }
            }
            .navigationTitle("Choose Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applySelection()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applySelection() {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1

        if let date = calendar.date(from: components) {
            displayedMonth = date
        }
    }
}

private struct YearsAgoView: View {
    @EnvironmentObject var store: PhotoStore
    @Binding var selectedDate: Date?

    @State private var selectedYearsAgo = 1

    private var yearsAgoPhoto: DailyPhoto? {
        let calendar = Calendar.current
        let now = Date()

        guard let targetDate = calendar.date(byAdding: .year, value: -selectedYearsAgo, to: now),
              let lowerBound = calendar.date(byAdding: .day, value: -14, to: targetDate),
              let upperBound = calendar.date(byAdding: .day, value: 14, to: targetDate)
        else {
            return nil
        }

        return store.photos
            .filter { photo in
                photo.capturedAt >= lowerBound && photo.capturedAt <= upperBound
            }
            .min { first, second in
                abs(first.capturedAt.timeIntervalSince(targetDate)) < abs(second.capturedAt.timeIntervalSince(targetDate))
            }
    }

    private var yearsAgoText: String {
        selectedYearsAgo == 1 ? "1 year ago" : "\(selectedYearsAgo) years ago"
    }

    private var noMemoryText: String {
        selectedYearsAgo == 1
            ? "no memory from a year ago :("
            : "no memory from \(selectedYearsAgo) years ago :("
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Stepper(value: $selectedYearsAgo, in: 1...50) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show memory from")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(yearsAgoText)
                            .font(.headline)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                if let photo = yearsAgoPhoto {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Closest memory from \(yearsAgoText)")
                            .font(.headline)

                        PhotoFeedCard(photo: photo, imageMode: .fullResolution)
                            .environmentObject(store)
                            .onTapGesture {
                                selectedDate = photo.date
                            }

                        Text(photo.capturedAt, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.body)
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                } else {
                    ContentUnavailableView(
                        noMemoryText,
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Nothing was found within two weeks of this day \(yearsAgoText).")
                    )
                    .padding(.top, 48)
                }
            }
            .padding()
        }
    }
}

private struct TimeFeedView: View {
    @EnvironmentObject var store: PhotoStore
    @Binding var selectedDate: Date?

    private var sortedPhotos: [DailyPhoto] {
        store.photos.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let horizontalPadding: CGFloat = 16
            let columnWidth = max((proxy.size.width - horizontalPadding * 2 - spacing) / 2, 1)

            let columns = [
                GridItem(.fixed(columnWidth), spacing: spacing),
                GridItem(.fixed(columnWidth), spacing: spacing)
            ]

            ScrollView {
                if sortedPhotos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Your time feed will appear here after you take photos.")
                    )
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedPhotos) { photo in
                            PhotoFeedCard(photo: photo, imageMode: .thumbnail(.medium))
                                .environmentObject(store)
                                .onTapGesture {
                                    selectedDate = photo.date
                                }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

private enum PhotoFeedCardImageMode {
    case thumbnail(PhotoThumbnailSize)
    case fullResolution
}

private struct PhotoFeedCard: View {
    @EnvironmentObject var store: PhotoStore

    let photo: DailyPhoto
    let imageMode: PhotoFeedCardImageMode

    @State private var image: UIImage?

    private let imageCornerRadius: CGFloat = 16
    private let cardPadding: CGFloat = 6

    init(
        photo: DailyPhoto,
        imageMode: PhotoFeedCardImageMode = .thumbnail(.small)
    ) {
        self.photo = photo
        self.imageMode = imageMode
    }

    private var taskID: String {
        switch imageMode {
        case .thumbnail(let size):
            "\(photo.id.uuidString)-thumbnail-\(size.rawValue)"
        case .fullResolution:
            "\(photo.id.uuidString)-full"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
            } else {
                RoundedRectangle(cornerRadius: imageCornerRadius)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1 / PhotoCompositionStyle.previewAspectRatio, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(photo.capturedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(photo.capturedAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(cardPadding)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .task(id: taskID) {
            switch imageMode {
            case .thumbnail(let size):
                image = await store.thumbnail(for: photo, size: size)

            case .fullResolution:
                image = store.combinedImage(for: photo)
            }
        }
    }
}

private struct DayCell: View {
    @EnvironmentObject var store: PhotoStore

    let date: Date?
    let cellWidth: CGFloat

    @State private var thumbnail: UIImage? = nil

    private var photoHeight: CGFloat {
        cellWidth
    }

    private var dayLabelHeight: CGFloat {
        14
    }

    var body: some View {
        Group {
            if let date {
                let photos = store.photos(for: date)
                let hasPhotos = !photos.isEmpty
                let isToday = Calendar.current.isDateInToday(date)

                VStack(spacing: 2) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))

                        if let img = thumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: cellWidth, height: photoHeight, alignment: .top)
                                .clipped()
                        }
                    }
                    .frame(width: cellWidth, height: photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if photos.count > 1 {
                            Text("\(photos.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.65))
                                .clipShape(Capsule())
                                .padding(3)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isToday ? Color.accentColor : Color.black.opacity(0.06),
                                lineWidth: 2
                            )
                    }

                    Text(date, format: .dateTime.day())
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(isToday ? .accentColor : .secondary)
                        .frame(width: cellWidth, height: dayLabelHeight, alignment: .top)
                }
                .frame(width: cellWidth, height: photoHeight + dayLabelHeight + 2, alignment: .top)
                .contentShape(Rectangle())
                .opacity(hasPhotos ? 1 : 0.55)
                .task(id: photos.first?.id) {
                    guard let first = photos.first else {
                        thumbnail = nil
                        return
                    }

                    thumbnail = await store.thumbnail(for: first)
                }
            } else {
                Color.clear
                    .frame(width: cellWidth, height: photoHeight + dayLabelHeight + 2)
            }
        }
    }
}

fileprivate struct CalendarDayItem: Identifiable {
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

private struct PreparedBulkShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct CalendarActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
