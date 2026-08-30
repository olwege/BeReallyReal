// PhotoMapView.swift

import SwiftUI
import MapKit
import UIKit

struct PhotoMapView: View {
    @EnvironmentObject private var store: PhotoStore
    @Binding var selectedDate: Date?

    @State private var recenterRequest = 0
    @State private var selectedLocationGroup: PhotoLocationGroup?
    @State private var mappedPhotos: [MappedPhoto] = []

    private var mappedPhotosTaskID: String {
        store.photos
            .map { "\($0.id.uuidString)-\($0.backImageFilename)-\($0.frontImageFilename)" }
            .joined(separator: "|")
    }

    private var locationGroups: [PhotoLocationGroup] {
        PhotoLocationGrouper.groups(from: mappedPhotos)
    }

    var body: some View {
        Group {
            if locationGroups.isEmpty {
                ContentUnavailableView(
                    "No mapped photos yet",
                    systemImage: "map",
                    description: Text("Photos saved with a location will appear here.")
                )
                .padding()
            } else {
                ClusteredPhotoMapView(
                    locationGroups: locationGroups,
                    selectedLocationGroup: $selectedLocationGroup,
                    recenterRequest: recenterRequest
                )
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            recenterRequest += 1
                        } label: {
                            Label("Recenter", systemImage: "location.viewfinder")
                        }
                    }
                }
            }
        }
        .task(id: mappedPhotosTaskID) {
            mappedPhotos = await loadMappedPhotos()
        }
        .sheet(item: $selectedLocationGroup) { group in
            LocationPhotosSheet(
                locationGroup: group,
                selectedDate: $selectedDate
            )
            .environmentObject(store)
        }
    }

    private func loadMappedPhotos() async -> [MappedPhoto] {
        var result: [MappedPhoto] = []

        for photo in store.photos {
            guard let latitude = photo.latitude,
                  let longitude = photo.longitude else {
                continue
            }

            let coordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )

            guard CLLocationCoordinate2DIsValid(coordinate) else {
                continue
            }

            let thumbnail = await store.thumbnail(for: photo)

            result.append(
                MappedPhoto(
                    photo: photo,
                    coordinate: coordinate,
                    thumbnail: thumbnail
                )
            )
        }

        return result.sorted { $0.photo.capturedAt > $1.photo.capturedAt }
    }
}

