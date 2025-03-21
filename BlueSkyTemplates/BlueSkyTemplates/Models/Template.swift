import Foundation
import SwiftUI

struct Template: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var text: String
    var hashtags: [String]
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, text: String, hashtags: [String], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.text = text
        self.hashtags = hashtags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var formattedHashtags: String {
        hashtags.map { "#\($0)" }.joined(separator: " ")
    }
    
    var fullText: String {
        if hashtags.isEmpty {
            return text
        }
        return "\(text)\n\n\(formattedHashtags)"
    }
    
    static let example = Template(
        name: "Coffee Art",
        text: "Today's latte art practice. Getting better!",
        hashtags: ["latteart", "coffee", "barista", "homecafe"]
    )
    
    static let cameraExample = Template(
        name: "Fuji Photography",
        text: "Captured this moment during my walk today.",
        hashtags: ["x100vi", "fujifilm", "photography", "streetphotography"]
    )
    
    static func == (lhs: Template, rhs: Template) -> Bool {
        return lhs.id == rhs.id
    }
} 