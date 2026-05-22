// CameraPreviewLayer — UIViewRepresentable wrapping AVCaptureVideoPreviewLayer.
// Pattern 2 from axiom-media camera-capture.md, adapted for our CameraSession.
//
// The `onPreviewReady` callback fires once the preview layer is mounted so
// CameraSession can attach its RotationCoordinator (which needs the layer
// reference). Fires on the main actor.

#if os(iOS)

import SwiftUI
import AVFoundation

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    let onPreviewReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            onPreviewReady(view.previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#endif
