import Testing
import Foundation
import SwiftData
@testable import Templates

@Suite("Template @Model")
struct TemplateModelTests {
    @Test
    func initSetsTitleBodyAndUpdatedAt() {
        let t = Template(title: "Hello", body: "World", hashtags: ["bsky"])
        #expect(t.title == "Hello")
        #expect(t.body == "World")
        #expect(t.hashtags == ["bsky"])
        #expect(t.updatedAt.timeIntervalSinceNow < 1)
    }
}

// MARK: - In-memory container helper

@MainActor
private func inMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Template.self, configurations: config)
}

// MARK: - SwiftData CRUD

@Suite("Template SwiftData CRUD")
struct TemplateCRUDTests {

    @Test
    @MainActor
    func fetchEmptyContainerReturnsEmptyArray() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let results = try context.fetch(FetchDescriptor<Template>())
        #expect(results.isEmpty)
    }

    @Test
    @MainActor
    func insertAndFetchRoundTrip() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let older = Template(title: "Older", body: "First", hashtags: ["a"])
        context.insert(older)
        try context.save()

        // Pause so updatedAt timestamps are strictly ordered.
        try await Task.sleep(for: .milliseconds(50))

        let newer = Template(title: "Newer", body: "Second", hashtags: ["b", "c"])
        context.insert(newer)
        try context.save()

        let olderID = older.id
        let newerID = newer.id

        let descriptor = FetchDescriptor<Template>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 2)
        #expect(results.first?.id == newerID)
        #expect(results.last?.id == olderID)
        #expect(results.first?.hashtags == ["b", "c"])
        #expect(results.last?.hashtags == ["a"])
    }

    @Test
    @MainActor
    func touchMovesTemplateToFrontOfFetchOrder() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let a = Template(title: "A", body: "first", hashtags: [])
        context.insert(a)
        try context.save()

        try await Task.sleep(for: .milliseconds(50))

        let b = Template(title: "B", body: "second", hashtags: [])
        context.insert(b)
        try context.save()

        // Sanity check: before touch, B is newest.
        let descriptor = FetchDescriptor<Template>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let beforeTouch = try context.fetch(descriptor)
        #expect(beforeTouch.first?.id == b.id)

        try await Task.sleep(for: .milliseconds(50))

        a.touch()
        try context.save()

        let afterTouch = try context.fetch(descriptor)
        #expect(afterTouch.first?.id == a.id)
        #expect(afterTouch.last?.id == b.id)
    }

    @Test
    @MainActor
    func deleteRemovesFromFetch() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let keep = Template(title: "Keep", body: "stays", hashtags: [])
        let drop = Template(title: "Drop", body: "goes", hashtags: [])
        context.insert(keep)
        context.insert(drop)
        try context.save()

        context.delete(drop)
        try context.save()

        let results = try context.fetch(FetchDescriptor<Template>())
        #expect(results.count == 1)
        #expect(results.first?.id == keep.id)
    }

    @Test
    @MainActor
    func hashtagsArrayRoundTripsThroughSwiftData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        let t = Template(title: "Tagged", body: "x", hashtags: ["bsky", "swiftui"])
        context.insert(t)
        try context.save()

        let results = try context.fetch(FetchDescriptor<Template>())
        #expect(results.count == 1)
        #expect(results.first?.hashtags == ["bsky", "swiftui"])
    }
}
