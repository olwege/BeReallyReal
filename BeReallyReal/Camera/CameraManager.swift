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
    @Published var isRunning = false
    @Published var isCapturing = false
    @Published var errorMessage: String?

    @Published private(set) var backZoom: Double = 1
    @Published private(set) var frontZoom: Double = 1
    @Published private(set) var backMinZoom: Double = 1
    @Published private(set) var frontMinZoom: Double = 1
    @Published private(set) var backMaxZoom: Double = 1
    @Published private(set) var frontMaxZoom: Double = 1

    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)

    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()

    private var backCompletion: ((UIImage?) -> Void)?
    private var frontCompletion: ((UIImage?) -> Void)?
    private var pendingCapture: (((UIImage?, UIImage?) -> Void))?

    private var backDevice: AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?

    var previewSession: AVCaptureMultiCamSession { session }

    func configure() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            errorMessage = "This device doesn't support simultaneous front/back capture."
            return
        }

        guard !isReady else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let backCamera = makeCameraInput(position: .back) else {
            errorMessage = "Could not configure back camera."
            return
        }

        backDevice = backCamera.device

        session.addInputWithNoConnections(backCamera.input)

        guard session.canAddOutput(backOutput) else {
            errorMessage = "Could not add back photo output."
            return
        }

        session.addOutputWithNoConnections(backOutput)

        guard let backPort = backCamera.input.ports(
            for: .video,
            sourceDeviceType: backCamera.device.deviceType,
            sourceDevicePosition: .back
        ).first else {
            errorMessage = "Could not connect back camera."
            return
        }

        let backConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)

        guard session.canAddConnection(backConnection) else {
            errorMessage = "Could not add back camera connection."
            return
        }

        session.addConnection(backConnection)

        guard let frontCamera = makeCameraInput(position: .front) else {
            errorMessage = "Could not configure front camera."
            return
        }

        frontDevice = frontCamera.device

        session.addInputWithNoConnections(frontCamera.input)

        guard session.canAddOutput(frontOutput) else {
            errorMessage = "Could not add front photo output."
            return
        }

        session.addOutputWithNoConnections(frontOutput)

        guard let frontPort = frontCamera.input.ports(
            for: .video,
            sourceDeviceType: frontCamera.device.deviceType,
            sourceDevicePosition: .front
        ).first else {
            errorMessage = "Could not connect front camera."
            return
        }

        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        frontConnection.automaticallyAdjustsVideoMirroring = false
        frontConnection.isVideoMirrored = true

        guard session.canAddConnection(frontConnection) else {
            errorMessage = "Could not add front camera connection."
            return
        }

        session.addConnection(frontConnection)

        updateZoomLimits(for: backCamera.device, isBackCamera: true)
        updateZoomLimits(for: frontCamera.device, isBackCamera: false)

        isReady = true
    }

    private func makeCameraInput(position: AVCaptureDevice.Position) -> (device: AVCaptureDevice, input: AVCaptureDeviceInput)? {
        for device in preferredVideoDevices(position: position) {
            guard let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                continue
            }

            return (device, input)
        }

        return nil
    }

    private func preferredVideoDevices(position: AVCaptureDevice.Position) -> [AVCaptureDevice] {
        let preferredTypes: [AVCaptureDevice.DeviceType]

        if position == .back {
            preferredTypes = [
                .builtInUltraWideCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
        } else {
            preferredTypes = [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera
            ]
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        )

        return preferredTypes.compactMap { type in
            discovery.devices.first { $0.deviceType == type }
        }
    }

    private func updateZoomLimits(for device: AVCaptureDevice, isBackCamera: Bool) {
        let minZoom = Double(device.minAvailableVideoZoomFactor)
        let maxZoom = min(Double(device.maxAvailableVideoZoomFactor), 8)
        let currentZoom = Double(device.videoZoomFactor)

        if isBackCamera {
            backMinZoom = minZoom
            backMaxZoom = max(maxZoom, minZoom)
            backZoom = min(max(currentZoom, backMinZoom), backMaxZoom)
            setBackZoom(backMinZoom)
        } else {
            frontMinZoom = minZoom
            frontMaxZoom = max(maxZoom, minZoom)
            frontZoom = min(max(currentZoom, frontMinZoom), frontMaxZoom)
            setFrontZoom(frontMinZoom)
        }
    }

    func setBackZoom(_ zoom: Double) {
        let clampedZoom = min(max(zoom, backMinZoom), backMaxZoom)
        backZoom = clampedZoom
        setZoomFactor(CGFloat(clampedZoom), for: backDevice)
    }

    func setFrontZoom(_ zoom: Double) {
        let clampedZoom = min(max(zoom, frontMinZoom), frontMaxZoom)
        frontZoom = clampedZoom
        setZoomFactor(CGFloat(clampedZoom), for: frontDevice)
    }

    func setBackZoom(scale: CGFloat, startingAt initialZoom: Double) {
        setBackZoom(initialZoom * Double(scale))
    }

    func setFrontZoom(scale: CGFloat, startingAt initialZoom: Double) {
        setFrontZoom(initialZoom * Double(scale))
    }

    private func setZoomFactor(_ zoomFactor: CGFloat, for device: AVCaptureDevice?) {
        guard let device else { return }

        do {
            try device.lockForConfiguration()

            let clampedZoom = min(
                max(zoomFactor, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )

            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Could not change camera zoom."
            }
        }
    }

    func start() {
        guard isReady else { return }
        guard !session.isRunning else {
            isRunning = true
            return
        }

        sessionQueue.async {
            self.session.startRunning()

            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning

                if self.session.isRunning,
                   let pendingCapture = self.pendingCapture {
                    self.pendingCapture = nil
                    self.capturePair(completion: pendingCapture)
                }
            }
        }
    }

    func stop() {
        pendingCapture = nil

        guard session.isRunning else {
            isRunning = false
            return
        }

        sessionQueue.async {
            self.session.stopRunning()

            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func capturePair(completion: @escaping (UIImage?, UIImage?) -> Void) {
        guard isReady else {
            completion(nil, nil)
            return
        }

        guard !isCapturing else {
            completion(nil, nil)
            return
        }

        guard session.isRunning else {
            pendingCapture = completion
            start()
            return
        }

        isCapturing = true

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
            self.isCapturing = false
            completion(back, front)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            if output === backOutput {
                backCompletion?(nil)
                backCompletion = nil
            } else {
                frontCompletion?(nil)
                frontCompletion = nil
            }

            return
        }

        if output === backOutput {
            backCompletion?(image)
            backCompletion = nil
        } else {
            frontCompletion?(image)
            frontCompletion = nil
        }
    }
}
