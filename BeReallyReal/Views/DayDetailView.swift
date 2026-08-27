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
                                if let shareURL = store.shareURL(for: photo, frontImageIsLarge: frontImageIsLarge) {
                                    ShareLink(item: shareURL) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                }

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

    private var mapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]
        return components.url!
    }

    private var fallbackLocationName: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var body: some View {
        ShareLink(item: mapsURL) {
            Label(locationName ?? fallbackLocationName, systemImage: "location.fill")
                .font(.caption)
        }
        .accessibilityHint("Shows sharing options so you can choose a maps app.")
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
