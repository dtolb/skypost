import Foundation
import SwiftUI

enum MediaSource {
    case camera
    case photoLibrary
}

struct PostMedia: Identifiable {
    var id = UUID()
    var image: UIImage
    var aspectRatio: CGFloat {
        return image.size.width / image.size.height
    }
    var originalSize: CGSize {
        return image.size
    }
}

struct Post {
    var text: String
    var hashtags: [String]
    var media: [PostMedia]
    
    var formattedHashtags: String {
        hashtags.map { "#\($0)" }.joined(separator: " ")
    }
    
    var fullText: String {
        if hashtags.isEmpty {
            return text
        }
        return "\(text)\n\n\(formattedHashtags)"
    }
    
    init(template: Template? = nil, text: String = "", hashtags: [String] = [], media: [PostMedia] = []) {
        if let template = template {
            self.text = template.text
            self.hashtags = template.hashtags
        } else {
            self.text = text
            self.hashtags = hashtags
        }
        self.media = media
    }
} 