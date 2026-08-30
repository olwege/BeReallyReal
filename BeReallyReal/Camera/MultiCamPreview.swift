//
//  MultiCamPreview.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import AVFoundation
import UIKit

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

    private var backZoomLabel: UILabel?
    private var frontZoomLabel: UILabel?

    private weak var backPinchGesture: UIPinchGestureRecognizer?
    private weak var frontPinchGesture: UIPinchGestureRecognizer?

    private var initialBackZoom: Double = 1
    private var initialFrontZoom: Double = 1

    private var backZoomHideWorkItem: DispatchWorkItem?
    private var frontZoomHideWorkItem: DispatchWorkItem?

    private let frontPreviewBorderWidth: CGFloat = 1.5
    private let frontPreviewAspectRatio: CGFloat = 1.4

    private let shutterButtonDiameter: CGFloat = 72
    private let shutterButtonBottomPadding: CGFloat = 40
    private let backZoomLabelHorizontalGapFromShutter: CGFloat = 14

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

        let frontLabel = makeZoomLabel()
        photoView.addSubview(frontLabel)
        frontZoomLabel = frontLabel

        let backLabel = makeZoomLabel()
        addSubview(backLabel)
        backZoomLabel = backLabel

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

        updateBackZoomLabelText()
        updateFrontZoomLabelText()

        setNeedsLayout()
    }

    func updateCamera(_ camera: CameraManager) {
        self.camera = camera
        updateBackZoomLabelText()
        updateFrontZoomLabelText()
    }

    private func makeZoomLabel() -> UILabel {
        let label = UILabel()
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        label.textAlignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.layer.cornerRadius = 15
        label.clipsToBounds = true
        label.isHidden = true
        label.alpha = 0
        label.isUserInteractionEnabled = false
        return label
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

        layoutBackZoomLabel()
        layoutFrontZoomLabel()

        if let backZoomLabel {
            bringSubviewToFront(backZoomLabel)
        }
    }

    private func layoutBackZoomLabel() {
        guard let backZoomLabel else { return }

        let width: CGFloat = 76
        let height: CGFloat = 34
        let horizontalInset: CGFloat = 16

        let shutterCenterX = bounds.midX
        let shutterCenterY = bounds.maxY
            - safeAreaInsets.bottom
            - shutterButtonBottomPadding
            - shutterButtonDiameter / 2

        let preferredX = shutterCenterX
            + shutterButtonDiameter / 2
            + backZoomLabelHorizontalGapFromShutter

        let fallbackX = shutterCenterX
            - shutterButtonDiameter / 2
            - backZoomLabelHorizontalGapFromShutter
            - width

        let x: CGFloat
        if preferredX + width <= bounds.maxX - horizontalInset {
            x = preferredX
        } else {
            x = max(horizontalInset, fallbackX)
        }

        backZoomLabel.frame = CGRect(
            x: x,
            y: shutterCenterY - height / 2,
            width: width,
            height: height
        )
    }

    private func layoutFrontZoomLabel() {
        guard let frontZoomLabel,
              let frontPhotoView else { return }

        let width = min(CGFloat(70), max(frontPhotoView.bounds.width - 16, 44))
        let height: CGFloat = 28

        frontZoomLabel.frame = CGRect(
            x: frontPhotoView.bounds.midX - width / 2,
            y: frontPhotoView.bounds.maxY - height - 8,
            width: width,
            height: height
        )
    }

    private func updateBackZoomLabelText() {
        guard let camera else { return }
        backZoomLabel?.text = String(format: "%.1fx", camera.backDisplayZoom)
    }

    private func updateFrontZoomLabelText() {
        guard let camera else { return }
        frontZoomLabel?.text = String(format: "%.1fx", camera.frontDisplayZoom)
    }

    private func showBackZoomLabel() {
        backZoomHideWorkItem?.cancel()
        updateBackZoomLabelText()
        showZoomLabel(backZoomLabel)
    }

    private func showFrontZoomLabel() {
        frontZoomHideWorkItem?.cancel()
        updateFrontZoomLabelText()
        showZoomLabel(frontZoomLabel)
    }

    private func hideBackZoomLabelAfterDelay() {
        backZoomHideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideZoomLabel(self?.backZoomLabel)
        }

        backZoomHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func hideFrontZoomLabelAfterDelay() {
        frontZoomHideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideZoomLabel(self?.frontZoomLabel)
        }

        frontZoomHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func showZoomLabel(_ label: UILabel?) {
        guard let label else { return }

        label.isHidden = false

        UIView.animate(withDuration: 0.12) {
            label.alpha = 1
        }
    }

    private func hideZoomLabel(_ label: UILabel?) {
        guard let label else { return }

        UIView.animate(withDuration: 0.2) {
            label.alpha = 0
        } completion: { _ in
            label.isHidden = true
        }
    }

    // MARK: - Pinch handling

    @objc private func handleBackPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let camera else { return }

        switch recognizer.state {
        case .began:
            initialBackZoom = camera.backZoom
            showBackZoomLabel()

        case .changed:
            camera.setBackZoom(scale: recognizer.scale, startingAt: initialBackZoom)
            showBackZoomLabel()

        case .ended, .cancelled, .failed:
            camera.setBackZoom(scale: recognizer.scale, startingAt: initialBackZoom)
            showBackZoomLabel()
            hideBackZoomLabelAfterDelay()

        default:
            break
        }
    }

    @objc private func handleFrontPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let camera else { return }

        switch recognizer.state {
        case .began:
            initialFrontZoom = camera.frontZoom
            showFrontZoomLabel()

        case .changed:
            camera.setFrontZoom(scale: recognizer.scale, startingAt: initialFrontZoom)
            showFrontZoomLabel()

        case .ended, .cancelled, .failed:
            camera.setFrontZoom(scale: recognizer.scale, startingAt: initialFrontZoom)
            showFrontZoomLabel()
            hideFrontZoomLabelAfterDelay()

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
