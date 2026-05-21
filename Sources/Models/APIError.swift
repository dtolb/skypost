// APIError — error surface for the Bluesky module / APIClient actor.
//
// Real cases will be added in the next dispatch when ATProtoKit is wired up.

import Foundation

public enum APIError: Error, Sendable, Equatable {
    /// The method exists but has not yet been implemented in this dispatch.
    case notImplemented
    /// Wrapped lower-level error string (used until typed cases are added).
    case underlying(String)
}
