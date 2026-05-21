import Testing
import Foundation
import Templates

@Suite("TemplateApplier")
struct TemplateApplierTests {

    @Test
    @MainActor
    func applyRecordsBodyAndHashtagsFromTemplate() {
        let applier = TemplateApplier()
        let t = Template(title: "t", body: "hello", hashtags: ["a", "b"])

        applier.apply(t)

        #expect(applier.pending?.body == "hello")
        #expect(applier.pending?.hashtags == ["a", "b"])
    }

    @Test
    @MainActor
    func firstApplyStartsTickAtOne() {
        let applier = TemplateApplier()
        let t = Template(title: "t", body: "hello", hashtags: [])

        applier.apply(t)

        #expect(applier.pending?.tick == 1)
    }

    @Test
    @MainActor
    func subsequentAppliesIncrementTickMonotonically() {
        let applier = TemplateApplier()
        let t = Template(title: "t", body: "hello", hashtags: [])

        applier.apply(t)
        #expect(applier.pending?.tick == 1)

        applier.apply(t)
        #expect(applier.pending?.tick == 2)

        applier.apply(t)
        #expect(applier.pending?.tick == 3)
    }

    @Test
    @MainActor
    func consumeClearsPending() {
        let applier = TemplateApplier()
        let t = Template(title: "t", body: "hello", hashtags: [])

        applier.apply(t)
        #expect(applier.pending != nil)

        applier.consume()
        #expect(applier.pending == nil)
    }

    @Test
    @MainActor
    func applyAfterConsumeStartsTickAfterPriorMax() {
        let applier = TemplateApplier()
        let t = Template(title: "t", body: "hello", hashtags: [])

        applier.apply(t)
        applier.consume()
        applier.apply(t)

        #expect(applier.pending?.tick == 2)
    }

    @Test
    func pendingEquatableHonorsAllFields() {
        let base = TemplateApplier.Pending(body: "x", hashtags: ["a"], tick: 1)
        // Same fields → equal
        #expect(base == TemplateApplier.Pending(body: "x", hashtags: ["a"], tick: 1))
        // Different body → not equal
        #expect(base != TemplateApplier.Pending(body: "y", hashtags: ["a"], tick: 1))
        // Different hashtags → not equal
        #expect(base != TemplateApplier.Pending(body: "x", hashtags: ["b"], tick: 1))
        // Different tick → not equal
        #expect(base != TemplateApplier.Pending(body: "x", hashtags: ["a"], tick: 2))
    }
}
