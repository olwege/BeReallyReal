//
//  DayDetailView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import UIKit
import CoreLocation
import MapKit

struct DayDetailView: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var photoPendingDeletion: DailyPhoto?
    @State private var showingFirstDeleteConfirmation = false
    @State private var showingSecondDeleteConfirmation = false
    @State private var photosWithFrontImageLarge: Set<DailyPhoto.ID> = []

    @State private var preparedShareItem: PreparedShareItem?
    @State private var isPreparingShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(store.photos(for: date)) { photo in
                        let frontImageIsLarge = photosWithFrontImageLarge.contains(photo.id)

                        VStack(alignment: .leading, spacing: 12) {
                            if let backImage = store.loadImage(filename: photo.backImageFilename),
                               let frontImage = store.loadImage(filename: photo.frontImageFilename) {
                                StoredPhotoPairView(
                                    backImage: backImage,
                                    frontImage: frontImage,
                                    frontImageIsLarge: frontImageIsLarge
                                ) {
                                    toggleLargePhoto(for: photo)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(photo.capturedAt, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let caption = photo.caption, !caption.isEmpty {
                                    Text(caption)
                                        .font(.body)
                                }

                                if let latitude = photo.latitude,
                                   let longitude = photo.longitude {
                                    LocationShareView(
                                        latitude: latitude,
                                        longitude: longitude
                                    )
                                }
                            }

                            HStack {
                                Button {
                                    prepareShareURL(for: photo, frontImageIsLarge: frontImageIsLarge)
                                } label: {
                                    if isPreparingShare {
                                        Label("Preparing", systemImage: "hourglass")
                                    } else {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isPreparingShare)

                                Button(role: .destructive) {
                                    requestDelete(photo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(date, format: .dateTime.month().day().year()))
            .sheet(item: $preparedShareItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .alert("Delete this photo?", isPresented: $showingFirstDeleteConfirmation) {
                Button("Continue", role: .destructive) {
                    showingSecondDeleteConfirmation = true
                }

                Button("Cancel", role: .cancel) {
                    photoPendingDeletion = nil
                }
            } message: {
                Text("This will permanently delete this memory from the app.")
            }
            .alert("Are you absolutely sure?", isPresented: $showingSecondDeleteConfirmation) {
                Button("Delete photo", role: .destructive) {
                    confirmDelete()
                }

                Button("Cancel", role: .cancel) {
                    photoPendingDeletion = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func toggleLargePhoto(for photo: DailyPhoto) {
        if photosWithFrontImageLarge.contains(photo.id) {
            photosWithFrontImageLarge.remove(photo.id)
        } else {
            photosWithFrontImageLarge.insert(photo.id)
        }
    }

    private func prepareShareURL(for photo: DailyPhoto, frontImageIsLarge: Bool) {
        guard !isPreparingShare else { return }

        isPreparingShare = true

        Task {
            let url = store.shareURL(for: photo, frontImageIsLarge: frontImageIsLarge)

            await MainActor.run {
                if let url {
                    preparedShareItem = PreparedShareItem(url: url)
                }

                isPreparingShare = false
            }
        }
    }

    private func requestDelete(_ photo: DailyPhoto) {
        photoPendingDeletion = photo
        showingFirstDeleteConfirmation = true
    }

    private func confirmDelete() {
        guard let photoPendingDeletion else { return }

        store.delete(photoPendingDeletion)
        photosWithFrontImageLarge.remove(photoPendingDeletion.id)
        self.photoPendingDeletion = nil

        if store.photos(for: date).isEmpty {
            dismiss()
        }
    }
}

private struct PreparedShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

private struct StoredPhotoPairView: View {
    let backImage: UIImage
    let frontImage: UIImage
    let frontImageIsLarge: Bool
    let toggle: () -> Void

    private var largeImage: UIImage {
        frontImageIsLarge ? frontImage : backImage
    }

    private var smallImage: UIImage {
        frontImageIsLarge ? backImage : frontImage
    }

    private var smallPhotoAccessibilityLabel: String {
        frontImageIsLarge ? "Show back camera photo large" : "Show front camera photo large"
    }

    var body: some View {
        Image(uiImage: largeImage)
            .resizable()
            .scaledToFit()
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let borderWidth = PhotoCompositionStyle.overlayBorderWidth(for: proxy.size)
                    let outerMargin = PhotoCompositionStyle.overlayMargin(for: proxy.size)
                    let overlayHeight = PhotoCompositionStyle.overlayHeight(for: proxy.size)
                    let overlayWidth = overlayHeight / PhotoCompositionStyle.previewAspectRatio
                    let cornerRadius = PhotoCompositionStyle.overlayCornerRadius(for: overlayWidth)

                    Button {
                        toggle()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius + borderWidth)
                                .fill(.black)
                                .frame(
                                    width: overlayWidth + borderWidth * 2,
                                    height: overlayHeight + borderWidth * 2
                                )

                            Image(uiImage: smallImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: overlayWidth, height: overlayHeight)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .clipped()
                        }
                        .frame(
                            width: overlayWidth + borderWidth * 2,
                            height: overlayHeight + borderWidth * 2
                        )
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius + borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(smallPhotoAccessibilityLabel)
                    .padding(outerMargin)
                }
            }
    }
}

private struct LocationShareView: View {
    let latitude: Double
    let longitude: Double

    @State private var locationName: String?
    @State private var showingMapOptions = false

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var fallbackLocationName: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private var displayName: String {
        locationName ?? fallbackLocationName
    }

    private var googleMapsAppURL: URL {
        URL(string: "comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)&zoom=16")!
    }

    private var googleMapsWebURL: URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(latitude),\(longitude)")
        ]
        return components.url!
    }

    private var organicMapsURL: URL {
        URL(string: "om://map?ll=\(latitude),\(longitude)&z=16")!
    }

    private var organicMapsLegacyURL: URL {
        URL(string: "mapsme://map?ll=\(latitude),\(longitude)&z=16")!
    }

    private var openStreetMapURL: URL {
        URL(string: "https://www.openstreetmap.org/?mlat=\(latitude)&mlon=\(longitude)#map=16/\(latitude)/\(longitude)")!
    }

    var body: some View {
        Button {
            showingMapOptions = true
        } label: {
            Label(displayName, systemImage: "location.fill")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingMapOptions) {
            LocationMapOptionsSheet(
                displayName: displayName,
                coordinateText: fallbackLocationName,
                coordinate: coordinate,
                googleMapsAppURL: googleMapsAppURL,
                googleMapsWebURL: googleMapsWebURL,
                organicMapsURL: organicMapsURL,
                organicMapsLegacyURL: organicMapsLegacyURL,
                openStreetMapURL: openStreetMapURL
            )
        }
        .accessibilityHint("Shows options for opening this location in a maps app.")
        .task(id: "\(latitude),\(longitude)") {
            await loadLocationName()
        }
    }

    private func loadLocationName() async {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let resolvedLocation = try await reverseGeocode(location)
            let city = resolvedLocation.city
            let country = resolvedLocation.country

            let resolvedName = [city, country]
                .compactMap { $0 }
                .removingAdjacentDuplicates()
                .joined(separator: ", ")

            guard !resolvedName.isEmpty else { return }

            await MainActor.run {
                locationName = resolvedName
            }
        } catch {
            await MainActor.run {
                locationName = fallbackLocationName
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> ResolvedLocation {
        if #available(iOS 26.0, *),
           let request = MKReverseGeocodingRequest(location: location) {
            let mapItems = try await request.mapItems
            let address = mapItems.first?.addressRepresentations

            return ResolvedLocation(
                city: address?.cityName,
                country: address?.regionName
            )
        }

        return ResolvedLocation(
            city: nil,
            country: nil
        )
    }
}

private struct LocationMapOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let displayName: String
    let coordinateText: String
    let coordinate: CLLocationCoordinate2D
    let googleMapsAppURL: URL
    let googleMapsWebURL: URL
    let organicMapsURL: URL
    let organicMapsLegacyURL: URL
    let openStreetMapURL: URL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LocationMapPreview(
                        coordinate: coordinate,
                        title: displayName
                    )
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    }

                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text(coordinateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    VStack(spacing: 10) {
                        Button {
                            dismiss()
                            openInAppleMaps()
                        } label: {
                            Label("Open in Apple Maps", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            dismiss()
                            openGoogleMaps()
                        } label: {
                            Label("Open in Google Maps", systemImage: "map.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            dismiss()
                            openOrganicMaps()
                        } label: {
                            Label("Open in Organic Maps", systemImage: "leaf.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            dismiss()
                            openURL(openStreetMapURL)
                        } label: {
                            Label("Open in OpenStreetMap", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            UIPasteboard.general.string = coordinateText
                        } label: {
                            Label("Copy Coordinates", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Open Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func openInAppleMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = displayName

        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(
                    latitudeDelta: 0.01,
                    longitudeDelta: 0.01
                )
            )
        ])
    }

    private func openGoogleMaps() {
        openURL(googleMapsAppURL) { accepted in
            if !accepted {
                openURL(googleMapsWebURL)
            }
        }
    }

    private func openOrganicMaps() {
        openURL(organicMapsURL) { accepted in
            if !accepted {
                openURL(organicMapsLegacyURL) { legacyAccepted in
                    if !legacyAccepted {
                        openURL(openStreetMapURL)
                    }
                }
            }
        }
    }
}

private struct LocationMapPreview: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let title: String

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = title
        mapView.addAnnotation(annotation)

        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: 0.01,
                longitudeDelta: 0.01
            )
        )

        mapView.setRegion(region, animated: false)
    }
}

private struct ResolvedLocation {
    let city: String?
    let country: String?
}

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        reduce(into: [String]()) { result, element in
            if result.last != element {
                result.append(element)
            }
        }
    }
}
