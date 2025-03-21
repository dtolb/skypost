import Foundation
import UIKit
import PhotosUI
import AVFoundation
import SwiftUI

class PhotoService: NSObject, ObservableObject {
    @Published var selectedImages: [UIImage] = []
    @Published var selectedAspectRatio: CGFloat = 1.0 // Default to square
    @Published var isSquareEnabled: Bool = true
    
    // Camera authorization
    func requestCameraAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
    
    // Photos library authorization
    func requestPhotoLibraryAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status == .authorized || status == .limited)
                }
            }
        default:
            return false
        }
    }
    
    // Process selected photos for upload
    func processSelectedPhotos(_ images: [UIImage], isSquare: Bool = false) -> [PostMedia] {
        return images.map { image in
            if isSquare {
                return PostMedia(image: cropToSquare(image))
            } else {
                return PostMedia(image: image)
            }
        }
    }
    
    // Crop an image to a square aspect ratio
    func cropToSquare(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        let minDimension = min(originalSize.width, originalSize.height)
        let xOffset = (originalSize.width - minDimension) / 2
        let yOffset = (originalSize.height - minDimension) / 2
        
        let cropRect = CGRect(x: xOffset, y: yOffset, width: minDimension, height: minDimension)
        
        if let cgImage = image.cgImage?.cropping(to: cropRect) {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
        
        return image
    }
    
    // Resize image to a specified target size while maintaining aspect ratio
    func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        // Use the smaller ratio to ensure the image fits within the target size
        let scaleFactor = min(widthRatio, heightRatio)
        
        let scaledSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        
        let scaledImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
        
        return scaledImage
    }
} 