private struct ClusteredPhotoMapView: UIViewRepresentable {
    let locationGroups: [PhotoLocationGroup]
    @Binding var selectedLocationGroup: PhotoLocationGroup?
    let recenterRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedLocationGroup: $selectedLocationGroup)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.register(
            PhotoLocationAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: PhotoLocationAnnotationView.reuseIdentifier
        )
        mapView.register(
            PhotoClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: PhotoClusterAnnotationView.reuseIdentifier
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.selectedLocationGroup = $selectedLocationGroup
        context.coordinator.updateAnnotations(on: mapView, with: locationGroups)

        if !context.coordinator.didPositionInitialMap {
            setVisibleRegion(for: locationGroups, on: mapView, animated: false)
            context.coordinator.didPositionInitialMap = true
            context.coordinator.lastRecenterRequest = recenterRequest
        } else if context.coordinator.lastRecenterRequest != recenterRequest {
            setVisibleRegion(for: locationGroups, on: mapView, animated: true)
            context.coordinator.lastRecenterRequest = recenterRequest
        }
    }

    private func setVisibleRegion(
        for groups: [PhotoLocationGroup],
        on mapView: MKMapView,
        animated: Bool
    ) {
        guard let first = groups.first else {
            return
        }

        if groups.count == 1 {
            let region = MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            mapView.setRegion(region, animated: animated)
            return
        }

        let mapRect = groups.reduce(MKMapRect.null) { partialResult, group in
            let point = MKMapPoint(group.coordinate)
            let rect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            return partialResult.union(rect)
        }

        guard !mapRect.isNull else {
            return
        }

        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: UIEdgeInsets(top: 80, left: 60, bottom: 80, right: 60),
            animated: animated
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var selectedLocationGroup: Binding<PhotoLocationGroup?>
        var didPositionInitialMap = false
        var lastRecenterRequest = 0

        private var annotationSignature: [String] = []

        init(selectedLocationGroup: Binding<PhotoLocationGroup?>) {
            self.selectedLocationGroup = selectedLocationGroup
        }

        func updateAnnotations(on mapView: MKMapView, with locationGroups: [PhotoLocationGroup]) {
            let newSignature = locationGroups.map(\.signature)

            guard newSignature != annotationSignature else {
                return
            }

            let existingPhotoAnnotations = mapView.annotations.compactMap { annotation in
                annotation as? PhotoLocationAnnotation
            }

            mapView.removeAnnotations(existingPhotoAnnotations)

            let newAnnotations = locationGroups.map(PhotoLocationAnnotation.init)
            mapView.addAnnotations(newAnnotations)

            annotationSignature = newSignature
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let clusterAnnotation = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PhotoClusterAnnotationView.reuseIdentifier,
                    for: clusterAnnotation
                ) as? PhotoClusterAnnotationView

                view?.configure(with: clusterAnnotation)
                return view
            }

            if let photoLocationAnnotation = annotation as? PhotoLocationAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PhotoLocationAnnotationView.reuseIdentifier,
                    for: photoLocationAnnotation
                ) as? PhotoLocationAnnotationView

                view?.configure(with: photoLocationAnnotation)
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let photoLocationAnnotation = annotation as? PhotoLocationAnnotation {
                selectedLocationGroup.wrappedValue = photoLocationAnnotation.locationGroup
                mapView.deselectAnnotation(annotation, animated: true)
                return
            }

            if let clusterAnnotation = annotation as? MKClusterAnnotation {
                zoomIn(on: clusterAnnotation, mapView: mapView)
                mapView.deselectAnnotation(annotation, animated: true)
            }
        }

        private func zoomIn(
            on clusterAnnotation: MKClusterAnnotation,
            mapView: MKMapView
        ) {
            let memberAnnotations = clusterAnnotation.memberAnnotations

            let mapRect = memberAnnotations.reduce(MKMapRect.null) { partialResult, annotation in
                let point = MKMapPoint(annotation.coordinate)
                let rect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                return partialResult.union(rect)
            }

            if mapRect.isNull || mapRect.width <= 1 || mapRect.height <= 1 {
                let currentSpan = mapView.region.span
                let region = MKCoordinateRegion(
                    center: clusterAnnotation.coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(currentSpan.latitudeDelta / 2, 0.002),
                        longitudeDelta: max(currentSpan.longitudeDelta / 2, 0.002)
                    )
                )
                mapView.setRegion(region, animated: true)
            } else {
                mapView.setVisibleMapRect(
                    mapRect,
                    edgePadding: UIEdgeInsets(top: 80, left: 60, bottom: 80, right: 60),
                    animated: true
                )
            }
        }
    }
}

private struct LocationPhotosSheet: View {
    @EnvironmentObject private var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    let locationGroup: PhotoLocationGroup
    @Binding var selectedDate: Date?

    private var title: String {
        locationGroup.photos.count == 1
            ? "1 Photo Here"
            : "\(locationGroup.photos.count) Photos Here"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(locationGroup.photos) { mappedPhoto in
                        LocationPhotoCard(mappedPhoto: mappedPhoto) {
                            selectedDate = mappedPhoto.photo.date
                            dismiss()
                        }
                        .environmentObject(store)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
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
}

private struct LocationPhotoCard: View {
    @EnvironmentObject private var store: PhotoStore

    let mappedPhoto: MappedPhoto
    let openDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = mappedPhoto.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1 / PhotoCompositionStyle.previewAspectRatio, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mappedPhoto.photo.capturedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.headline)

                Text(mappedPhoto.photo.capturedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let caption = mappedPhoto.photo.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .padding(.top, 4)
                }
            }

