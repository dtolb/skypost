import Foundation
import CoreGraphics

public struct CameraZoomOption: Identifiable, Sendable, Equatable {
    public let zoomFactor: CGFloat
    public let displayZoomFactor: CGFloat
    public let label: String

    public var id: String { String(format: "%.3f", Double(zoomFactor)) }

    public init(zoomFactor: CGFloat, displayZoomFactor: CGFloat, label: String) {
        self.zoomFactor = zoomFactor
        self.displayZoomFactor = displayZoomFactor
        self.label = label
    }

    public static func options(
        minZoomFactor: CGFloat,
        maxZoomFactor: CGFloat,
        switchOverZoomFactors: [CGFloat],
        displayMultiplier: CGFloat
    ) -> [CameraZoomOption] {
        let rawFactors = ([minZoomFactor] + switchOverZoomFactors)
            .map { min(max($0, minZoomFactor), maxZoomFactor) }
            .filter { $0 > 0 }
            .sorted()

        let uniqueFactors = rawFactors.reduce(into: [CGFloat]()) { result, factor in
            guard !result.contains(where: { abs($0 - factor) < 0.001 }) else { return }
            result.append(factor)
        }

        return uniqueFactors.map { factor in
            let displayZoom = factor * displayMultiplier
            return CameraZoomOption(
                zoomFactor: factor,
                displayZoomFactor: displayZoom,
                label: Self.label(forDisplayZoom: displayZoom)
            )
        }
    }

    public static func defaultOption(in options: [CameraZoomOption]) -> CameraZoomOption? {
        options.min { lhs, rhs in
            abs(lhs.displayZoomFactor - 1) < abs(rhs.displayZoomFactor - 1)
        }
    }

    private static func label(forDisplayZoom displayZoom: CGFloat) -> String {
        if abs(displayZoom.rounded() - displayZoom) < 0.05 {
            return "\(Int(displayZoom.rounded()))x"
        }

        let rounded = (displayZoom * 10).rounded() / 10
        return String(format: "%.1fx", Double(rounded))
    }
}
