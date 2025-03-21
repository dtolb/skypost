import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var shouldShowSquareOverlay = true
    @Published var errorMessage: String?
    @Published var isPortraitModeEnabled = false
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
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
    
    // Setup capture session
    func setupCaptureSession(in view: UIView) {
        captureSession = AVCaptureSession()
        
        // Find the back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "Could not find camera"
            return
        }
        
        // Set up dual camera if available (for portrait mode)
        if isPortraitModeEnabled {
            if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                do {
                    let input = try AVCaptureDeviceInput(device: dualCamera)
                    if captureSession!.canAddInput(input) {
                        captureSession!.addInput(input)
                    }
                } catch {
                    // Fall back to regular camera
                    setupRegularCamera(camera)
                }
            } else if let depthCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                // Try the dual wide camera as a fallback for newer devices
                do {
                    let input = try AVCaptureDeviceInput(device: depthCamera)
                    if captureSession!.canAddInput(input) {
                        captureSession!.addInput(input)
                    }
                } catch {
                    // Fall back to regular camera
                    setupRegularCamera(camera)
                }
            } else {
                // No dual camera, use regular camera
                setupRegularCamera(camera)
            }
        } else {
            // Using the regular camera for non-portrait mode
            setupRegularCamera(camera)
        }
        
        // Set up photo output
        videoOutput = AVCapturePhotoOutput()
        if let videoOutput = videoOutput, captureSession!.canAddOutput(videoOutput) {
            captureSession!.addOutput(videoOutput)
        }
        
        // Set up preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer!.videoGravity = .resizeAspectFill
        previewLayer!.frame = view.bounds
        view.layer.addSublayer(previewLayer!)
        
        // Start the session
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }
    
    private func setupRegularCamera(_ camera: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession!.canAddInput(input) {
                captureSession!.addInput(input)
            }
        } catch {
            errorMessage = "Could not set up camera: \(error.localizedDescription)"
        }
    }
    
    // Capture a photo
    func capturePhoto() {
        guard let videoOutput = videoOutput else { return }
        
        let settings = AVCapturePhotoSettings()
        
        // Configure portrait mode (depth effect) if enabled
        if isPortraitModeEnabled {
            if videoOutput.isDepthDataDeliverySupported {
                settings.isDepthDataDeliveryEnabled = true
                if videoOutput.isPortraitEffectsMatteDeliverySupported {
                    settings.isPortraitEffectsMatteDeliveryEnabled = true
                }
            } else {
                // Device doesn't support portrait mode
                errorMessage = "Portrait mode not available on this device"
            }
        }
        
        videoOutput.capturePhoto(with: settings, delegate: self)
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
    
    // Cleanup
    func stopCaptureSession() {
        captureSession?.stopRunning()
    }
}

// MARK: - Camera Delegate Implementation
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            errorMessage = "Error capturing photo: \(error.localizedDescription)"
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            errorMessage = "Could not convert photo to image"
            return
        }
        
        DispatchQueue.main.async {
            self.processImage(image)
        }
    }
}

// MARK: - Custom Camera View

struct CustomCameraView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        DispatchQueue.main.async {
            self.cameraManager.setupCaptureSession(in: view)
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed
    }
}

// MARK: - Camera Controls View

struct CameraControlsView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            Spacer()
            
            // Portrait mode indicator
            if cameraManager.isPortraitModeEnabled {
                Text("Portrait Mode")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            HStack {
                // Cancel button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                
                Spacer()
                
                // Capture button
                Button(action: {
                    cameraManager.capturePhoto()
                    // Dismiss after capturing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 70, height: 70)
                        .overlay(Circle().fill(Color.white).frame(width: 60, height: 60))
                }
                
                Spacer()
                
                // Square mode indicator
                if cameraManager.shouldShowSquareOverlay {
                    Image(systemName: "square")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Main Camera View

struct MainCameraView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            CustomCameraView(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
            
            // Optional square overlay for framing
            if cameraManager.shouldShowSquareOverlay {
                GeometryReader { geometry in
                    let minDimension = min(geometry.size.width, geometry.size.height)
                    let xOffset = (geometry.size.width - minDimension) / 2
                    let yOffset = (geometry.size.height - minDimension) / 2
                    
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: minDimension, height: minDimension)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            
            CameraControlsView(cameraManager: cameraManager)
            
            if let errorMessage = cameraManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .background(Color.black.opacity(0.7))
                    .padding()
                    .position(x: UIScreen.main.bounds.width / 2, y: 100)
            }
        }
        .onDisappear {
            cameraManager.stopCaptureSession()
        }
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
        
        // Enable camera controls
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

// MARK: - Main Camera View

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @ObservedObject var postViewModel: PostViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingImagePicker = false
    @State private var showingCustomCamera = false
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
                            // Use custom camera or image picker based on portrait mode setting
                            if cameraManager.isPortraitModeEnabled {
                                showingCustomCamera = true
                            } else {
                                showingImagePicker = true
                            }
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
                // Camera options when no image is captured
                VStack {
                    Text("Camera Options")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                    
                    // Square mode toggle
                    Toggle("Square Format", isOn: $cameraManager.shouldShowSquareOverlay)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    
                    // Portrait mode toggle
                    Toggle("Portrait Mode", isOn: $cameraManager.isPortraitModeEnabled)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    Button(action: {
                        checkCameraAccess()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
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
        .sheet(isPresented: $showingCustomCamera) {
            MainCameraView(cameraManager: cameraManager)
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
                // If portrait mode is enabled, use custom camera
                if cameraManager.isPortraitModeEnabled {
                    showingCustomCamera = true
                } else {
                    // Otherwise use standard image picker
                    showingImagePicker = true
                }
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
