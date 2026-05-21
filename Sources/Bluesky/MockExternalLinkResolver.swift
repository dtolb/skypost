// MockExternalLinkResolver — deterministic fixture impl for previews + tests.
//
// Three fixture URLs cover the three branches the UI cares about:
// success-without-thumb, success-with-thumb, and badMetadata. The live
// LPMetadataProvider-backed resolver lands in Phase F3; this stub keeps
// ComposeView previews and the @Suite tests stable.

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Canned responses for SwiftUI previews and future UI tests. Three
/// fixture URLs — see the @Suite tests for the contracts.
public struct MockExternalLinkResolver: ExternalLinkResolver {

    public init() {}

    public func resolve(url: URL) async throws -> ExternalLinkCard {
        switch url.absoluteString {
        case "https://example.com":
            return ExternalLinkCard(
                url: url,
                title: "Example Domain",
                description: "Reserved for documentation.",
                thumbnailJPEG: nil
            )
        case "https://anthropic.com":
            return ExternalLinkCard(
                url: url,
                title: "Anthropic",
                description: "AI safety company.",
                thumbnailJPEG: Self.fixtureJPEG
            )
        case "https://broken.example":
            throw ExternalLinkResolverError.badMetadata
        default:
            throw ExternalLinkResolverError.badMetadata
        }
    }

    /// Minimal real JPEG — a 1×1 gray pixel encoded via ImageIO at load
    /// time. Built programmatically rather than hand-typed so the bytes
    /// always decode through `CGImageSourceCreateWithData` (the path any
    /// future thumbnail-render code will exercise). Built once and held
    /// for the process lifetime.
    private static let fixtureJPEG: Data = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            // Programmer-error: building a 1×1 RGB context cannot fail
            // on any supported platform. If it ever does, return empty
            // Data so a downstream nil-check still distinguishes
            // "thumbnail attempted" from "no thumbnail".
            return Data()
        }
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = ctx.makeImage() else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return Data() }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality as String: 0.95 as CFNumber
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }()
}
