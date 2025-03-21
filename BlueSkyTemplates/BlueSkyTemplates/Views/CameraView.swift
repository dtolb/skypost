import SwiftUI
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

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView(postViewModel: PostViewModel())
    }
} 

