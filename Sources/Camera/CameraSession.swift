// CameraSession — @MainActor @Observable wrapper around AVCaptureSession.
//
// All configuration and start/stop hops to a private serial sessionQueue
// per axiom-media (startRunning blocks for seconds — never on main).
// AVCapturePhotoCaptureDelegate methods are nonisolated; they finish the
// pipeline off-main (crop + JPEG encode are CPU-bound, not MainActor-relevant)
// then publish the result back to MainActor.
//
// iOS-only: the entire type is gated by `#if os(iOS)` so macOS swift test
// runs of CameraTests don't try to import AVFoundation surfaces that
// behave differently on macOS (AVCaptureDevice exists but has no camera).

#if os(iOS)

import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import AppLogging
import Models
import Observation

@MainActor
@Observable
public final class CameraSession: NSObject {

    public enum State: Equatable {
        case idle                                  // before requestPermissionAndStart()
        case resolvingPermission
        case denied
        case unavailable                            // no camera device on this hardware
        case live                                   // viewfinder running, ready for shutter
        case capturing
        case captured(jpegData: Data, pixelWidth: Int, pixelHeight: Int)
        case failed(message: String)
    }

    public private(set) var state: State = .idle
    public private(set) var configuration = CameraCaptureConfiguration()
    public private(set) var zoomOptions: [CameraZoomOption] = []
    public private(set) var selectedZoomOption: CameraZoomOption?

    // Immutable AVFoundation refs are nonisolated so background-queue closures
    // can touch them without crossing actor boundaries. They're never reassigned,
    // and AVCaptureSession/AVCapturePhotoOutput are thread-safe for the calls we
    // make on sessionQueue.
    public nonisolated let session = AVCaptureSession()
    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private nonisolated let sessionQueue = DispatchQueue(
        label: "com.dtolb.BlueSkyTemplates.camera.session",
        qos: .userInitiated
    )
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var interruptionObservers: [NSObjectProtocol] = []
    private var inFlightCaptures: [Int64: CameraPhotoCaptureProcessor] = [:]

    private let permissionProvider: any CameraPermissionProviding

    public init(permissionProvider: any CameraPermissionProviding = LiveCameraPermissionProvider()) {
        self.permissionProvider = permissionProvider
        super.init()
        setupInterruptionHandling()
    }

