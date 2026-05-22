// CameraPermissionResolver — pure resolution layer over the AVFoundation
// permission API. Injectable for tests (macOS has no AVCaptureDevice for
// camera).
//
// The resolver collapses Apple's 4-case AVAuthorizationStatus into the 2
// outcomes the UI actually cares about: .authorized (proceed) and .denied
// (show settings card). `.notDetermined` triggers a prompt; everything
// else is terminal.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Mirror of `AVAuthorizationStatus` that compiles cross-platform.
public enum CameraAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Resolved camera permission state — what the UI binds to.
public enum CameraPermissionState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Injection seam — the live impl wraps AVCaptureDevice; tests stub it.
public protocol CameraPermissionProviding: Sendable {
    func currentStatus() -> CameraAuthorizationStatus
    func requestAccess() async -> Bool
}

public enum CameraPermissionResolver {

    /// Returns the resolved state, prompting via `requestAccess` only when
    /// the current status is `.notDetermined`.
    public static func resolve(using provider: CameraPermissionProviding) async -> CameraPermissionState {
        switch provider.currentStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await provider.requestAccess()
            return granted ? .authorized : .denied
        }
    }
}

#if canImport(AVFoundation)

/// Production provider — wraps `AVCaptureDevice` directly.
public struct LiveCameraPermissionProvider: CameraPermissionProviding {

    public init() {}

    public func currentStatus() -> CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

#endif
