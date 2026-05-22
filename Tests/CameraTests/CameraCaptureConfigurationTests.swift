import CoreGraphics
import Testing
@testable import Camera

@Suite("Camera capture configuration")
struct CameraCaptureConfigurationTests {

    @Test
    func squareRatioIgnoresOrientationForTargetAspect() {
        let portrait = CameraCaptureConfiguration(ratio: .square, orientation: .portrait)
        let landscape = CameraCaptureConfiguration(ratio: .square, orientation: .landscape)

        #expect(portrait.targetAspectRatio == CameraAspectRatio(width: 1, height: 1))
        #expect(landscape.targetAspectRatio == CameraAspectRatio(width: 1, height: 1))
    }

    @Test
    func defaultRatioUsesPortraitPhotoAspect() {
        let configuration = CameraCaptureConfiguration(ratio: .defaultPhoto, orientation: .portrait)

        #expect(configuration.targetAspectRatio == CameraAspectRatio(width: 3, height: 4))
    }

    @Test
    func defaultRatioUsesLandscapePhotoAspect() {
        let configuration = CameraCaptureConfiguration(ratio: .defaultPhoto, orientation: .landscape)

        #expect(configuration.targetAspectRatio == CameraAspectRatio(width: 4, height: 3))
    }

    @Test
    func previewSizeFitsInsideAvailableBounds() {
        let configuration = CameraCaptureConfiguration(ratio: .defaultPhoto, orientation: .landscape)

        let size = configuration.previewSize(fitting: CGSize(width: 390, height: 844))

        #expect(abs(size.width - 390) <= 0.001)
        #expect(abs(size.height - 292.5) <= 0.001)
    }
}
