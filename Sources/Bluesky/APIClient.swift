// APIClient — actor that owns all Bluesky network I/O.
//
// Per §6.1 / §10: the Bluesky module is the ONLY place that imports
// ATProtoKit. UI modules talk to this client, never to the SDK directly.
//
// This is a stub for the scaffold dispatch — the real ATProtoKit wiring
// (ATProtocolConfiguration + AppleSecureKeychain + ATProtoBluesky) lands
// in the next dispatch.

import Foundation
import Models

public actor APIClient {
    public init() {}

    public func authenticate(handle: String, password: String) async throws -> SessionInfo {
        throw APIError.notImplemented
    }

    public func refresh(_ session: SessionInfo) async throws -> SessionInfo {
        throw APIError.notImplemented
    }

    public func signOut(_ session: SessionInfo) async throws {
        throw APIError.notImplemented
    }
}