            Button {
                openDay()
            } label: {
                Label("Open day", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private enum PhotoLocationGrouper {
    private static let groupingDistanceInMeters: CLLocationDistance = 100

    static func groups(from photos: [MappedPhoto]) -> [PhotoLocationGroup] {
        var groups: [PhotoLocationGroup] = []

        for photo in photos {
            if let existingIndex = groups.firstIndex(where: { group in
                group.coordinate.distance(to: photo.coordinate) <= groupingDistanceInMeters
            }) {
                groups[existingIndex].append(photo)
            } else {
                groups.append(PhotoLocationGroup(photos: [photo]))
            }
        }

        return groups.sorted { first, second in
            first.latestCapturedAt > second.latestCapturedAt
        }
    }
}

private struct PhotoLocationGroup: Identifiable {
    private(set) var photos: [MappedPhoto]

    var id: String {
        photos
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "-")
    }

    var coordinate: CLLocationCoordinate2D {
        guard !photos.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        let latitude = photos.map(\.coordinate.latitude).reduce(0, +) / Double(photos.count)
        let longitude = photos.map(\.coordinate.longitude).reduce(0, +) / Double(photos.count)

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var latestCapturedAt: Date {
        photos.map(\.photo.capturedAt).max() ?? .distantPast
    }

    var thumbnail: UIImage? {
        photos
            .sorted { $0.photo.capturedAt > $1.photo.capturedAt }
            .first?
            .thumbnail
    }

    var signature: String {
        let photoIDs = photos
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: ",")

        return "\(id):\(coordinate.latitude):\(coordinate.longitude):\(photoIDs)"
    }

    mutating func append(_ photo: MappedPhoto) {
        photos.append(photo)
        photos.sort { $0.photo.capturedAt > $1.photo.capturedAt }
    }
}

private struct MappedPhoto: Identifiable {
    let photo: DailyPhoto
    let coordinate: CLLocationCoordinate2D
    let thumbnail: UIImage?

    var id: DailyPhoto.ID {
        photo.id
    }
}

private extension CLLocationCoordinate2D {
    func distance(to otherCoordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: otherCoordinate.latitude, longitude: otherCoordinate.longitude))
    }
}

private final class PhotoLocationAnnotation: NSObject, MKAnnotation {
    let locationGroup: PhotoLocationGroup
    let coordinate: CLLocationCoordinate2D

    init(locationGroup: PhotoLocationGroup) {
        self.locationGroup = locationGroup
        self.coordinate = locationGroup.coordinate
    }
}

private final class PhotoLocationAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PhotoLocationAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        canShowCallout = false
        clusteringIdentifier = "photo-location"
        collisionMode = .circle
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with annotation: PhotoLocationAnnotation) {
        let count = annotation.locationGroup.photos.count > 1
            ? annotation.locationGroup.photos.count
            : nil

        let markerImage = PhotoMapMarkerRenderer.makeMarkerImage(
            thumbnail: annotation.locationGroup.thumbnail,
            count: count,
            tintColor: tintColor
        )

        image = markerImage
        centerOffset = CGPoint(x: 0, y: -markerImage.size.height / 2)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        image = nil
    }
}

private final class PhotoClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PhotoClusterAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        canShowCallout = false
        collisionMode = .circle
        displayPriority = .required
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with clusterAnnotation: MKClusterAnnotation) {
        let locationAnnotations = clusterAnnotation.memberAnnotations.compactMap {
            $0 as? PhotoLocationAnnotation
        }

        let totalPhotoCount = locationAnnotations.reduce(0) { partialResult, annotation in
            partialResult + annotation.locationGroup.photos.count
        }

        let thumbnail = locationAnnotations
            .sorted { $0.locationGroup.latestCapturedAt > $1.locationGroup.latestCapturedAt }
            .first?
            .locationGroup
            .thumbnail

        let markerImage = PhotoMapMarkerRenderer.makeMarkerImage(
            thumbnail: thumbnail,
            count: max(totalPhotoCount, clusterAnnotation.memberAnnotations.count),
            tintColor: tintColor
        )

        image = markerImage
        centerOffset = CGPoint(x: 0, y: -markerImage.size.height / 2)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        image = nil
    }
}

