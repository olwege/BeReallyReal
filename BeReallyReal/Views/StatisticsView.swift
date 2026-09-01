//
//  StatisticsView.swift
//  BeReallyReal
//

import SwiftUI
import CoreLocation

struct StatisticsView: View {
    @EnvironmentObject private var store: PhotoStore

    @State private var selectedPeriod: StatisticsPeriod = .sinceFirstPhoto
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var displayedYear = Calendar.current.startOfDay(for: Date())

    @State private var resolvedLocations: [DailyPhoto.ID: StatisticsResolvedLocation] = [:]
    @State private var isResolvingLocations = false

    private let calendar = Calendar.current

    private var photos: [DailyPhoto] {
        store.photos
    }

    private var sortedPhotos: [DailyPhoto] {
        photos.sorted { $0.capturedAt < $1.capturedAt }
    }

    private var firstPhoto: DailyPhoto? {
        sortedPhotos.first
    }

    private var latestPhoto: DailyPhoto? {
        sortedPhotos.last
    }

    private var totalPhotoCount: Int {
        photos.count
    }

    private var uniquePhotoDays: [Date] {
        Array(Set(photos.map { calendar.startOfDay(for: $0.date) }))
            .sorted()
    }

    private var longestStreak: Int {
        longestDailyStreak(in: uniquePhotoDays)
    }

    private var selectedInterval: DateInterval? {
        switch selectedPeriod {
        case .month:
            return calendar.dateInterval(of: .month, for: displayedMonth)

        case .year:
            return calendar.dateInterval(of: .year, for: displayedYear)

        case .sinceFirstPhoto:
            guard let firstPhoto else { return nil }

            let start = calendar.startOfDay(for: firstPhoto.date)
            let lastRelevantDate = max(Date(), latestPhoto?.date ?? Date())

            guard let end = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: lastRelevantDate)
            ) else {
                return nil
            }

