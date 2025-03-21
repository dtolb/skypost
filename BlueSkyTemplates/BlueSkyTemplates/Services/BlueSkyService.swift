import Foundation
import UIKit

enum BlueSkyError: Error {
    case networkError
    case authError
    case uploadError
    case postError
    case decodingError
    case unknown
}

class BlueSkyService {
    // Bluesky PDS endpoint - use the correct one based on Bluesky's documentation
    private let baseURL = "https://bsky.social/xrpc"
    private var auth: BlueSkyAuth?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let authKey = "bluesky_auth_data"
    
    init() {
        // Load saved authentication data when initializing
        loadSavedAuth()
    }
    
    // MARK: - Authentication State
    
    func isAuthenticated() -> Bool {
        return auth != nil && auth?.session != nil && auth?.did != nil
    }
    
    private func saveAuth(_ auth: BlueSkyAuth) {
        self.auth = auth
        
        // Persist auth to UserDefaults
        if let encodedData = try? encoder.encode(auth) {
            UserDefaults.standard.set(encodedData, forKey: authKey)
        }
    }
    
    private func loadSavedAuth() {
        if let savedData = UserDefaults.standard.data(forKey: authKey),
           let savedAuth = try? decoder.decode(BlueSkyAuth.self, from: savedData) {
            self.auth = savedAuth
        }
    }
    
    func clearAuth() {
        self.auth = nil
        UserDefaults.standard.removeObject(forKey: authKey)
    }
    
    // MARK: - Authentication
    
    func login(identifier: String, password: String) async -> Result<BlueSkyAuth, BlueSkyError> {
        guard let url = URL(string: "\(baseURL)/com.atproto.server.createSession") else {
            return .failure(.networkError)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["identifier": identifier, "password": password]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Login response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    print("Login error: \(String(data: data, encoding: .utf8) ?? "No error message")")
                    return .failure(.authError)
                }
            }
            
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let did = jsonResponse["did"] as? String,
                  let accessJwt = jsonResponse["accessJwt"] as? String,
                  let refreshJwt = jsonResponse["refreshJwt"] as? String else {
                return .failure(.decodingError)
            }
            
            let authData = BlueSkyAuth(
                identifier: identifier, 
                password: password,
                session: accessJwt,
                refreshToken: refreshJwt,
                did: did
            )
            
            // Save the auth data
            saveAuth(authData)
            
