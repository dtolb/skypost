// APIError — error surface for the Bluesky module / APIClient actor.
//
// Kept small and Sendable. Lower-level ATProtoKit errors are flattened to
// strings here so they don't leak across module boundaries (UI modules
// must not import ATProtoKit per §5).

import Foundation

public enum APIError: Error, Sendable, Equatable {
    /// The method exists but has not yet been implemented in this dispatch.
    case notImplemented

    /// A request was made before an authenticated session existed.
    case notAuthenticated

    /// Sign-in failed at the PDS — wrong handle/password, network, 2FA prompt, etc.
    case authenticationFailed(reason: String)

    /// `createPostRecord` failed at the PDS or in the lexicon layer.
    case postFailed(reason: String)

    /// Wrapped lower-level error string.
    case underlying(String)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature isn't wired up yet."
        case .notAuthenticated:
            return "You're not signed in."
        case .authenticationFailed(let reason):
            return "Sign-in failed: \(reason)"
        case .postFailed(let reason):
            return "Couldn't post: \(reason)"
        case .underlying(let reason):
            return reason
        }
    }
}
