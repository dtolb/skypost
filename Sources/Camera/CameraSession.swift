// CameraSession — @MainActor @Observable wrapper around AVCaptureSession.
//
// All configuration and start/stop hops to a private serial sessionQueue
// per axiom-media (startRunning blocks for seconds — never on main).
// AVCapturePhotoCaptureDelegate methods are nonisolated; they finish the
// pipeline on the session queue (crop + JPEG encode are CPU-bound, not
// MainActor-relevant) then publish the result back to MainActor.
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

    public let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.dtolb.BlueSkyTemplates.camera.session",
                                             qos: .userInitiated)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var interruptionObservers: [NSObjectProtocol] = []

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

    // MARK: - Capture

    public func capture() {
        guard case .live = state else { return }
        state = .capturing
        let rotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
        sessionQueue.async { [photoOutput] in
            if let connection = photoOutput.connection(with: .video) {
                connection.videoRotationAngle = rotationAngle
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Configuration

    private func configureAndStart() async {
        // Check device availability up-front; the iPhone 17 simulator has no
        // back wide-angle camera and would otherwise fail silently.
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            state = .unavailable
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                let configured = configureSessionSync()
                DispatchQueue.main.async {
                    if configured {
                        // session.startRunning() is a blocking call; do it on the queue.
                        self.sessionQueue.async {
                            if !self.session.isRunning { self.session.startRunning() }
                        }
                        self.state = .live
                    } else {
                        self.state = .failed(message: "Couldn't start camera.")
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Returns true on success. Runs on sessionQueue.
    private func configureSessionSync() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            Log.media.error("camera input add failed")
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            Log.media.error("camera photo output add failed")
            return false
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // RotationCoordinator setup happens on main — the preview layer it
        // observes is owned by the SwiftUI representable. Done by caller via
        // attachRotationCoordinator(...) after the preview is mounted.
        return true
    }

    /// Wired from `CameraPreviewLayer.makeUIView` once the preview layer exists.
    /// Sets up the iOS 17+ RotationCoordinator so preview + capture stay correctly
    /// oriented even when the device is face-up / face-down.
    public func attachRotationCoordinator(previewLayer: AVCaptureVideoPreviewLayer) {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak previewLayer] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor [weak previewLayer] in
                previewLayer?.connection?.videoRotationAngle = angle
            }
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

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSession: AVCapturePhotoCaptureDelegate {

    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Log.media.error("photo capture failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't take photo.")
            }
            return
        }

        guard let jpegData = photo.fileDataRepresentation() else {
            Log.media.error("nil photo data representation")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't read photo data.")
            }
            return
        }

        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Log.media.error("photo decode failed")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't decode photo.")
            }
            return
        }

        let squareImage = CenterSquareCrop.crop(fullImage)

        let encoded: (data: Data, pixelWidth: Int, pixelHeight: Int)
        do {
            encoded = try ImageProcessor.encodeJPEG(cgImage: squareImage, maxBytes: 1_000_000)
        } catch {
            Log.media.error("encode failed: \(String(describing: error), privacy: .public)")
            Task { @MainActor [weak self] in
                self?.state = .failed(message: "Couldn't encode photo.")
            }
            return
        }

        Task { @MainActor [weak self] in
            self?.state = .captured(
                jpegData: encoded.data,
                pixelWidth: encoded.pixelWidth,
                pixelHeight: encoded.pixelHeight
            )
        }
    }
}

#endif
