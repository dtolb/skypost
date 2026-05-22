// Template — SwiftData @Model per §6.5.
//
// Lives in the Templates module per §5's intent that SwiftData models stay
// with the feature module that owns them. Apps can wire storage through
// TemplateStorage.

import Foundation
import SwiftData

@Model
public final class Template {
    public var id: UUID = UUID()
    public var title: String = ""
    public var body: String = ""
    public var hashtags: [String] = []
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        hashtags: [String] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.hashtags = hashtags
        self.updatedAt = updatedAt
    }

    /// Bumps updatedAt so the template floats to the top of the updatedAt-desc list.
    public func touch() {
        self.updatedAt = .now
    }
}
