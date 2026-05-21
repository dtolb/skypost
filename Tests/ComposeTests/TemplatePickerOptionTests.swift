import Testing
import Foundation
import SwiftData
import Compose
import Templates

@Suite("TemplatePickerOption")
struct TemplatePickerOptionTests {

    @Test
    @MainActor
    func optionsFromEmptyArrayReturnsJustNone() {
        let options = TemplatePickerOption.options(from: [])
        #expect(options.count == 1)
        // Disambiguate: `.none` would otherwise resolve to Optional.none.
        #expect(options.first == TemplatePickerOption.none)
    }

    @Test
    @MainActor
    func optionsFromTemplatesPrependsNoneAndPreservesOrder() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let first  = Template(title: "First",  body: "x", hashtags: [])
        let second = Template(title: "Second", body: "y", hashtags: [])
        context.insert(first)
        context.insert(second)
        try context.save()

        let options = TemplatePickerOption.options(from: [first, second])

        #expect(options.count == 3)
        #expect(options[0] == .none)
        #expect(options[1] == .template(first.persistentModelID, title: "First"))
        #expect(options[2] == .template(second.persistentModelID, title: "Second"))
    }

    @Test
    func noneOptionTitleIsHumanReadable() {
        #expect(TemplatePickerOption.none.menuTitle == "None (blank)")
    }

    @Test
    @MainActor
    func templateOptionTitleEchoesTemplateTitle() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let t = Template(title: "Daily Fuji", body: "x", hashtags: [])
        context.insert(t)
        try context.save()

        let option = TemplatePickerOption.template(t.persistentModelID, title: t.title)
        #expect(option.menuTitle == "Daily Fuji")
    }

    @Test
    @MainActor
    func optionsIdentifyByDistinctIDs() throws {
        let container = try inMemoryTemplateContainer()
        let context = ModelContext(container)
        let a = Template(title: "A", body: "x", hashtags: [])
        let b = Template(title: "B", body: "y", hashtags: [])
        context.insert(a)
        context.insert(b)
        try context.save()

        let options = TemplatePickerOption.options(from: [a, b])
        let ids = Set(options.map(\.id))
        #expect(ids.count == options.count, "Each option must have a unique id for ForEach")
    }
}

@MainActor
private func inMemoryTemplateContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Template.self, configurations: config)
}
