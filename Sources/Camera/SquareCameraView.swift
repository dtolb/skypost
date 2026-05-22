// SquareCameraView — full-screen sheet that owns CameraSession's lifetime.
//
// Viewfinder: full-bleed preview with opaque top + bottom letterbox so the
// visible window is exactly square. Shutter button bottom-center, Cancel
// top-leading.
// Review: the captured square photo at full bleed, with Retake + Use Photo.
// Denied: settings-redirect card. Unavailable: device-has-no-camera card.

#if os(iOS)

import SwiftUI
import AVFoundation
import UIKit
import DesignSystem

public struct SquareCameraView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var session = CameraSession()

    /// Called when the user taps Use Photo on the review screen. The sheet
    /// dismisses itself after the callback returns.
    let onCapture: (Data, Int, Int) -> Void

    public init(onCapture: @escaping (Data, Int, Int) -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .task {
            // Re-check every time the sheet appears so a user who toggled
            // permission in Settings comes back to a working viewfinder.
            await session.requestPermissionAndStart()
        }
        .onDisappear {
            session.stop()
        }
    }

    // MARK: - State-routed content

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .idle, .resolvingPermission:
            ProgressView().tint(.white)
        case .denied:
            permissionDeniedCard
        case .unavailable:
            unavailableCard
        case .live, .capturing:
            viewfinder
        case .captured(let data, let w, let h):
            reviewScreen(data: data, width: w, height: h)
        case .failed(let message):
            failureCard(message: message)
        }
    }

    // MARK: - Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    CameraPreviewLayer(session: session.session) { previewLayer in
                        session.attachRotationCoordinator(previewLayer: previewLayer)
                    }
                    .frame(width: side, height: side)
                    .clipped()
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) { cancelBar }
            .overlay(alignment: .bottom) { shutterBar }
        }
    }

    private var cancelBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("Cancel and close camera")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var shutterBar: some View {
        VStack(spacing: 12) {
            if case .failed(let msg) = session.state {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.error)
                    .font(.callout)
                    .padding(.horizontal, 16)
            }
            Button {
                session.capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.6), lineWidth: 4)
                            .frame(width: 84, height: 84)
                    )
            }
            .disabled(!isShutterEnabled)
            .accessibilityLabel("Take photo")
            .padding(.bottom, 32)
        }
    }

    private var isShutterEnabled: Bool {
        if case .live = session.state { return true }
        return false
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewScreen(data: Data, width: Int, height: Int) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.gray)
                        .frame(width: side, height: side)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) {
                HStack(spacing: 24) {
                    Button("Retake") { session.resume() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Use Photo") {
                        onCapture(data, width, height)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 32)
            }
            .overlay(alignment: .top) { cancelBar }
        }
    }

    // MARK: - Cards

    private var permissionDeniedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
            Text("Camera access is off")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("BlueSky Templates needs camera access to take photos.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(32)
    }

    private var unavailableCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
            Text("No camera on this device")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("This device doesn't have a camera the app can access. Try on a physical iPhone or iPad.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func failureCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(BrandColor.error)
            Text(message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

// MARK: - Preview

#Preview("Camera — denied state") {
    SquareCameraView { _, _, _ in }
}

#endif
