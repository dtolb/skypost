import Foundation
import SwiftData
import Templates
import Testing

@Suite("Template exchange JSON")
struct TemplateExchangeJSONTests {

    @Test
    func singleTemplateRoundTripsThroughJSON() throws {
        let document = TemplateExchangeDocument(
            id: try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555")),
            title: "Daily standup",
            body: "What did you ship?",
            hashtags: ["work", "bsky"],
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try TemplateExchange.encode(document)
        let decoded = try TemplateExchange.decodeTemplate(from: data)

        #expect(decoded == document)
    }

    @Test
    func invalidPayloadThrowsUsefulExchangeError() {
        let invalidJSON = Data(#"{"schema":"wrong","version":1}"#.utf8)

        #expect(throws: TemplateExchangeError.self) {
            _ = try TemplateExchange.decodeTemplate(from: invalidJSON)
        }
    }
}

@Suite("Template exchange import")
struct TemplateExchangeImportTests {

    @Test
    @MainActor
    func importingTemplateCreatesRow() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let document = TemplateExchangeDocument(
            id: id,
            title: "First",
            body: "Body",
            hashtags: ["one"],
            updatedAt: updatedAt
        )

        let imported = try TemplateExchange.upsert(document, into: context)
        let results = try context.fetch(FetchDescriptor<Template>())

        #expect(imported.id == id)
        #expect(results.count == 1)
        #expect(results.first?.id == id)
        #expect(results.first?.title == "First")
        #expect(results.first?.body == "Body")
        #expect(results.first?.hashtags == ["one"])
        #expect(results.first?.updatedAt == updatedAt)
    }

    @Test
    @MainActor
    func importingSameUUIDUpdatesExistingRowInsteadOfDuplicating() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let id = try #require(UUID(uuidString: "99999999-8888-7777-6666-555555555555"))

        _ = try TemplateExchange.upsert(
            TemplateExchangeDocument(
                id: id,
                title: "Original",
                body: "Old body",
                hashtags: ["old"],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            into: context
        )
        _ = try TemplateExchange.upsert(
            TemplateExchangeDocument(
                id: id,
                title: "Updated",
                body: "New body",
                hashtags: ["new", "bsky"],
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            into: context
        )

        let results = try context.fetch(FetchDescriptor<Template>())

        #expect(results.count == 1)
        #expect(results.first?.id == id)
        #expect(results.first?.title == "Updated")
        #expect(results.first?.body == "New body")
        #expect(results.first?.hashtags == ["new", "bsky"])
        #expect(results.first?.updatedAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}

// MARK: - In-memory container helper

@MainActor
private func inMemoryContainer() throws -> ModelContainer {
    try TemplateStorage.makeInMemoryContainer()
}
