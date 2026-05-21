import Foundation

/// Pure helpers for the composer's send-eligibility / counter UI.
/// Lives in Compose (not Models) because it's view-adjacent — no other
/// module needs it. Caseless enum so callers can't init it.
public enum ComposeText {
    public static let graphemeLimit: Int = 300

    /// Count graphemes the way the user perceives them. Swift `String.count`
    /// is grapheme-clustered, which is what we want — emoji-with-skin-tone,
    /// flag sequences, ZWJ families all count as one.
    public static func graphemeCount(_ text: String) -> Int {
        text.count
    }

    /// Whitespace-trimmed and within the limit.
    public static func isSubmittable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return graphemeCount(text) <= graphemeLimit
    }

    /// Remaining graphemes (negative when the user has typed past the cap).
    public static func remaining(_ text: String) -> Int {
        graphemeLimit - graphemeCount(text)
    }

    /// Bluesky caps images per post at 4 (architecture §8.3).
    public static let attachmentLimit: Int = 4

    /// Whether another attachment can still be added.
    public static func canAttach(currentCount: Int) -> Bool {
        currentCount < attachmentLimit
    }

    /// Send-eligibility for text + attachments. Empty attachments list
    /// keeps the text-only path working; non-empty requires every
    /// attachment to carry non-blank alt text (accessibility gate,
    /// architecture §2 correction to v1's hard-coded alt).
    public static func isSubmittable(
        text: String,
        attachments: [ComposeAttachment]
    ) -> Bool {
        isSubmittable(text)
            && attachments.count <= attachmentLimit
            && attachments.allSatisfy { !$0.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
