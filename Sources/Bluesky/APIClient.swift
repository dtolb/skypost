// APIClient — actor that owns all Bluesky network I/O.
//
// Per §6.1 / §5: the Bluesky module is the ONLY place that imports
// ATProtoKit. UI modules talk to this client, never to the SDK directly.
//
// Auth uses ATProtoKit's AppleSecureKeychain (per §8.2) — the refresh
// token and password are stored in the system Keychain, the access token
// lives in-memory only. We persist the keychain UUID (a handle, not a
// secret) in UserDefaults so the same Keychain bundle is reused across
// process launches.

import Foundation
@preconcurrency import ATProtoKit
import AppLogging
import Models

public actor APIClient {

    // MARK: - Constants

    /// The `kSecAttrService` value used by ATProtoKit's keychain wrapper.
    /// Matches the app bundle id so future Share Extensions can scope by service.
    public static let keychainServiceName = "com.dtolb.BlueSkyTemplates"

    /// UserDefaults key for the persisted keychain UUID. The UUID is just a
    /// handle — the actual secrets live in the system Keychain.
    public static let keychainUUIDDefaultsKey = "bsky.keychainUUID"

    // MARK: - State

    private let keychain: AppleSecureKeychain
    private var config: ATProtocolConfiguration?
    private var kit: ATProtoKit?
    private var bluesky: ATProtoBluesky?

    // MARK: - Init

    public init() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Self.keychainUUIDDefaultsKey)
        let uuid = stored.flatMap(UUID.init(uuidString:)) ?? UUID()
        if stored == nil {
            defaults.set(uuid.uuidString, forKey: Self.keychainUUIDDefaultsKey)
        }
        self.keychain = AppleSecureKeychain(
            identifier: uuid,
            serviceName: Self.keychainServiceName
        )
    }

    // MARK: - Authentication

    /// Authenticates with the PDS using an app password and stores the
    /// resulting refresh token in the Keychain.
    public func authenticate(handle: String, appPassword: String) async throws -> SessionInfo {
        Log.auth.info("Authenticating handle=\(handle, privacy: .public)")
        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        do {
            try await cfg.authenticate(with: handle, password: appPassword)
        } catch {
            Log.auth.error("Authenticate failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.authenticationFailed(reason: error.localizedDescription)
        }
        return try await finishSignIn(with: cfg)
    }

    /// Restores a previous session by refreshing the stored refresh token.
    ///
    /// Returns `nil` if there is no usable session in the Keychain (first
    /// launch, after sign-out, or after the 2-week refresh window).
    public func restore() async throws -> SessionInfo? {
        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        do {
            try await cfg.refreshSession()
        } catch {
            Log.auth.notice("Restore failed (no valid refresh token): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return try await finishSignIn(with: cfg)
    }

    /// Signs out: deletes the session on the PDS (best effort), clears the
    /// in-memory ATProtoKit state, and wipes the Keychain tokens.
    public func signOut() async throws {
        if let cfg = config {
            do {
                try await cfg.deleteSession()
            } catch {
                // Don't fail sign-out if the server call fails — local
                // state still needs to be cleared.
                Log.auth.notice("deleteSession failed (continuing): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Wipe keychain state for this UUID. ATProtoKit caches secrets
        // in-memory inside the keychain actor; delete to flush both.
        do {
            try await keychain.deleteRefreshToken()
        } catch {
            Log.auth.debug("deleteRefreshToken: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try await keychain.deletePassword()
        } catch {
            Log.auth.debug("deletePassword: \(error.localizedDescription, privacy: .public)")
        }
        try? await keychain.deleteAccessToken()

        config = nil
        kit = nil
        bluesky = nil
        Log.auth.info("Signed out")
    }

    // MARK: - Posting

    /// Posts a fixed hello-world string. Returns the new record's AT-URI.
    public func postHelloWorld() async throws -> String {
        guard let bluesky else { throw APIError.notAuthenticated }
        do {
            let ref = try await bluesky.createPostRecord(
                text: "hello from v2",
                locales: [Locale(identifier: "en")],
                creationDate: Date()
            )
            Log.network.info("Posted record uri=\(ref.recordURI, privacy: .public)")
            return ref.recordURI
        } catch {
            Log.network.error("createPostRecord failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.postFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func finishSignIn(with cfg: ATProtocolConfiguration) async throws -> SessionInfo {
        let kit = await ATProtoKit(sessionConfiguration: cfg)
        let bsky = ATProtoBluesky(atProtoKitInstance: kit)
        self.config = cfg
        self.kit = kit
        self.bluesky = bsky

        guard let user = try await kit.getUserSession() else {
            throw APIError.authenticationFailed(reason: "No user session after authenticate")
        }
        let info = SessionInfo(did: user.sessionDID, handle: user.handle)
        Log.auth.info("Signed in did=\(info.did, privacy: .private(mask: .hash)) handle=\(info.handle, privacy: .public)")
        return info
    }
}