            return .success(authData)
        } catch {
            print("Network error during login: \(error)")
            return .failure(.networkError)
        }
    }
    
    // MARK: - Token Refresh
    
    private func refreshTokenIfNeeded() async -> Bool {
        guard let auth = auth, let refreshToken = auth.refreshToken else {
            return false
        }
        
        guard let url = URL(string: "\(baseURL)/com.atproto.server.refreshSession") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessJwt = jsonResponse["accessJwt"] as? String,
               let refreshJwt = jsonResponse["refreshJwt"] as? String {
                
                var updatedAuth = auth
                updatedAuth.session = accessJwt
                updatedAuth.refreshToken = refreshJwt
                
                // Save the refreshed auth data
                saveAuth(updatedAuth)
                
                return true
            }
        } catch {
            print("Failed to refresh token: \(error)")
        }
        
        return false
    }
    
    // MARK: - Posting
    
    func createPost(text: String, images: [UIImage]) async -> Result<String, BlueSkyError> {
        // Check if we need to refresh the token first
        let refreshTokenNeeded = await refreshTokenIfNeeded()
        if !refreshTokenNeeded && !isAuthenticated() {
            return .failure(.authError)
        }
        
        
        // First, upload images if any
        var blobs: [[String: Any]] = []
        
        for image in images {
            do {
                guard let blobResult = try await uploadImage(image) else {
                    return .failure(.uploadError)
                }
                blobs.append(blobResult)
            } catch {
                print("Failed to upload image: \(error)")
                return .failure(.uploadError)
            }
        }
        
        // Then create the post
        return await createPostWithBlobs(text: text, blobs: blobs)
    }
    
    private func uploadImage(_ image: UIImage) async throws -> [String: Any]? {
        guard let auth = auth, let session = auth.session,
              let url = URL(string: "\(baseURL)/com.atproto.repo.uploadBlob") else {
            return nil
        }
        
        // Get resized image data under 900KB
        guard let imageData = resizeImageToMaxSize(image, maxSizeKB: 900) else {
            return nil
        }
        
        // Print the size for debugging
        print("Image size for upload: \(Double(imageData.count) / 1024.0) KB")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Upload blob response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    print("Upload blob error: \(String(data: data, encoding: .utf8) ?? "No error message")")
                    return nil
                }
            }
            
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blob = jsonResponse["blob"] as? [String: Any] else {
                return nil
            }
            
            return blob
        } catch {
            print("Network error during image upload: \(error)")
            throw BlueSkyError.networkError
        }
    }
    
    // Function to resize image data to a maximum size in KB
    private func resizeImageToMaxSize(_ image: UIImage, maxSizeKB: Int) -> Data? {
        let maxSizeBytes = maxSizeKB * 1024
        
        // Try initial high quality compression
        if let data = image.jpegData(compressionQuality: 0.9), data.count <= maxSizeBytes {
            return data
        }
        
        // Try several quality levels without resizing
        var compressionQuality: CGFloat = 0.8
        while compressionQuality >= 0.1 {
            if let data = image.jpegData(compressionQuality: compressionQuality), data.count <= maxSizeBytes {
                return data
            }
            compressionQuality -= 0.1
        }
        
        // If compression alone isn't enough, start resizing
        var currentImage = image
        var scaleFactor: CGFloat = 0.9
        
        while scaleFactor > 0.1 {
            let newWidth = currentImage.size.width * scaleFactor
            let newHeight = currentImage.size.height * scaleFactor
            
            UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, 1.0)
            currentImage.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            guard let resized = resizedImage else {
                break
            }
            
            // Try with different compression qualities for each size
            var tryQuality: CGFloat = 0.8
            while tryQuality >= 0.1 {
                if let data = resized.jpegData(compressionQuality: tryQuality), data.count <= maxSizeBytes {
                    return data
                }
                tryQuality -= 0.1
            }
            
            // Update for next iteration
            currentImage = resized
            scaleFactor -= 0.1
        }
        
        // Last resort - try with the smallest size and lowest quality
        if let smallestImage = currentImage.jpegData(compressionQuality: 0.1) {
            return smallestImage
        }
        
        // If everything fails, return nil
        return nil
    }
    
    private func createPostWithBlobs(text: String, blobs: [[String: Any]]) async -> Result<String, BlueSkyError> {
        guard let auth = auth, let session = auth.session, let did = auth.did,
              let url = URL(string: "\(baseURL)/com.atproto.repo.createRecord") else {
            return .failure(.networkError)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        
        // Parse hashtags and create facets
        let facets = parseHashtags(text)
        
        // Properly format the post record according to Bluesky API specs
        var postRecord: [String: Any] = [
            "text": text,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Add facets for hashtags if any were found
        if !facets.isEmpty {
            postRecord["facets"] = facets
        }
        
        // Format embed according to the documentation
        if !blobs.isEmpty {
            var images: [[String: Any]] = []
            
            for blob in blobs {
                images.append([
                    "alt": "Image uploaded from BlueSkyTemplates app",
                    "image": blob
                ])
            }
            
            // Create proper embed structure
            postRecord["embed"] = [
                "$type": "app.bsky.embed.images",
                "images": images
            ]
        }
        
        let payload: [String: Any] = [
            "repo": did,
            "collection": "app.bsky.feed.post",
            "record": postRecord
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print("Sending post payload: \(String(data: jsonData, encoding: .utf8) ?? "Invalid JSON")")
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Create post response status: \(httpResponse.statusCode)")
                print("Response headers: \(httpResponse.allHeaderFields)")
                print("Response body: \(String(data: data, encoding: .utf8) ?? "No response body")")
                
                if httpResponse.statusCode != 200 {
                    return .failure(.postError)
                }
            }
            
            // Successfully posted
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uri = jsonResponse["uri"] as? String else {
                return .failure(.decodingError)
            }
            
            return .success(uri)
        } catch {
            print("Network error during post creation: \(error)")
            return .failure(.networkError)
        }
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxSizeKB: Int = 900) -> UIImage {
        // First try with high quality JPEG compression
        guard let initialData = image.jpegData(compressionQuality: 0.8) else {
            return image // Return original if we can't get initial data
        }
        
        // Check if the image is already small enough
        if initialData.count <= maxSizeKB * 1024 {
            return image
        }
        
        // Start with reasonable compression quality
        var compressionQuality: CGFloat = 0.7
        let minCompressionQuality: CGFloat = 0.1
        
        // Try compressing with decreasing quality
        while compressionQuality > minCompressionQuality {
            guard let compressedData = image.jpegData(compressionQuality: compressionQuality) else {
                break
            }
            
            if compressedData.count <= maxSizeKB * 1024 {
                // If we reach the target size with compression only, return a UIImage from the compressed data
                if let compressedImage = UIImage(data: compressedData) {
                    return compressedImage
                }
                break
            }
            
            // Reduce quality and try again
            compressionQuality -= 0.1
        }
        
        // If compression alone didn't work, we'll resize the image
        var targetImage = image
        var scaleFactor: CGFloat = 0.9
        
        while scaleFactor > 0.1 {
            // Calculate new dimensions
            let newWidth = targetImage.size.width * scaleFactor
            let newHeight = targetImage.size.height * scaleFactor
            
            // Create a new image context
            UIGraphicsBeginImageContextWithOptions(CGSize(width: newWidth, height: newHeight), false, 1.0)
            targetImage.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                UIGraphicsEndImageContext()
                
                // Check if this resized image meets our size requirement
                if let resizedData = resizedImage.jpegData(compressionQuality: 0.7),
                   resizedData.count <= maxSizeKB * 1024 {
                    return resizedImage
                }
                
                // Update target for next iteration
                targetImage = resizedImage
            } else {
                UIGraphicsEndImageContext()
                break
            }
            
            // Reduce size further if needed
            scaleFactor -= 0.1
        }
        
        // If we can't get under the limit with reasonable methods, try one more time
        // with both small size and low quality
        if let finalData = targetImage.jpegData(compressionQuality: 0.5),
           let finalImage = UIImage(data: finalData) {
            return finalImage
        }
        
        // Return our best effort if we can't meet the target
        return targetImage
    }
    
    // Add this new function to parse hashtags
    private func parseHashtags(_ text: String) -> [[String: Any]] {
        var facets: [[String: Any]] = []
        
        // Regular expression to find hashtags
        // This regex looks for hashtags that start with # and contain letters, numbers, or underscores
        guard let regex = try? NSRegularExpression(pattern: "#([\\w_]+)", options: []) else {
            return facets
        }
        
        // Need to work with UTF8 for byte position calculations
        let textData = text.data(using: .utf8)!
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        
        for match in matches {
            // Get the full range, including the # symbol
            let fullRange = match.range
            
            // Extract just the tag without the # symbol
            let tagRange = match.range(at: 1)
            
            guard let tagRange = Range(tagRange, in: text) else { continue }
            let tag = String(text[tagRange])
            
            // Calculate UTF-8 byte positions
            guard let fullRange = Range(fullRange, in: text) else { continue }
            let fullMatchStr = String(text[fullRange])
            
            // Find byte position of the start of the hashtag
            var byteStart = 0
            if fullRange.lowerBound.utf16Offset(in: text) > 0 {
                let prefixString = text[..<fullRange.lowerBound]
                byteStart = prefixString.data(using: .utf8)!.count
            }
            
            // Find byte position of the end of the hashtag
            let byteEnd = byteStart + fullMatchStr.data(using: .utf8)!.count
            
            // Create a facet for this hashtag
            let facet: [String: Any] = [
                "index": [
                    "byteStart": byteStart,
                    "byteEnd": byteEnd
                ],
                "features": [
                    [
                        "$type": "app.bsky.richtext.facet#tag",
                        "tag": tag
                    ]
                ]
            ]
            
            facets.append(facet)
        }
        
        return facets
    }
}
