// Template — SwiftData @Model per §6.5.
//
// Lives in the Templates module per §5's intent that SwiftData models stay
// with the feature module that owns them. Apps wire this up with
// `.modelContainer(for: Template.self)` at App scope.

import Foundation
import SwiftData

@Model
public final class Template {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var body: String
    public var hashtags: [String]
    public var updatedAt: Date

    public init(title: String, body: String, hashtags: [String] = []) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.hashtags = hashtags
        self.updatedAt = .now
    }

    /// Bumps updatedAt so the template floats to the top of the updatedAt-desc list.
    public func touch() {
        self.updatedAt = .now
    }
}
