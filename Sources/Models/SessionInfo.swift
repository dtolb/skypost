// SessionInfo — Sendable handle on an authenticated atproto session.
//
// The DID is the stable identifier. Never log it without
// `.private(mask: .hash)`; never log the handle without
// `.private(mask: .hash)` either — it's PII.

import Foundation

public struct SessionInfo: Sendable, Hashable, Codable {
    public let did: String
    public let handle: String

    public init(did: String, handle: String) {
        self.did = did
        self.handle = handle
    }
}
