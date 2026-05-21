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
        let ctx = ModelContext(container)
        let results = try ctx.fetch(FetchDescriptor<Template>())
        #expect(results.isEmpty)
    }

    @Test
    @MainActor
    func insertAndFetchRoundTrip() throws {
        let container = try inMemoryContainer()
        let ctx = ModelContext(container)

        let older = Template(title: "Older", body: "First", hashtags: ["a"])
        ctx.insert(older)
        try ctx.save()

        // Pause so updatedAt timestamps are strictly ordered.
        Thread.sleep(forTimeInterval: 0.05)

        let newer = Template(title: "Newer", body: "Second", hashtags: ["b", "c"])
        ctx.insert(newer)
        try ctx.save()

        let olderID = older.id
        let newerID = newer.id

        let descriptor = FetchDescriptor<Template>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let results = try ctx.fetch(descriptor)

        #expect(results.count == 2)
        #expect(results.first?.id == newerID)
        #expect(results.last?.id == olderID)
        #expect(results.first?.hashtags == ["b", "c"])
        #expect(results.last?.hashtags == ["a"])
    }

    @Test
    @MainActor
    func touchUpdatesUpdatedAtAndReordering() throws {
        let container = try inMemoryContainer()
        let ctx = ModelContext(container)

        let a = Template(title: "A", body: "first", hashtags: [])
        ctx.insert(a)
        try ctx.save()

        Thread.sleep(forTimeInterval: 0.05)

        let b = Template(title: "B", body: "second", hashtags: [])
        ctx.insert(b)
        try ctx.save()

        // Sanity check: before touch, B is newest.
        let descriptor = FetchDescriptor<Template>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let beforeTouch = try ctx.fetch(descriptor)
        #expect(beforeTouch.first?.id == b.id)

        Thread.sleep(forTimeInterval: 0.05)

        a.touch()
        try ctx.save()

        let afterTouch = try ctx.fetch(descriptor)
        #expect(afterTouch.first?.id == a.id)
        #expect(afterTouch.last?.id == b.id)
    }

    @Test
    @MainActor
    func deleteRemovesFromFetch() throws {
        let container = try inMemoryContainer()
        let ctx = ModelContext(container)

        let keep = Template(title: "Keep", body: "stays", hashtags: [])
        let drop = Template(title: "Drop", body: "goes", hashtags: [])
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        ctx.delete(drop)
        try ctx.save()

        let results = try ctx.fetch(FetchDescriptor<Template>())
        #expect(results.count == 1)
        #expect(results.first?.id == keep.id)
    }

    @Test
    @MainActor
    func hashtagsArrayPersistedAsExpected() throws {
        let container = try inMemoryContainer()
        let ctx = ModelContext(container)

        let t = Template(title: "Tagged", body: "x", hashtags: ["bsky", "swiftui"])
        ctx.insert(t)
        try ctx.save()

        let results = try ctx.fetch(FetchDescriptor<Template>())
        #expect(results.count == 1)
        #expect(results.first?.hashtags == ["bsky", "swiftui"])
    }
}