private enum PhotoMapMarkerRenderer {
    static func makeMarkerImage(
        thumbnail: UIImage?,
        count: Int?,
        tintColor: UIColor
    ) -> UIImage {
        let size = CGSize(width: 70, height: 78)
        let circleRect = CGRect(x: 8, y: 3, width: 54, height: 54)
        let imageRect = circleRect.insetBy(dx: 4, dy: 4)
        let triangleTip = CGPoint(x: size.width / 2, y: size.height - 3)

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext

            cgContext.setShadow(
                offset: CGSize(width: 0, height: 3),
                blur: 6,
                color: UIColor.black.withAlphaComponent(0.25).cgColor
            )

            let circlePath = UIBezierPath(ovalIn: circleRect)
            UIColor.systemBackground.setFill()
            circlePath.fill()

            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            if let thumbnail {
                cgContext.saveGState()
                UIBezierPath(ovalIn: imageRect).addClip()
                thumbnail.draw(in: aspectFillRect(for: thumbnail.size, inside: imageRect))
                cgContext.restoreGState()
            } else {
                UIColor.secondarySystemFill.setFill()
                UIBezierPath(ovalIn: imageRect).fill()

                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
                let symbol = UIImage(systemName: "camera.fill", withConfiguration: symbolConfig)?
                    .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)

                if let symbol {
                    let symbolSize = symbol.size
                    let symbolRect = CGRect(
                        x: imageRect.midX - symbolSize.width / 2,
                        y: imageRect.midY - symbolSize.height / 2,
                        width: symbolSize.width,
                        height: symbolSize.height
                    )
                    symbol.draw(in: symbolRect)
                }
            }

            tintColor.setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()

            let trianglePath = UIBezierPath()
            trianglePath.move(to: CGPoint(x: size.width / 2 - 8, y: 55))
            trianglePath.addLine(to: CGPoint(x: size.width / 2 + 8, y: 55))
            trianglePath.addLine(to: triangleTip)
            trianglePath.close()

            tintColor.setFill()
            trianglePath.fill()

            if let count {
                drawCountBadge(count, in: size, tintColor: tintColor)
            }
        }
    }

    private static func aspectFillRect(
        for imageSize: CGSize,
        inside bounds: CGRect
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let imageAspectRatio = imageSize.width / imageSize.height
        let boundsAspectRatio = bounds.width / bounds.height

        if imageAspectRatio > boundsAspectRatio {
            let height = bounds.height
            let width = height * imageAspectRatio

            return CGRect(
                x: bounds.midX - width / 2,
                y: bounds.minY,
                width: width,
                height: height
            )
        } else {
            let width = bounds.width
            let height = width / imageAspectRatio

            return CGRect(
                x: bounds.minX,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    private static func drawCountBadge(
        _ count: Int,
        in markerSize: CGSize,
        tintColor: UIColor
    ) {
        let text = count > 99 ? "99+" : "\(count)"
        let badgeWidth: CGFloat = count > 99 ? 32 : 25
        let badgeRect = CGRect(x: 68 - badgeWidth, y: 0, width: badgeWidth, height: 22)
        let badgePath = UIBezierPath(
            roundedRect: badgeRect,
            cornerRadius: badgeRect.height / 2
        )

        UIColor.black.withAlphaComponent(0.75).setFill()
        badgePath.fill()

        tintColor.setStroke()
        badgePath.lineWidth = 2
        badgePath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.white
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
    }
}
