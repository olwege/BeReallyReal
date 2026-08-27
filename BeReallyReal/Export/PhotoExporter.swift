//
//  Untitled.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import Photos
import UIKit

enum PhotoExporter {
    static func requestAddOnlyPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                completion(status == .authorized || status == .limited)
            }
        }
    }

    static func export(images: [UIImage], completion: @escaping (Bool) -> Void) {
        guard !images.isEmpty else { completion(false); return }
        requestAddOnlyPermission { granted in
            guard granted else { completion(false); return }
            PHPhotoLibrary.shared().performChanges {
                images.forEach { PHAssetChangeRequest.creationRequestForAsset(from: $0) }
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
        }
    }
}
