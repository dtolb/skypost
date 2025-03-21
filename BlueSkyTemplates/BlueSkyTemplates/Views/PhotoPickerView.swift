import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @ObservedObject var postViewModel: PostViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @StateObject private var photoService = PhotoService()
    @State private var showPhotoPicker = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Select Photos")
                            .font(.title)
                            .bold()
                            .padding(.horizontal)
                        
                        // Preview of selected photos
                        if !photoService.selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(photoService.selectedImages.indices, id: \.self) { index in
                                        VStack {
                                            Image(uiImage: photoService.selectedImages[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 150, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.gray, lineWidth: 1)
                                                )
                                            
                                            Button(action: {
                                                photoService.selectedImages.remove(at: index)
                                            }) {
                                                Text("Remove")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 180)
                        }
                        
                        // Square crop option
                        Toggle("Crop to Square", isOn: $photoService.isSquareEnabled)
                            .padding(.horizontal)
                        
                        // Photo library button
                        Button(action: {
                            showPhotoPicker = true
                        }) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Choose from Photo Library")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                
                // Bottom buttons
                VStack {
                    Button(action: {
                        addSelectedPhotos()
                    }) {
                        Text("Use Selected Photos")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(photoService.selectedImages.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                    .disabled(photoService.selectedImages.isEmpty)
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .navigationBarTitle("Photo Library", displayMode: .inline)
            .navigationBarHidden(true)
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedItems,
                maxSelectionCount: 4,
                matching: .images
            )
            .onChange(of: selectedItems) { oldValue, newValue in
                processSelectedPhotos()
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .overlay(
                Group {
                    if isLoading {
                        ZStack {
                            Color.black.opacity(0.4)
                                .edgesIgnoringSafeArea(.all)
                            ProgressView()
                                .scaleEffect(2)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                }
            )
        }
        .onAppear {
            checkPhotoLibraryPermission()
        }
    }
    
    private func checkPhotoLibraryPermission() {
        Task {
            let isAuthorized = await photoService.requestPhotoLibraryAuthorization()
            
            if !isAuthorized {
                await MainActor.run {
                    alertMessage = "This app needs photo library access to select images. Please enable it in Settings."
                    showingAlert = true
                }
            }
        }
    }
    
    private func processSelectedPhotos() {
        guard !selectedItems.isEmpty else { return }
        
        isLoading = true
        
        Task {
            photoService.selectedImages = [] // Clear existing
            
            for item in selectedItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        photoService.selectedImages.append(uiImage)
                    }
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func addSelectedPhotos() {
        guard !photoService.selectedImages.isEmpty else { return }
        
        // Process the images (square crop if enabled)
        let mediaItems = photoService.processSelectedPhotos(
            photoService.selectedImages,
            isSquare: photoService.isSquareEnabled
        )
        
        // Add them to the post view model
        postViewModel.addMedia(mediaItems)
        
        // Dismiss this view
        presentationMode.wrappedValue.dismiss()
    }
}

struct PhotoPickerView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoPickerView(postViewModel: PostViewModel())
    }
} 