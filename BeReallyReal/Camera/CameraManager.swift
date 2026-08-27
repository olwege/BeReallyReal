//
//  CameraManager.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import AVFoundation
import UIKit
import Combine

final class CameraManager: NSObject, ObservableObject {
    @Published var backImage: UIImage?
    @Published var frontImage: UIImage?
    @Published var isReady = false
    @Published var errorMessage: String?

    private let session = AVCaptureMultiCamSession()
    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()
    private var backCompletion: ((UIImage?) -> Void)?
    private var frontCompletion: ((UIImage?) -> Void)?

    var previewSession: AVCaptureMultiCamSession { session }

    func configure() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            errorMessage = "This device doesn't support simultaneous front/back capture."
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        do {
            // Back camera
            guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let backInput = try? AVCaptureDeviceInput(device: backDevice),
                  session.canAddInput(backInput) else {
                errorMessage = "Could not configure back camera."
                return
            }
            session.addInputWithNoConnections(backInput)

            guard session.canAddOutput(backOutput) else { return }
            session.addOutputWithNoConnections(backOutput)

            guard let backPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first else { return }
            let backConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
            guard session.canAddConnection(backConnection) else { return }
            session.addConnection(backConnection)

            // Front camera
            guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let frontInput = try? AVCaptureDeviceInput(device: frontDevice),
                  session.canAddInput(frontInput) else {
                errorMessage = "Could not configure front camera."
                return
            }
            session.addInputWithNoConnections(frontInput)

            guard session.canAddOutput(frontOutput) else { return }
            session.addOutputWithNoConnections(frontOutput)

            guard let frontPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first else { return }
            let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
            frontConnection.automaticallyAdjustsVideoMirroring = false
            frontConnection.isVideoMirrored = true
            guard session.canAddConnection(frontConnection) else { return }
            session.addConnection(frontConnection)

            isReady = true
        }
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func capturePair(completion: @escaping (UIImage?, UIImage?) -> Void) {
        var back: UIImage?
        var front: UIImage?
        let group = DispatchGroup()

        group.enter()
        backCompletion = { image in
            back = image
            group.leave()
        }
        backOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)

        group.enter()
        frontCompletion = { image in
            front = image
            group.leave()
        }
        frontOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)

        group.notify(queue: .main) {
            completion(back, front)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            if output === backOutput { backCompletion?(nil) } else { frontCompletion?(nil) }
            return
        }
        if output === backOutput {
            backCompletion?(image)
        } else {
            frontCompletion?(image)
        }
    }
}
