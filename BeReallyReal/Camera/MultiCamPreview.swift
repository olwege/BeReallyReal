//
//  MultiCamPreview.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import AVFoundation

struct MultiCamPreview: UIViewRepresentable {
    let session: AVCaptureMultiCamSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.configure(with: session)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}
}

final class PreviewContainerView: UIView {
    private var backLayer: AVCaptureVideoPreviewLayer?
    private var frontLayer: AVCaptureVideoPreviewLayer?

    func configure(with session: AVCaptureMultiCamSession) {
        // Full-screen back camera preview
        let back = AVCaptureVideoPreviewLayer()
        back.session = session
        back.videoGravity = .resizeAspectFill
        back.frame = bounds
        layer.addSublayer(back)
        backLayer = back

        // Small front camera preview, bottom-left corner (BeReal-style)
        let front = AVCaptureVideoPreviewLayer()
        front.session = session
        front.videoGravity = .resizeAspectFill
        front.frame = CGRect(x: 16, y: bounds.height - 216, width: 100, height: 140)
        front.cornerRadius = 12
        front.masksToBounds = true
        layer.addSublayer(front)
        frontLayer = front

        // Connect each preview layer to the correct camera port
        if let backConnection = session.connections.first(where: {
            $0.inputPorts.contains { $0.sourceDevicePosition == .back }
        }) {
            back.setSessionWithNoConnection(session)
            let backPreviewConnection = AVCaptureConnection(inputPort: backConnection.inputPorts[0], videoPreviewLayer: back)
            if session.canAddConnection(backPreviewConnection) {
                session.addConnection(backPreviewConnection)
            }
        }

        if let frontConnection = session.connections.first(where: {
            $0.inputPorts.contains { $0.sourceDevicePosition == .front }
        }) {
            front.setSessionWithNoConnection(session)
            let frontPreviewConnection = AVCaptureConnection(inputPort: frontConnection.inputPorts[0], videoPreviewLayer: front)
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
        frontLayer?.frame = CGRect(x: 16, y: bounds.height - 216, width: 100, height: 140)
    }
}
