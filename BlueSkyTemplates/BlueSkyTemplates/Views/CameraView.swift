import SwiftUI
import AVFoundation
import UIKit

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @ObservedObject var postViewModel: PostViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingImagePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Display captured image if available
            if let capturedImage = cameraManager.capturedImage {
                VStack {
                    // Image preview
                    Image(uiImage: capturedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    
                    // Action buttons
                    HStack(spacing: 40) {
                        Button(action: {
                            cameraManager.resetCapturedImage()
                            showingImagePicker = true
                        }) {
                            VStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 24))
                                Text("Retake")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(10)
                        }
                        
                        Button(action: {
                            useCapture()
                        }) {
                            VStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 24))
                                Text("Use Photo")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.bottom, 30)
                }
            } else {
                // Simple camera options when no image is captured
                VStack {
                    Text("Take Photo")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        checkCameraAccess()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Open Camera")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            CameraPickerView(cameraManager: cameraManager)
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Camera Access"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if alertMessage.contains("Settings") {
                        // Ideally would open settings but this is simplified
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            )
        }
    }
    
    private func checkCameraAccess() {
        cameraManager.checkCameraPermission { granted in
            if granted {
                showingImagePicker = true
            } else {
                alertMessage = "Camera access is required. Please enable it in Settings."
                showingAlert = true
            }
        }
    }
    
    private func useCapture() {
        guard let image = cameraManager.capturedImage else { return }
        
        // Create PostMedia from captured image
        let media = PostMedia(image: image)
        
        // Add it to the post view model
        postViewModel.addMedia([media])
        
        // Dismiss the camera view
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    
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
    
    // Process the captured image
    func processImage(_ image: UIImage) {
        capturedImage = image
    }
}

// MARK: - Camera Picker View

struct CameraPickerView: UIViewControllerRepresentable {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        
        // Enable camera controls - this will show the native iOS camera interface
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

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView(postViewModel: PostViewModel())
    }
}
