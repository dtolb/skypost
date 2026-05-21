// AppPasswordAuth — the only AuthProvider impl at v2 launch.
//
// Delegates to the Bluesky module's APIClient. When OAuth lands per §7.3,
// drop an OAuthAuth in next to this file, swap in the composition root,
// ship. UI never knows the difference.

import Foundation
import Bluesky
import Models

public struct AppPasswordAuth: AuthProvider {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func session(handle: String, secret: String?) async throws -> SessionInfo {
        guard let secret, !secret.isEmpty else {
            // Missing app password is treated as bad credentials — the user
            // sees "Check your handle and app password." which is the right
            // remediation.
            throw APIError.authenticationFailed(reason: .badCredentials)
        }
        return try await api.authenticate(handle: handle, appPassword: secret)
    }

    public func restore() async throws -> SessionInfo? {
        try await api.restore()
    }

    public func refresh(_ session: SessionInfo) async throws -> SessionInfo {
        // In-session token rollover. ATProtoKit's refresh path is the same
        // call as cold-launch restore — the SDK reads the session out of
        // its own keychain wrapper rather than from `session`. If the
        // refresh succeeds we get a fresh `SessionInfo` back; if the
        // refresh token has expired we fall back to throwing
        // `.notAuthenticated` so the call site can decide to log out.
        //
        // Not wired to a call site yet (the post path is one shot today),
        // but having the right shape now avoids another protocol break
        // the moment we add a real 401 retry loop.
        guard let refreshed = try await api.restore() else {
            throw APIError.notAuthenticated
        }
        return refreshed
    }

    public func revoke(_ session: SessionInfo) async throws {
        try await api.signOut()
    }
}
