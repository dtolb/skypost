import CoreGraphics

public enum CameraCaptureRatio: String, CaseIterable, Sendable, Equatable, Identifiable {
    case defaultPhoto
    case square

    public var id: Self { self }

    public var label: String {
        switch self {
        case .defaultPhoto: return "Default"
        case .square:       return "1:1"
        }
    }
}

public enum CameraCaptureOrientation: String, CaseIterable, Sendable, Equatable, Identifiable {
    case portrait
    case landscape

    public var id: Self { self }

    public var accessibilityLabel: String {
        switch self {
        case .portrait:  return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    public var systemImage: String {
        switch self {
        case .portrait:  return "rectangle.portrait"
        case .landscape: return "rectangle.landscape"
        }
    }
}

public struct CameraAspectRatio: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "CameraAspectRatio dimensions must be positive")
        self.width = width
        self.height = height
    }

    public var value: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
}

public struct CameraCaptureConfiguration: Sendable, Equatable {
    public var ratio: CameraCaptureRatio
    public var orientation: CameraCaptureOrientation

    public init(
        ratio: CameraCaptureRatio = .defaultPhoto,
        orientation: CameraCaptureOrientation = .portrait
    ) {
        self.ratio = ratio
        self.orientation = orientation
    }

    public var targetAspectRatio: CameraAspectRatio {
        switch ratio {
        case .square:
            return CameraAspectRatio(width: 1, height: 1)
        case .defaultPhoto:
            switch orientation {
            case .portrait:
                return CameraAspectRatio(width: 3, height: 4)
            case .landscape:
                return CameraAspectRatio(width: 4, height: 3)
            }
        }
    }

    public func previewSize(fitting bounds: CGSize) -> CGSize {
        let aspect = targetAspectRatio.value
        let widthBoundedHeight = bounds.width / aspect
        if widthBoundedHeight <= bounds.height {
            return CGSize(width: bounds.width, height: widthBoundedHeight)
        }

        return CGSize(width: bounds.height * aspect, height: bounds.height)
    }
}