    deinit {
        // CameraSession is @MainActor, so its deinit runs on MainActor when held
        // by a SwiftUI @State (the only intended retainer). assumeIsolated lets
        // the compiler verify the MainActor access without the property-isolation
        // diagnostic that Swift 6's nonisolated-by-default deinit triggers.
        MainActor.assumeIsolated {
            interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    // MARK: - Lifecycle

    public func requestPermissionAndStart() async {
        state = .resolvingPermission
        let resolved = await CameraPermissionResolver.resolve(using: permissionProvider)
        switch resolved {
        case .authorized:
            await configureAndStart()
        case .denied:
            state = .denied
        case .notDetermined:
            // Resolver guarantees a terminal state, but be defensive.
            state = .denied
        }
    }

    public func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    public func resume() {
        // After Retake: state is .captured(...); flip back to .live and the
        // preview keeps streaming (session never stopped).
        state = .live
    }

    public func selectCaptureRatio(_ ratio: CameraCaptureRatio) {
        guard configuration.ratio != ratio else { return }
        configuration.ratio = ratio
        applyDynamicAspectRatio(configuration)
    }

    public func selectCaptureOrientation(_ orientation: CameraCaptureOrientation) {
        guard configuration.orientation != orientation else { return }
        configuration.orientation = orientation
        applyDynamicAspectRatio(configuration)
    }

    public func selectZoomOption(_ option: CameraZoomOption) {
        guard selectedZoomOption != option else { return }
        selectedZoomOption = option
        applyZoomFactor(option.zoomFactor)
    }

    // MARK: - Capture

    public func capture() {
        guard case .live = state else { return }
        state = .capturing
        let captureConfiguration = configuration
        let rotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        let captureID = settings.uniqueID
        let processor = CameraPhotoCaptureProcessor(configuration: captureConfiguration) { [weak self] result in
            Task { @MainActor in
                self?.finishCapture(id: captureID, result: result)
            }
        }
        inFlightCaptures[captureID] = processor

        sessionQueue.async { [photoOutput] in
            if let connection = photoOutput.connection(with: .video) {
                connection.videoRotationAngle = rotationAngle
            }
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: - Configuration

    private func configureAndStart() async {
        // Check device availability up-front; the iPhone 17 simulator has no
        // back wide-angle camera and would otherwise fail silently.
        guard Self.preferredBackCamera() != nil else {
            state = .unavailable
            return
        }
        let initialConfiguration = configuration
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<SessionConfigurationResult, Never>) in
            sessionQueue.async { [self] in
                let result = configureSessionSync(configuration: initialConfiguration)
                continuation.resume(returning: result)
            }
        }
        if result.isConfigured {
            zoomOptions = result.zoomOptions
            selectedZoomOption = result.selectedZoomOption
            // session.startRunning() is a blocking call; do it on the queue.
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
            state = .live
        } else {
            state = .failed(message: "Couldn't start camera.")
        }
    }

    /// Returns true on success. Runs on sessionQueue.
    private nonisolated func configureSessionSync(configuration: CameraCaptureConfiguration) -> SessionConfigurationResult {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        let camera: AVCaptureDevice
        if let existingInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput {
            camera = existingInput.device
        } else {
            guard let preferredCamera = Self.preferredBackCamera(),
                  let input = try? AVCaptureDeviceInput(device: preferredCamera),
                  session.canAddInput(input) else {
                Log.media.error("camera input add failed")
                return .failed
            }
            session.addInput(input)
            camera = preferredCamera
        }

        if !session.outputs.contains(where: { $0 === photoOutput }) {
            guard session.canAddOutput(photoOutput) else {
                Log.media.error("camera photo output add failed")
                return .failed
            }
            session.addOutput(photoOutput)
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        Self.applyDynamicAspectRatioSync(configuration, to: camera)

        let zoomOptions = Self.makeZoomOptions(for: camera)
        let selectedZoomOption = CameraZoomOption.defaultOption(in: zoomOptions)
        if let selectedZoomOption {
            Self.applyZoomFactorSync(selectedZoomOption.zoomFactor, to: camera, animated: false)
        }

        // RotationCoordinator setup happens on main — the preview layer it
        // observes is owned by the SwiftUI representable. Done by caller via
        // attachRotationCoordinator(...) after the preview is mounted.
        return SessionConfigurationResult(
            isConfigured: true,
            zoomOptions: zoomOptions,
            selectedZoomOption: selectedZoomOption
        )
    }

    /// Wired from `CameraPreviewLayer.makeUIView` once the preview layer exists.
    /// Sets up the iOS 17+ RotationCoordinator for capture-time EXIF orientation.
    ///
    /// The app is portrait-only (UISupportedInterfaceOrientations in Info.plist),
    /// so the preview layer's videoRotationAngle is set once here and never needs
    /// to change — there's no KVO observation of videoRotationAngleForHorizonLevelPreview.
    /// Capture rotation still flows through the coordinator's
    /// videoRotationAngleForHorizonLevelCapture in `capture()`, so face-up /
    /// face-down EXIF orientation remains correct for the saved JPEG.
    public func attachRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
    }

    private func applyDynamicAspectRatio(_ configuration: CameraCaptureConfiguration) {
        sessionQueue.async { [session] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            Self.applyDynamicAspectRatioSync(configuration, to: device)
        }
    }

    private func applyZoomFactor(_ zoomFactor: CGFloat) {
        sessionQueue.async { [session] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            Self.applyZoomFactorSync(zoomFactor, to: device, animated: true)
        }
    }

    private func finishCapture(id: Int64, result: CameraCaptureProcessingResult) {
        inFlightCaptures[id] = nil
        switch result {
        case .success(let data, let width, let height):
            state = .captured(jpegData: data, pixelWidth: width, pixelHeight: height)
        case .failure(let message):
            state = .failed(message: message)
        }
    }

    private nonisolated static func preferredBackCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
        ]

        for deviceType in deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                return device
            }
        }

        return nil
    }

    private nonisolated static func makeZoomOptions(for device: AVCaptureDevice) -> [CameraZoomOption] {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let options = CameraZoomOption.options(
            minZoomFactor: device.minAvailableVideoZoomFactor,
            maxZoomFactor: device.maxAvailableVideoZoomFactor,
            switchOverZoomFactors: switchOvers,
            displayMultiplier: device.displayVideoZoomFactorMultiplier
        )

        if options.isEmpty {
            return [
                CameraZoomOption(
                    zoomFactor: device.videoZoomFactor,
                    displayZoomFactor: device.videoZoomFactor * device.displayVideoZoomFactorMultiplier,
                    label: "1x"
                ),
            ]
        }

        return options
    }

    private nonisolated static func applyZoomFactorSync(
        _ zoomFactor: CGFloat,
        to device: AVCaptureDevice,
        animated: Bool
    ) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let clampedZoom = min(
                max(zoomFactor, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )
            device.cancelVideoZoomRamp()
            if animated {
                device.ramp(toVideoZoomFactor: clampedZoom, withRate: 8)
            } else {
                device.videoZoomFactor = clampedZoom
            }
        } catch {
            Log.media.error("camera zoom configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func applyDynamicAspectRatioSync(
        _ configuration: CameraCaptureConfiguration,
        to device: AVCaptureDevice
    ) {
        let aspectRatio = configuration.avCaptureAspectRatio
        guard device.activeFormat.supportedDynamicAspectRatios.contains(aspectRatio) else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setDynamicAspectRatio(aspectRatio) { _, error in
                if let error {
                    Log.media.error("camera dynamic aspect ratio failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Log.media.error("camera aspect ratio configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Interruption handling

    private func setupInterruptionHandling() {
        let interrupted = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { notification in
            let reason: String
            if let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
                reason = "\(raw)"
            } else {
                reason = "unknown"
            }
            Log.media.info("camera session interrupted: \(reason, privacy: .public)")
            // We don't flip state — the UI shows a banner via its own observer.
        }
        interruptionObservers.append(interrupted)

        let ended = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { _ in
            Log.media.info("camera session interruption ended")
        }
        interruptionObservers.append(ended)
    }
}

private struct SessionConfigurationResult: Sendable {
    let isConfigured: Bool
    let zoomOptions: [CameraZoomOption]
    let selectedZoomOption: CameraZoomOption?

    static let failed = SessionConfigurationResult(
        isConfigured: false,
        zoomOptions: [],
        selectedZoomOption: nil
    )
}

private enum CameraCaptureProcessingResult: Sendable {
    case success(data: Data, pixelWidth: Int, pixelHeight: Int)
    case failure(String)
}

// MARK: - AVCapturePhotoCaptureDelegate

private final class CameraPhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let configuration: CameraCaptureConfiguration
    private let completion: @Sendable (CameraCaptureProcessingResult) -> Void

    init(
        configuration: CameraCaptureConfiguration,
        completion: @escaping @Sendable (CameraCaptureProcessingResult) -> Void
    ) {
        self.configuration = configuration
        self.completion = completion
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Log.media.error("photo capture failed: \(error.localizedDescription, privacy: .public)")
            completion(.failure("Couldn't take photo."))
            return
        }

        guard let jpegData = photo.fileDataRepresentation() else {
            Log.media.error("nil photo data representation")
            completion(.failure("Couldn't read photo data."))
            return
        }

        guard let fullImage = OrientedCGImageDecoder.decode(jpegData) else {
            Log.media.error("photo decode failed")
            completion(.failure("Couldn't decode photo."))
            return
        }

        let framedImage = CenterAspectCrop.crop(fullImage, aspectRatio: configuration.targetAspectRatio)

        let encoded: (data: Data, pixelWidth: Int, pixelHeight: Int)
        do {
            encoded = try ImageProcessor.encodeJPEG(cgImage: framedImage, maxBytes: 1_000_000)
        } catch {
            Log.media.error("encode failed: \(String(describing: error), privacy: .public)")
            completion(.failure("Couldn't encode photo."))
            return
        }

        completion(.success(
            data: encoded.data,
            pixelWidth: encoded.pixelWidth,
            pixelHeight: encoded.pixelHeight
        ))
    }
}

private extension CameraCaptureConfiguration {
    var avCaptureAspectRatio: AVCaptureDevice.AspectRatio {
        switch ratio {
        case .square:
            return .ratio1x1
        case .defaultPhoto:
            switch orientation {
            case .portrait:
                return .ratio3x4
            case .landscape:
                return .ratio4x3
            }
        }
    }
}

#endif