            return DateInterval(start: start, end: end)
        }
    }

    private var periodPhotos: [DailyPhoto] {
        guard let selectedInterval else { return [] }

        return photos.filter { photo in
            photo.capturedAt >= selectedInterval.start && photo.capturedAt < selectedInterval.end
        }
    }

    private var periodDaysWithPhotos: Int {
        Set(periodPhotos.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var periodTotalDays: Int {
        guard let selectedInterval else { return 0 }

        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: selectedInterval.start),
            to: calendar.startOfDay(for: selectedInterval.end)
        ).day ?? 0
    }

    private var periodCoverage: Double {
        guard periodTotalDays > 0 else { return 0 }
        return Double(periodDaysWithPhotos) / Double(periodTotalDays)
    }

    private var cityRankings: [StatisticsLocationRanking] {
        locationRankings(for: periodPhotos, keyPath: \.city)
    }

    private var countryRankings: [StatisticsLocationRanking] {
        locationRankings(for: periodPhotos, keyPath: \.country)
    }

    private var locationTaskID: String {
        store.photos
            .map { "\($0.id.uuidString)-\($0.latitude ?? 0)-\($0.longitude ?? 0)" }
            .joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Statistics will appear after you take your first photo.")
                )
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    globalStatsSection
                    periodSection
                    coverageSection
                    locationSection
                }
                .padding()
            }
        }
        .task(id: locationTaskID) {
            await resolveMissingLocations()
        }
    }

    private var globalStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Stats")
                .font(.title2.weight(.bold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                StatisticsMetricCard(
                    title: "Photos total",
                    value: "\(totalPhotoCount)",
                    systemImage: "photo.stack"
                )

                StatisticsMetricCard(
                    title: "Days with photos",
                    value: "\(uniquePhotoDays.count)",
                    systemImage: "calendar.badge.checkmark"
                )

                StatisticsMetricCard(
                    title: "First photo",
                    value: firstPhotoDateText,
                    systemImage: "calendar"
                )

                StatisticsMetricCard(
                    title: "Longest streak",
                    value: longestStreak == 1 ? "1 day" : "\(longestStreak) days",
                    systemImage: "flame"
                )
            }
        }
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Period")
                .font(.title2.weight(.bold))

            Picker("Period", selection: $selectedPeriod) {
                ForEach(StatisticsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)

            switch selectedPeriod {
            case .month:
                monthSelector

            case .year:
                yearSelector

            case .sinceFirstPhoto:
                Text(sinceFirstPhotoText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                shiftDisplayedMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            VStack(spacing: 2) {
                Text(displayedMonth, format: .dateTime.month(.wide))
                    .font(.headline)

                Text(displayedMonth, format: .dateTime.year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                shiftDisplayedMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var yearSelector: some View {
        HStack {
            Button {
                shiftDisplayedYear(-1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(displayedYear, format: .dateTime.year())
                .font(.headline)

            Spacer()

            Button {
                shiftDisplayedYear(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coverage")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(percentText(periodCoverage))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()

                    Spacer()

                    Text("\(periodDaysWithPhotos) / \(periodTotalDays) days")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: periodCoverage)
                    .tint(.accentColor)

                Text("Days with at least one photo divided by total days in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location Rankings")
                    .font(.title2.weight(.bold))

                Spacer()

                if isResolvingLocations {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            StatisticsRankingCard(
                title: "Cities",
                subtitle: "Share of photos in this period",
                rankings: cityRankings,
                emptyText: "No city data for this period."
            )

            StatisticsRankingCard(
                title: "Countries",
                subtitle: "Share of photos in this period",
                rankings: countryRankings,
                emptyText: "No country data for this period."
            )
        }
    }

    private var firstPhotoDateText: String {
        guard let firstPhoto else { return "—" }
        return firstPhoto.capturedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var sinceFirstPhotoText: String {
        guard let firstPhoto else {
            return "No photos yet."
        }

        return "From \(firstPhoto.capturedAt.formatted(date: .abbreviated, time: .omitted)) through today."
    }

    private func shiftDisplayedMonth(_ delta: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else {
            return
        }

        displayedMonth = startOfMonth(newDate)
    }

    private func shiftDisplayedYear(_ delta: Int) {
        guard let newDate = calendar.date(byAdding: .year, value: delta, to: displayedYear) else {
            return
        }

        displayedYear = startOfYear(newDate)
    }

    private func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func startOfYear(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func longestDailyStreak(in days: [Date]) -> Int {
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for index in days.indices.dropFirst() {
            let previousDay = days[days.index(before: index)]
            let day = days[index]

            let difference = calendar.dateComponents([.day], from: previousDay, to: day).day

            if difference == 1 {
                current += 1
            } else {
                current = 1
            }

            longest = max(longest, current)
        }

        return longest
    }

    private func locationRankings(
        for photos: [DailyPhoto],
        keyPath: KeyPath<StatisticsResolvedLocation, String?>
    ) -> [StatisticsLocationRanking] {
        guard !photos.isEmpty else { return [] }

        var counts: [String: Int] = [:]

        for photo in photos {
            let name: String

            if let resolvedLocation = resolvedLocations[photo.id],
               let resolvedName = resolvedLocation[keyPath: keyPath],
               !resolvedName.isEmpty {
                name = resolvedName
            } else if photo.latitude != nil, photo.longitude != nil {
                name = "Resolving"
            } else {
                name = "Unknown"
            }

            counts[name, default: 0] += 1
        }

        return counts
            .map { name, count in
                StatisticsLocationRanking(
                    name: name,
                    photoCount: count,
                    percentage: Double(count) / Double(photos.count)
                )
            }
            .sorted { first, second in
                if first.photoCount == second.photoCount {
                    return first.name < second.name
                }

                return first.photoCount > second.photoCount
            }
    }

    private func resolveMissingLocations() async {
        let photosNeedingResolution = store.photos.filter { photo in
            photo.latitude != nil &&
            photo.longitude != nil &&
            resolvedLocations[photo.id] == nil
        }

        guard !photosNeedingResolution.isEmpty else {
            return
        }

        isResolvingLocations = true

        for photo in photosNeedingResolution {
            guard let latitude = photo.latitude,
                  let longitude = photo.longitude else {
                continue
            }

            let location = CLLocation(latitude: latitude, longitude: longitude)
            let resolvedLocation = await reverseGeocode(location)

            resolvedLocations[photo.id] = resolvedLocation

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        isResolvingLocations = false
    }

    private func reverseGeocode(_ location: CLLocation) async -> StatisticsResolvedLocation {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let placemark = placemarks.first

            return StatisticsResolvedLocation(
                city: placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea,
                country: placemark?.country
            )
        } catch {
            return StatisticsResolvedLocation(city: nil, country: nil)
        }
    }

    private func percentText(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}

private enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case month
    case year
    case sinceFirstPhoto

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .month:
            "Month"
        case .year:
            "Year"
        case .sinceFirstPhoto:
            "Since First"
        }
    }
}

private struct StatisticsResolvedLocation {
    let city: String?
    let country: String?
}

private struct StatisticsLocationRanking: Identifiable {
    let name: String
    let photoCount: Int
    let percentage: Double

    var id: String {
        name
    }
}

private struct StatisticsMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)

            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct StatisticsRankingCard: View {
    let title: String
    let subtitle: String
    let rankings: [StatisticsLocationRanking]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if rankings.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(rankings) { ranking in
                        StatisticsRankingRow(ranking: ranking)
                    }
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct StatisticsRankingRow: View {
    let ranking: StatisticsLocationRanking

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(ranking.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(ranking.percentage.formatted(.percent.precision(.fractionLength(1))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                ProgressView(value: ranking.percentage)
                    .tint(.accentColor)

                Text("\(ranking.photoCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
    }
}
