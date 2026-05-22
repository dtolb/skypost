// CameraCaptureView — full-screen sheet that owns CameraSession's lifetime.
//
// Viewfinder: full-bleed preview framed to the selected ratio/orientation,
// with native-style zoom chips and capture controls. Review: captured photo
// at its actual output aspect, with Retake + Use Photo. Denied/unavailable:
// focused recovery cards.

#if os(iOS)

import SwiftUI
import AVFoundation
import UIKit
import DesignSystem

public struct CameraCaptureView: View {

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
            let previewSize = session.configuration.previewSize(fitting: geo.size)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    CameraPreviewLayer(session: session.session) { previewLayer in
                        session.attachRotationCoordinator(previewLayer: previewLayer)
                    }
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) { cancelBar }
            .overlay(alignment: .top) { modeBar }
            .overlay(alignment: .bottom) { zoomBar.padding(.bottom, 128) }
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

    private var modeBar: some View {
        VStack(spacing: 12) {
            Picker("Ratio", selection: ratioBinding) {
                ForEach(CameraCaptureRatio.allCases) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .accessibilityLabel("Photo ratio")

            HStack(spacing: 8) {
                ForEach(CameraCaptureOrientation.allCases) { orientation in
                    Button {
                        session.selectCaptureOrientation(orientation)
                    } label: {
                        Image(systemName: orientation.systemImage)
                            .font(.body.weight(.semibold))
                            .frame(width: 42, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(session.configuration.orientation == orientation ? .black : .white)
                    .background(
                        session.configuration.orientation == orientation
                            ? AnyShapeStyle(.white)
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .accessibilityLabel(orientation.accessibilityLabel)
                    .accessibilityAddTraits(session.configuration.orientation == orientation ? .isSelected : [])
                }
            }
        }
        .padding(.top, 64)
    }

    @ViewBuilder
    private var zoomBar: some View {
        if !session.zoomOptions.isEmpty {
            HStack(spacing: 8) {
                ForEach(session.zoomOptions) { option in
                    Button {
                        session.selectZoomOption(option)
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 44, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(session.selectedZoomOption == option ? .black : .white)
                    .background(
                        session.selectedZoomOption == option
                            ? AnyShapeStyle(.white)
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .accessibilityLabel("Zoom \(option.label)")
                    .accessibilityAddTraits(session.selectedZoomOption == option ? .isSelected : [])
                }
            }
        }
    }

    private var shutterBar: some View {
        VStack(spacing: 12) {
            if case .failed(let msg) = session.state {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.error)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .accessibilityLabel(msg)
            }
            Button {
                session.capture()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 4)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                }
                .frame(width: 84, height: 84)
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
            let previewSize = reviewSize(width: width, height: height, fitting: geo.size)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.gray)
                        .frame(width: previewSize.width, height: previewSize.height)
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

    private var ratioBinding: Binding<CameraCaptureRatio> {
        Binding {
            session.configuration.ratio
        } set: { ratio in
            session.selectCaptureRatio(ratio)
        }
    }

    private func reviewSize(width: Int, height: Int, fitting bounds: CGSize) -> CGSize {
        let aspect = CameraAspectRatio(width: width, height: height).value
        let widthBoundedHeight = bounds.width / aspect
        if widthBoundedHeight <= bounds.height {
            return CGSize(width: bounds.width, height: widthBoundedHeight)
        }

        return CGSize(width: bounds.height * aspect, height: bounds.height)
    }

    // MARK: - Cards

    private var permissionDeniedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
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
                .accessibilityHidden(true)
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
                .accessibilityHidden(true)
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
    CameraCaptureView { _, _, _ in }
}

#endif
