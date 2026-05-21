import Foundation

/// One attached image, post-encode. Owned by `ComposeView`'s `@State`
/// (no SwiftData backing in Phase C).
public struct ComposeAttachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let jpegData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// `var` because the editor two-way-binds a `TextField` to it;
    /// everything else is `let` (immutable post-encode).
    public var altText: String

    public init(
        id: UUID = UUID(),
        jpegData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        altText: String = ""
    ) {
        self.id = id
        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.altText = altText
    }
}
