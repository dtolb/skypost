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

    /// Sign-in failed at the PDS. The reason is a closed enum so UI can render
    /// localized copy without ever seeing the raw SDK error string.
    case authenticationFailed(reason: AuthFailureReason)

    /// Session restore failed transiently — a refresh token is in the Keychain
    /// but the network/PDS call to refresh it failed. Distinct from
    /// `.notAuthenticated`: the user should be offered retry, not a fresh login.
    case restoreFailed(reason: AuthFailureReason)

    /// `createPostRecord` failed at the PDS or in the lexicon layer.
    case postFailed(reason: String)

    /// Wrapped lower-level error string.
    case underlying(String)
}

/// Closed set of user-facing reasons for an auth-related failure. Mapped from
/// `ATProtoError` / `URLError` shapes inside the `Bluesky` module so UI never
/// sees raw SDK strings.
public enum AuthFailureReason: Sendable, Equatable {
    /// Wrong handle or wrong app password.
    case badCredentials
    /// Network unreachable, request timed out, etc.
    case network
    /// PDS returned HTTP 429 (or equivalent).
    case rateLimited
    /// PDS requires a 2FA / one-time code we don't collect yet.
    case twoFactorRequired
    /// Anything else we couldn't classify. Raw SDK detail is logged separately.
    case unknown
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature isn't wired up yet."
        case .notAuthenticated:
            return "You're not signed in."
        case .authenticationFailed(let reason):
            return "Sign-in failed: \(reason.userFacingDescription)"
        case .restoreFailed(let reason):
            return "Couldn't restore your session: \(reason.userFacingDescription)"
        case .postFailed(let reason):
            return "Couldn't post: \(reason)"
        case .underlying(let reason):
            return reason
        }
    }
}

extension AuthFailureReason {
    /// English copy for the failure reason. Kept in `Models` so any UI
    /// surface can format `APIError` without re-deriving the strings.
    public var userFacingDescription: String {
        switch self {
        case .badCredentials:
            return "Check your handle and app password."
        case .network:
            return "Network connection failed. Try again."
        case .rateLimited:
            return "Too many attempts. Wait a moment and try again."
        case .twoFactorRequired:
            return "This account requires a one-time code, which this app doesn't support yet."
        case .unknown:
            return "Something went wrong. Try again."
        }
    }
}
