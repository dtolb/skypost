import Testing
import Foundation
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
