//
//  MultiCamPreview.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import AVFoundation

struct MultiCamPreview: UIViewRepresentable {
    let camera: CameraManager

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.configure(with: camera)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.updateCamera(camera)
    }
}

final class PreviewContainerView: UIView, UIGestureRecognizerDelegate {
    private weak var camera: CameraManager?

    private var backLayer: AVCaptureVideoPreviewLayer?
    private var frontLayer: AVCaptureVideoPreviewLayer?

    private var frontBorderView: UIView?
    private var frontPhotoView: UIView?

    private weak var backPinchGesture: UIPinchGestureRecognizer?
    private weak var frontPinchGesture: UIPinchGestureRecognizer?

    private var initialBackZoom: Double = 1
    private var initialFrontZoom: Double = 1

    // ‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑-
    // The front‑camera overlay has a border that used to be 2 pts wide.
    // Reduce it by 25 % → 2 × 0.75 = 1.5 pts.
    private let frontPreviewBorderWidth: CGFloat = 1.5
    // ‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑

    private let frontPreviewAspectRatio: CGFloat = 1.4

    private var frontPreviewSize: CGSize {
        let height = bounds.height * 0.3
        let width = height / frontPreviewAspectRatio
        return CGSize(width: width, height: height)
    }

    private var frontPreviewCornerRadius: CGFloat {
        frontPreviewSize.width * 0.08
    }

    func configure(with camera: CameraManager) {
        self.camera = camera

        backgroundColor = .black

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        subviews.forEach { $0.removeFromSuperview() }
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }

        let session = camera.previewSession

        // -------- BACK CAMERA ----------
        let back = AVCaptureVideoPreviewLayer()
        back.setSessionWithNoConnection(session)

        // Use .resizeAspectFill so the back preview fills the whole view (no black bars)
        back.videoGravity = .resizeAspectFill
        back.frame = bounds
        layer.addSublayer(back)
        backLayer = back

        // -------- FRONT CAMERA OVERLAY ----------
        let borderView = UIView()
        borderView.backgroundColor = .black
        borderView.isUserInteractionEnabled = false
        addSubview(borderView)
        frontBorderView = borderView

        let photoView = UIView()
        photoView.clipsToBounds = true
        photoView.backgroundColor = .black
        addSubview(photoView)
        frontPhotoView = photoView

        let front = AVCaptureVideoPreviewLayer()
        front.setSessionWithNoConnection(session)
        front.videoGravity = .resizeAspectFill
        photoView.layer.addSublayer(front)
        frontLayer = front

        // -------- GESTURES ----------
        let backPinch = UIPinchGestureRecognizer(target: self, action: #selector(handleBackPinch(_:)))
        backPinch.delegate = self
        addGestureRecognizer(backPinch)
        backPinchGesture = backPinch

        let frontPinch = UIPinchGestureRecognizer(target: self, action: #selector(handleFrontPinch(_:)))
        frontPinch.delegate = self
        photoView.addGestureRecognizer(frontPinch)
        frontPinchGesture = frontPinch

        connectPreviewLayers(to: session)

        setNeedsLayout()
    }

    func updateCamera(_ camera: CameraManager) {
        self.camera = camera
    }

    private func connectPreviewLayers(to session: AVCaptureMultiCamSession) {
        if let backLayer,
           let backConnection = session.connections.first(where: {
               $0.inputPorts.contains { $0.sourceDevicePosition == .back }
           }),
           let backPort = backConnection.inputPorts.first {
            let backPreviewConnection = AVCaptureConnection(
                inputPort: backPort,
                videoPreviewLayer: backLayer
            )
            if session.canAddConnection(backPreviewConnection) {
                session.addConnection(backPreviewConnection)
            }
        }

        if let frontLayer,
           let frontConnection = session.connections.first(where: {
               $0.inputPorts.contains { $0.sourceDevicePosition == .front }
           }),
           let frontPort = frontConnection.inputPorts.first {
            let frontPreviewConnection = AVCaptureConnection(
                inputPort: frontPort,
                videoPreviewLayer: frontLayer
            )
            frontPreviewConnection.automaticallyAdjustsVideoMirroring = false
            frontPreviewConnection.isVideoMirrored = true
            if session.canAddConnection(frontPreviewConnection) {
                session.addConnection(frontPreviewConnection)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backLayer?.frame = bounds

        let size = frontPreviewSize
        let photoFrame = CGRect(
            x: safeAreaInsets.left + 16,
            y: safeAreaInsets.top + 16,
            width: size.width,
            height: size.height
        )

        frontPhotoView?.frame = photoFrame
        frontPhotoView?.layer.cornerRadius = frontPreviewCornerRadius

        frontBorderView?.frame = photoFrame.insetBy(
            dx: -frontPreviewBorderWidth,
            dy: -frontPreviewBorderWidth
        )
        frontBorderView?.layer.cornerRadius = frontPreviewCornerRadius + frontPreviewBorderWidth

        if let frontPhotoView {
            frontLayer?.frame = frontPhotoView.bounds
        }
    }

    // MARK: - Pinch handling

    @objc private func handleBackPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let camera else { return }

        switch recognizer.state {
        case .began:
            initialBackZoom = camera.backZoom
        case .changed, .ended:
            camera.setBackZoom(scale: recognizer.scale, startingAt: initialBackZoom)
        default:
            break
        }
    }

    @objc private func handleFrontPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let camera else { return }

        switch recognizer.state {
        case .began:
            initialFrontZoom = camera.frontZoom
        case .changed, .ended:
            camera.setFrontZoom(scale: recognizer.scale, startingAt: initialFrontZoom)
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === backPinchGesture,
           let frontPhotoView,
           frontPhotoView.frame.contains(touch.location(in: self)) {
            return false
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
