import SwiftData

/// Builds SwiftData storage configurations for templates.
public enum TemplateStorage {
    /// The app's private CloudKit container for synced templates.
    public static let cloudKitContainerIdentifier = "iCloud.com.dtolb.BlueSkyTemplates"

    /// The SwiftData configuration name used for template stores.
    public static let configurationName = "Templates"

    /// The SwiftData schema owned by the Templates module.
    public static var schema: Schema {
        Schema([Template.self])
    }

    /// A CloudKit-backed SwiftData configuration for production template storage.
    public static var cloudConfiguration: ModelConfiguration {
        cloudConfiguration(for: schema)
    }

    /// An in-memory SwiftData configuration with CloudKit disabled for tests and previews.
    public static var inMemoryConfiguration: ModelConfiguration {
        inMemoryConfiguration(for: schema)
    }

    /// Creates a CloudKit-backed template container.
    public static func makeCloudContainer() throws -> ModelContainer {
        let schema = Self.schema
        return try ModelContainer(
            for: schema,
            configurations: [cloudConfiguration(for: schema)]
        )
    }

    /// Creates an in-memory template container with CloudKit disabled.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Self.schema
        return try ModelContainer(
            for: schema,
            configurations: [inMemoryConfiguration(for: schema)]
        )
    }

    private static func cloudConfiguration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            configurationName,
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
    }

    private static func inMemoryConfiguration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            configurationName,
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }
}
