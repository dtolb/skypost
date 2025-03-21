import Foundation
import UIKit
import SwiftUI

class PostViewModel: ObservableObject {
    @Published var post: Post
    @Published var selectedTemplate: Template?
    @Published var isPosting = false
    @Published var postError: String?
    @Published var isPostSuccessful = false
    @Published var needsAuthentication = false
    
    private let blueSkyService = BlueSkyService()
    private let photoService = PhotoService()
    
    init(template: Template? = nil) {
        self.selectedTemplate = template
        self.post = Post(template: template)
        
        // Check if we have auth information
        checkAuthenticationStatus()
    }
    
    func checkAuthenticationStatus() {
        needsAuthentication = !blueSkyService.isAuthenticated()
    }
    
    // Apply a template to the current post
    func applyTemplate(_ template: Template) {
        selectedTemplate = template
        post.text = template.text
        post.hashtags = template.hashtags
    }
    
    // Add or remove hashtags
    func addHashtag(_ tag: String) {
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTag.isEmpty && !post.hashtags.contains(cleanTag) {
            post.hashtags.append(cleanTag)
        }
    }
    
    func removeHashtag(_ tag: String) {
        post.hashtags.removeAll { $0 == tag }
    }
    
    // Add media to the post
    func addMedia(_ media: [PostMedia]) {
        post.media.append(contentsOf: media)
    }
    
    func removeMedia(at index: Int) {
        if index >= 0 && index < post.media.count {
            post.media.remove(at: index)
        }
    }
    
    // Post to BlueSky
    func submitPost() async {
        // First check if we're authenticated
        if !blueSkyService.isAuthenticated() {
            await MainActor.run {
                needsAuthentication = true
                postError = "Please log in to Bluesky before posting"
            }
            return
        }
        
        // Update UI properties on the main thread
        await MainActor.run {
            isPosting = true
            postError = nil
        }
        
        do {
            // Extract images from PostMedia
            let images = post.media.map { $0.image }
            
            let result = await blueSkyService.createPost(
                text: post.fullText,
                images: images
            )
            
            // Update UI properties on the main thread
            await MainActor.run {
                isPosting = false
                
                switch result {
                case .success(_):
                    isPostSuccessful = true
                case .failure(let error):
                    postError = "Failed to post: \(error)"
                    // If we got an auth error, we need to re-authenticate
                    if error == .authError {
                        needsAuthentication = true
                    }
                }
            }
        }
    }
    
    // Login to BlueSky
    func login(identifier: String, password: String) async -> Bool {
        let result = await blueSkyService.login(identifier: identifier, password: password)
        
        switch result {
        case .success(_):
            await MainActor.run {
                needsAuthentication = false
            }
            return true
        case .failure(_):
            await MainActor.run {
                postError = "Login failed. Please check your credentials."
            }
            return false
        }
    }
} 
