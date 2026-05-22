import Testing
@testable import Camera

@Suite("Camera module sanity")
struct CameraModuleSanityTests {

    @Test
    func moduleImports() {
        // Trivial: if the module fails to compile, this whole file fails to build.
        // J1.A onwards replaces this with real test suites.
        #expect(true)
    }
}
