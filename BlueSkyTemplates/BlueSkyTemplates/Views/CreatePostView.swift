import SwiftUI

struct CreatePostView: View {
    @ObservedObject var postViewModel: PostViewModel
    @ObservedObject var authViewModel: AuthViewModel
    
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showTemplates = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var showLoginSheet = false
    
    var body: some View {
        NavigationView {
            Form {
                // Text input section
                postTextSection
                
                // Template section
                templateSection
                
                // Media section
                mediaSection
                
                // Post button section
                postButtonSection
                
                // Error section
                if let error = postViewModel.postError {
                    errorSection(error)
                }
            }
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .onAppear {
                checkTemplates()
            }
            .sheet(isPresented: $showCamera) {
                CameraView(postViewModel: postViewModel)
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView(postViewModel: postViewModel)
            }
            .sheet(isPresented: $showTemplates) {
                templateSheetContent
            }
            .sheet(isPresented: $showLoginSheet) {
                loginSheetContent
            }
            .alert("Post Successful", isPresented: $showSuccessAlert) {
                Button("OK") {
                    resetPost()
                }
            } message: {
                Text("Your post has been published to BlueSky.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(postViewModel.postError ?? "An unknown error occurred.")
            }
            .onChange(of: postViewModel.isPostSuccessful) { oldValue, newValue in
                handlePostSuccess(newValue)
            }
            .onChange(of: postViewModel.postError) { oldValue, newValue in
                handlePostError(newValue)
            }
        }
    }
    
    // MARK: - View Components
    
    private var postTextSection: some View {
        Section {
            TextField("What's on your mind?", text: $postViewModel.post.text, axis: .vertical)
                .lineLimit(5...10)
            
            HashtagsView(hashtags: $postViewModel.post.hashtags)
        }
    }
    
    private var templateSection: some View {
        Section(header: Text("Template")) {
            if let template = postViewModel.selectedTemplate {
                existingTemplateView(template)
            } else {
                Button("Select a Template") {
                    showTemplates = true
                }
            }
        }
    }
    
    private func existingTemplateView(_ template: Template) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(template.name)
                    .font(.headline)
                
                if !template.hashtags.isEmpty {
                    Text(template.formattedHashtags)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Button("Change") {
                showTemplates = true
            }
        }
    }
    
    private var mediaSection: some View {
        Section(header: Text("Media")) {
            if postViewModel.post.media.isEmpty {
                emptyMediaView
            } else {
                mediaGalleryView
            }
        }
    }
    
    private var emptyMediaView: some View {
        HStack {
            Button(action: {
                showCamera = true
            }) {
                Label("Take Photo", systemImage: "camera")
            }
            
            Spacer()
            
            Button(action: {
                showPhotoPicker = true
            }) {
                Label("Choose Photo", systemImage: "photo")
            }
        }
    }
    
    private var mediaGalleryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Existing media items
                ForEach(0..<postViewModel.post.media.count, id: \.self) { index in
                    mediaItemView(at: index)
                }
                
                // Camera button
                mediaAddButton(isCameraButton: true)
                
