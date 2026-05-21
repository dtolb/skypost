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

    public func refresh(_ session: SessionInfo) async throws -> SessionInfo {
        guard let restored = try await api.restore() else {
            throw APIError.notAuthenticated
        }
        return restored
    }

    public func revoke(_ session: SessionInfo) async throws {
        try await api.signOut()
    }
}
