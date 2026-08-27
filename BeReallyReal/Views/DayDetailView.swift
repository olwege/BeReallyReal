//
//  DayDetailView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject var store: PhotoStore
    let date: Date
    let dayPhotos: [DailyPhoto]

    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(dayPhotos) { photo in
                        VStack {
                            ZStack(alignment: .topLeading) {
                                if let back = store.loadImage(filename: photo.backImageFilename) {
                                    Image(uiImage: back).resizable().scaledToFit()
                                }
                                if let front = store.loadImage(filename: photo.frontImageFilename) {
                                    Image(uiImage: front)
                                        .resizable().scaledToFill()
                                        .frame(width: 90, height: 126)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 3))
                                        .padding(10)
                                }
                            }
                            Text(photo.capturedAt, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                PhotoExporter.export(images: [store.loadImage(filename: photo.backImageFilename),
                                                               store.loadImage(filename: photo.frontImageFilename)].compactMap { $0 }) { success in
                                    exportMessage = success ? "Saved to Photos" : "Couldn't save"
                                }
                            } label: {
                                Label("Save this to Photos", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(Text(date, format: .dateTime.month().day().year()))
            .alert(exportMessage ?? "", isPresented: Binding(get: { exportMessage != nil }, set: { _ in exportMessage = nil })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
