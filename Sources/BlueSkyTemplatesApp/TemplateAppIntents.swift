#if canImport(AppIntents)
import AppIntents
import Foundation
import SwiftData
import Templates

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct BlueSkyTemplatesAppIntentsPackage: AppIntentsPackage {}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct CreateTemplateIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Template"
    public static let description = IntentDescription("Create a saved Bluesky post template.")

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public static var supportedModes: IntentModes { .background }

    @Parameter(title: "Title")
    var title: String

    @Parameter(
        title: "Body",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var body: String

    @Parameter(title: "Hashtags")
    var hashtags: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let normalizedTitle = Self.normalizedTitle(title)
        let normalizedHashtags = Self.normalizedHashtags(hashtags)

        do {
            try await MainActor.run {
                let container = try TemplateStorage.makeCloudContainer()
                let template = Template(
                    title: normalizedTitle,
                    body: body,
                    hashtags: normalizedHashtags
                )
                container.mainContext.insert(template)
                try container.mainContext.save()
            }
            return .result(dialog: "Created \(normalizedTitle).")
        } catch {
            return .result(dialog: "Could not create the template.")
        }
    }

    static func normalizedTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Template" : trimmed
    }

    static func normalizedHashtags(_ rawHashtags: String?) -> [String] {
        parseHashtags(rawHashtags ?? "")
    }
}

#endif