                // Photo picker button
                mediaAddButton(isCameraButton: false)
            }
            .padding(.vertical, 5)
        }
    }
    
    private func mediaItemView(at index: Int) -> some View {
        let media = postViewModel.post.media[index]
        return ZStack(alignment: .topTrailing) {
            Image(uiImage: media.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .cornerRadius(8)
            
            Button(action: {
                postViewModel.removeMedia(at: index)
            }) {
                Image(systemName: "x.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .padding(4)
            }
        }
    }
    
    private func mediaAddButton(isCameraButton: Bool) -> some View {
        Button(action: {
            if postViewModel.post.media.count < 4 {
                if isCameraButton {
                    showCamera = true
                } else {
                    showPhotoPicker = true
                }
            }
        }) {
            VStack {
                Image(systemName: isCameraButton ? "camera" : "photo")
                    .font(.system(size: 30))
                Text("Add")
                    .font(.caption)
            }
            .frame(width: 80, height: 80)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .disabled(postViewModel.post.media.count >= 4)
    }
    
    private var postButtonSection: some View {
        Section {
            Button(action: {
                if postViewModel.needsAuthentication {
                    showLoginSheet = true
                } else {
                    submitPost()
                }
            }) {
                if postViewModel.isPosting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(postViewModel.needsAuthentication ? "Login to Post" : "Post to BlueSky")
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .disabled(postViewModel.isPosting || postViewModel.post.text.isEmpty)
        }
    }
    
    private func errorSection(_ error: String) -> some View {
        Section {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if authViewModel.isLoggedIn {
                Menu {
                    Button(action: {
                        authViewModel.logout()
                        postViewModel.needsAuthentication = true
                    }) {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Label("Menu", systemImage: "person.circle")
                }
            }
        }
    }
    
    private var templateSheetContent: some View {
        TemplatesView(selectedTemplate: $postViewModel.selectedTemplate)
            .onDisappear {
                if let template = postViewModel.selectedTemplate {
                    postViewModel.applyTemplate(template)
                }
            }
    }
    
    private var loginSheetContent: some View {
        LoginView(authViewModel: authViewModel)
            .onDisappear {
                postViewModel.checkAuthenticationStatus()
                
                if !postViewModel.needsAuthentication {
                    submitPost()
                }
            }
    }
    
    // MARK: - Helper Methods
    
    private func checkTemplates() {
        if postViewModel.selectedTemplate == nil && !postViewModel.post.text.isEmpty {
            return
        }
    }
    
    private func handlePostSuccess(_ isSuccessful: Bool) {
        if isSuccessful {
            showSuccessAlert = true
            postViewModel.isPostSuccessful = false
        }
    }
    
    private func handlePostError(_ error: String?) {
        if error != nil {
            showErrorAlert = true
        }
    }
    
    private func submitPost() {
        Task {
            await postViewModel.submitPost()
        }
    }
    
    private func resetPost() {
        let template = postViewModel.selectedTemplate
        postViewModel.post = Post(template: template)
    }
}

struct HashtagsView: View {
    @Binding var hashtags: [String]
    @State private var newTag: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Hashtags")
                .font(.headline)
                .padding(.top, 5)
            
            FlowLayout(spacing: 8) {
                ForEach(hashtags, id: \.self) { tag in
                    hashtagView(tag: tag)
                }
                
                TextField("Add hashtag", text: $newTag)
                    .submitLabel(.done)
                    .onSubmit {
                        addTag()
                    }
                    .frame(width: 120)
                    .padding(.vertical, 5)
            }
        }
    }
    
    private func hashtagView(tag: String) -> some View {
        HStack {
            Text("#\(tag)")
                .padding(.vertical, 5)
                .padding(.leading, 10)
            
            Button(action: {
                removeTag(tag)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 10)
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(20)
    }
    
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty && !hashtags.contains(trimmedTag) {
            hashtags.append(trimmedTag)
            newTag = ""
        }
    }
    
    private func removeTag(_ tag: String) {
        hashtags.removeAll { $0 == tag }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 0
        
        var height: CGFloat = 0
        var width: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let viewSize = subview.sizeThatFits(.unspecified)
            
            if rowWidth + viewSize.width > containerWidth {
                // Start a new row
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = viewSize.width
                rowHeight = viewSize.height
            } else {
                // Continue on the current row
                rowWidth += viewSize.width + spacing
                rowHeight = max(rowHeight, viewSize.height)
            }
        }
        
        // Add the last row
        width = max(width, rowWidth)
        height += rowHeight
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let containerWidth = bounds.width
        
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowStartIndex = 0
        
        var y = bounds.minY
        
        for index in subviews.indices {
            let viewSize = subviews[index].sizeThatFits(.unspecified)
            
            if rowWidth + viewSize.width > containerWidth {
                // Place the row
                placeRow(subviews: subviews, from: rowStartIndex, to: index - 1, y: y, rowHeight: rowHeight, rowWidth: rowWidth, bounds: bounds)
                
                // Start a new row
                y += rowHeight + spacing
                rowWidth = viewSize.width
                rowHeight = viewSize.height
                rowStartIndex = index
            } else {
                // Continue on current row
                rowWidth += viewSize.width + (index > rowStartIndex ? spacing : 0)
                rowHeight = max(rowHeight, viewSize.height)
            }
        }
        
        // Place the last row
        placeRow(subviews: subviews, from: rowStartIndex, to: subviews.count - 1, y: y, rowHeight: rowHeight, rowWidth: rowWidth, bounds: bounds)
    }
    
    private func placeRow(subviews: Subviews, from startIndex: Int, to endIndex: Int, y: CGFloat, rowHeight: CGFloat, rowWidth: CGFloat, bounds: CGRect) {
        var x = bounds.minX
        
        for index in startIndex...endIndex {
            let viewSize = subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - viewSize.height) / 2), proposal: ProposedViewSize(viewSize))
            x += viewSize.width + spacing
        }
    }
}

struct CreatePostView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePostView(
            postViewModel: PostViewModel(template: Template.example),
            authViewModel: AuthViewModel()
        )
    }
} 