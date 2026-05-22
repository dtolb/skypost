import Testing
@testable import Camera

@Suite("Camera zoom options")
struct CameraZoomOptionTests {

    @Test
    func tripleCameraOptionsUseDisplayMultiplierForNativeLabels() {
        let options = CameraZoomOption.options(
            minZoomFactor: 1,
            maxZoomFactor: 15,
            switchOverZoomFactors: [2, 6],
            displayMultiplier: 0.5
        )

        #expect(options.map(\.label) == ["0.5x", "1x", "3x"])
        #expect(options.map(\.zoomFactor) == [1, 2, 6])
    }

    @Test
    func defaultSelectionPrefersOneTimesDisplayZoom() throws {
        let options = CameraZoomOption.options(
            minZoomFactor: 1,
            maxZoomFactor: 15,
            switchOverZoomFactors: [2, 6],
            displayMultiplier: 0.5
        )

        let selected = try #require(CameraZoomOption.defaultOption(in: options))

        #expect(selected.label == "1x")
        #expect(selected.zoomFactor == 2)
    }

    @Test
    func singleCameraFallsBackToOneOption() {
        let options = CameraZoomOption.options(
            minZoomFactor: 1,
            maxZoomFactor: 10,
            switchOverZoomFactors: [],
            displayMultiplier: 1
        )

        #expect(options.map(\.label) == ["1x"])
        #expect(CameraZoomOption.defaultOption(in: options) == options.first)
    }

    @Test
    func duplicateSwitchOverFactorsAreRemoved() {
        let options = CameraZoomOption.options(
            minZoomFactor: 1,
            maxZoomFactor: 10,
            switchOverZoomFactors: [2, 2, 4],
            displayMultiplier: 1
        )

        #expect(options.map(\.zoomFactor) == [1, 2, 4])
    }
}
