import Testing
@testable import Compose

@Suite("Compose module wires up")
struct ComposeModuleTests {
    @Test
    func moduleNameIsCompose() {
        #expect(ComposeFeature.moduleName == "Compose")
    }
}
