// HashtagParser — normalizes a free-form, comma-separated hashtag string.
//
// Lives as a free function (not a String extension or Template method)
// because the editor binds a single TextField to the raw string and only
// normalizes at save time. Future callers — e.g. the composer inheriting
// tags from a Template — will reuse the same parse.

import Foundation

/// Parses a comma-separated hashtag string into a normalized list:
/// splits on commas, trims whitespace, drops any leading `#` characters,
/// lowercases, drops empties, deduplicates preserving first-seen order.
public func parseHashtags(_ raw: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingHash = trimmed.drop(while: { $0 == "#" })
        let normalized = withoutLeadingHash.lowercased()
        if normalized.isEmpty { continue }
        if seen.insert(normalized).inserted {
            result.append(normalized)
        }
    }
    return result
}
