import Testing
import Compose

@Suite("ComposeText validator")
struct ComposeTextTests {

    @Test
    func graphemeCountEmptyReturnsZero() {
        #expect(ComposeText.graphemeCount("") == 0)
    }

    @Test
    func graphemeCountCountsClustersNotCodeUnits() {
        #expect(ComposeText.graphemeCount("👨‍👩‍👧‍👦") == 1)
        #expect(ComposeText.graphemeCount("é") == 1)
        #expect(ComposeText.graphemeCount("e\u{0301}") == 1)
        #expect(ComposeText.graphemeCount("abc") == 3)
    }

    @Test
    func isSubmittableRejectsBlank() {
        #expect(ComposeText.isSubmittable("") == false)
        #expect(ComposeText.isSubmittable("   ") == false)
        #expect(ComposeText.isSubmittable("\n\n") == false)
    }

    @Test
    func isSubmittableRejectsOverLimit() {
        #expect(ComposeText.isSubmittable(String(repeating: "a", count: 301)) == false)
        // Trimmed-empty wrapper around long text — leading/trailing whitespace
        // shouldn't sneak past the blank guard, but the over-limit branch
        // should still reject in any case.
        let padded = "   " + String(repeating: "a", count: 301) + "   "
        #expect(ComposeText.isSubmittable(padded) == false)
    }

    @Test
    func isSubmittableAcceptsExactly300() {
        #expect(ComposeText.isSubmittable(String(repeating: "a", count: 300)) == true)
    }

    @Test
    func remainingIsNegativeWhenOver() {
        #expect(ComposeText.remaining(String(repeating: "a", count: 305)) == -5)
        #expect(ComposeText.remaining(String(repeating: "a", count: 300)) == 0)
        #expect(ComposeText.remaining("") == 300)
    }
}
