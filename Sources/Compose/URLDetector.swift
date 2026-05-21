import Foundation

/// Finds the first URL in composer text using NSDataDetector — the same
/// machinery iOS uses for Messages / Mail link autodetection, so the
/// edge cases (trailing punctuation, schemeless hosts, IDN, fragments)
/// already work the way users expect.
///
/// Caseless enum so callers can't instantiate it.
public enum URLDetector {

    private static let detector: NSDataDetector = {
        // try! is safe: `.link` is a documented OptionSet value; the
        // initializer only throws for *invalid* checking types.
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    /// Returns the first URL found in `text`, or nil if none.
    public static func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range)
            .lazy
            .compactMap(\.url)
            .first
    }
}
