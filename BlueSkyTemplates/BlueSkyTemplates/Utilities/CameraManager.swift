import Foundation
import AVFoundation
import UIKit
import SwiftUI

// A simplified camera manager that uses UIImagePickerController
class CameraManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var shouldShowSquareOverlay = true
    @Published var errorMessage: String?

    // Function to check camera permissions
    func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    // Reset captured image
    func resetCapturedImage() {
        capturedImage = nil
    }
    
    // Process the captured image (like cropping to square if needed)
    func processImage(_ image: UIImage) {
        if shouldShowSquareOverlay {
            capturedImage = cropToSquare(image)
        } else {
            capturedImage = image
        }
    }
    
    // Crop an image to square
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
}

// View that wraps UIImagePickerController for camera access
struct CameraPickerView: UIViewControllerRepresentable {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        
        // Enable camera controls including zoom and portrait mode
        picker.showsCameraControls = true
        picker.allowsEditing = false
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.cameraManager.processImage(image)
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Preview for SwiftUI
extension CameraManager {
    static var preview: CameraManager {
        let manager = CameraManager()
        manager.capturedImage = UIImage(systemName: "photo")
        return manager
    }
} 
