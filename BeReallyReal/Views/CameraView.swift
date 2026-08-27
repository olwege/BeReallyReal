//
//  CameraView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import AVFoundation
import Combine

struct CameraView: View {
    @EnvironmentObject var store: PhotoStore
    @StateObject private var camera = CameraManager()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            if camera.isReady {
                MultiCamPreview(session: camera.previewSession)
                    .ignoresSafeArea()
            } else if let error = camera.errorMessage {
                Text(error).foregroundColor(.white).padding()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                Spacer()
                Button {
                    camera.capturePair { back, front in
                        if let back, let front {
                            store.save(backImage: back, frontImage: front)
                            NotificationScheduler.scheduleNext()
                            dismiss()
                        }
                    }
                } label: {
                    Circle().fill(.white).frame(width: 72, height: 72)
                }
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
    }
}
