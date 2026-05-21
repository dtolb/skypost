// AuthProvider — protocol for swapping auth strategies (§7.2).
//
// At v2 launch the only implementation is AppPasswordAuth. When OAuth lands
// (per §7.3 triggers), add OAuthAuth next to it and swap in the
// composition root. UI never knows the difference.

import Foundation
import Models

public protocol AuthProvider: Sendable {
    func session(handle: String, secret: String?) async throws -> SessionInfo
    func refresh(_ session: SessionInfo) async throws -> SessionInfo
    func revoke(_ session: SessionInfo) async throws
}
