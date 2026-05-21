// AuthProvider — protocol for swapping auth strategies (§7.2).
//
// At v2 launch the only implementation is AppPasswordAuth. When OAuth lands
// (per §7.3 triggers), add OAuthAuth next to it and swap in the
// composition root. UI never knows the difference.

import Foundation
import Models

public protocol AuthProvider: Sendable {

    /// Interactive sign-in. The provider is free to ignore `secret` for
    /// strategies that don't use one (e.g. OAuth).
    func session(handle: String, secret: String?) async throws -> SessionInfo

    /// Cold-launch restore from persistent storage (Keychain).
    ///
    /// - Returns: a live `SessionInfo` if a session was restored, or `nil` if
    ///   no stored session is available (first launch, after sign-out, or
    ///   past the refresh window — all of which land the user at `.signedOut`
    ///   cleanly with no UI noise).
    /// - Throws: when a stored session *exists* but the refresh attempt
    ///   failed transiently (network, server 5xx). Callers should surface
    ///   this as `.error` with a retry affordance, not silently log out.
    func restore() async throws -> SessionInfo?

    /// In-session token rollover. Called when the access token expires
    /// mid-session (e.g. on a 401 from a write path).
    func refresh(_ session: SessionInfo) async throws -> SessionInfo

    /// Revoke the session on the PDS and clear local state.
    func revoke(_ session: SessionInfo) async throws
}
