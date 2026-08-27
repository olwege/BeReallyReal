//
//  CameraView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import AVFoundation
import Combine
import CoreLocation
import UIKit

struct CameraView: View {
    @EnvironmentObject var store: PhotoStore
    @StateObject private var camera = CameraManager()
    @StateObject private var locationProvider = LocationProvider()

    @Environment(\.dismiss) var dismiss
    @AppStorage("includeLocationByDefault") private var includeLocationByDefault = true

    @State private var capturedBackImage: UIImage?
    @State private var capturedFrontImage: UIImage?
    @State private var showingCaptionSheet = false

    var body: some View {
        ZStack {
            if camera.isReady {
                MultiCamPreview(camera: camera)
                    .ignoresSafeArea()
            } else if let error = camera.errorMessage {
                Text(error)
                    .foregroundColor(.white)
                    .padding()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .padding()
                }

                Spacer()

                Button {
                    camera.capturePair { back, front in
                        if let back, let front {
                            capturedBackImage = back
                            capturedFrontImage = front
                            showingCaptionSheet = true
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle()
                                    .stroke(.black.opacity(0.25), lineWidth: 2)
                            )

                        if camera.isCapturing {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                }
                .disabled(!camera.isRunning || camera.isCapturing)
                .opacity(camera.isRunning && !camera.isCapturing ? 1 : 0.55)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            camera.configure()
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $showingCaptionSheet) {
            if let capturedBackImage, let capturedFrontImage {
                CaptionAfterCaptureView(
                    backImage: capturedBackImage,
                    frontImage: capturedFrontImage,
                    includeLocationByDefault: $includeLocationByDefault,
                    save: { caption, shouldIncludeLocation in
                        Task {
                            let coordinate = shouldIncludeLocation
                                ? await locationProvider.requestCurrentCoordinate()
                                : nil

                            await MainActor.run {
                                store.save(
                                    backImage: capturedBackImage,
                                    frontImage: capturedFrontImage,
                                    caption: caption,
                                    location: coordinate
                                )
                                NotificationScheduler.scheduleNext()
                                dismiss()
                            }
                        }
                    },
                    retake: {
                        self.capturedBackImage = nil
                        self.capturedFrontImage = nil
                        showingCaptionSheet = false
                    }
                )
            }
        }
    }
}

private struct CaptionAfterCaptureView: View {
    let backImage: UIImage
    let frontImage: UIImage
    @Binding var includeLocationByDefault: Bool

    let save: (_ caption: String, _ shouldIncludeLocation: Bool) -> Void
    let retake: () -> Void

    @State private var caption = ""
    @FocusState private var captionIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: backImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    GeometryReader { proxy in
                        let overlayHeight = max(proxy.size.height * 0.3, 1)
                        let overlayWidth = overlayHeight / 1.4
                        let borderWidth: CGFloat = 2
                        let cornerRadius = overlayWidth * 0.08

                        Image(uiImage: frontImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: overlayWidth, height: overlayHeight)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .padding(borderWidth)
                            .background(
                                RoundedRectangle(cornerRadius: cornerRadius + borderWidth)
                                    .fill(Color.black)
                            )
                            .padding(12)
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))

                    TextEditor(text: $caption)
                        .focused($captionIsFocused)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                    if caption.isEmpty {
                        Text("Add a caption")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 88, maxHeight: 132)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    captionIsFocused = true
                }

                Toggle("Add location", isOn: $includeLocationByDefault)

                Spacer()
            }
            .padding()
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake") {
                        retake()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(caption, includeLocationByDefault)
                    }
                }
            }
        }
    }
}
