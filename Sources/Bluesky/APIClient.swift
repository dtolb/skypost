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
    /// Mirror of the keychain UUID. Held alongside the actor so we can
    /// probe the system Keychain directly without forcing ATProtoKit to
    /// build a configuration just to discover an empty slot.
    private let keychainUUID: UUID
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
        self.keychainUUID = uuid
        self.keychain = AppleSecureKeychain(
            identifier: uuid,
            serviceName: Self.keychainServiceName
        )
    }

    // MARK: - Authentication

    /// Authenticates with the PDS using an app password and stores the
    /// resulting refresh token in the Keychain.
    ///
    /// Handle and password are normalized here — the service layer is the
    /// single source of truth so UI doesn't have to know the rules.
    public func authenticate(handle: String, appPassword: String) async throws -> SessionInfo {
        let normalizedHandle = handle.bskyNormalizedHandle
        let normalizedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.auth.info("Authenticating handle=\(normalizedHandle, privacy: .public)")
        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        do {
            try await cfg.authenticate(with: normalizedHandle, password: normalizedPassword)
        } catch {
            let reason = mapAuthFailure(error)
            // Raw SDK text is hashed in the log so the device can be
            // matched across log entries without leaking the contents.
            Log.auth.error("Authenticate failed: reason=\(String(describing: reason), privacy: .public) raw=\(error.localizedDescription, privacy: .private(mask: .hash))")
            throw APIError.authenticationFailed(reason: reason)
        }
        return try await finishSignIn(with: cfg)
    }

    /// Restores a previous session by refreshing the stored refresh token.
    ///
    /// - Returns `nil` if there is no usable session in the Keychain (first
    ///   launch, after sign-out, or after the 2-week refresh window). The
    ///   caller treats this as "cleanly signed out".
    /// - Throws `APIError.restoreFailed(reason:)` if a refresh token *does*
    ///   exist in the Keychain but the refresh call itself failed for a
    ///   transient reason (network down at cold launch, PDS 5xx). The
    ///   caller surfaces this as a retryable error rather than silently
    ///   logging the user out.
    public func restore() async throws -> SessionInfo? {
        // Probe the Keychain first so we can tell "no session" from
        // "session exists but refresh failed". The native SecItem wrapper
        // is faster than building an ATProtoKit config just to discover an
        // empty keychain, and it gives us a clean nil signal without
        // depending on the SDK's internal error mapping. The account key
        // shape mirrors AppleSecureKeychain's internal `refreshTokenKey`.
        let probeAccount = "\(keychainUUID.uuidString).refreshToken"
        let hasStoredRefreshToken: Bool
        do {
            hasStoredRefreshToken = try Keychain.data(
                account: probeAccount,
                service: Self.keychainServiceName
            ) != nil
        } catch {
            // A genuine Keychain failure on the probe itself is transient
            // (locked device, daemon hiccup) — treat it the same as a
            // transient refresh failure below.
            Log.auth.error("Keychain probe failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.restoreFailed(reason: .unknown)
        }
        guard hasStoredRefreshToken else {
            // First launch / after sign-out / past refresh window — clean
            // signed-out, no UI noise.
            return nil
        }

        let cfg = ATProtocolConfiguration(keychainProtocol: keychain)
        do {
            try await cfg.refreshSession()
        } catch let error as ApplSecureKeychainError {
            switch error {
            case .itemNotFound:
                // Raced with sign-out, or the cached keychain UUID points
                // at an empty slot. Treat as cleanly signed out.
                return nil
            case .accessTokenNotFound, .invalidData, .unhandledStatus:
                Log.auth.error("Restore failed (keychain): \(error.localizedDescription, privacy: .public)")
                throw APIError.restoreFailed(reason: .unknown)
            }
        } catch {
            // Token was present, refresh threw. Surface as transient so
            // AuthService lands in `.error` with a retry affordance.
            let reason = mapAuthFailure(error)
            Log.auth.error("Restore failed: reason=\(String(describing: reason), privacy: .public) raw=\(error.localizedDescription, privacy: .private(mask: .hash))")
            throw APIError.restoreFailed(reason: reason)
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

    /// Posts an arbitrary text body. Returns the new record's AT-URI on
    /// success. Facets (mentions, URLs, hashtags) are auto-parsed by
    /// ATProtoKit's `ATFacetParser.parseFacets` from the text itself — see
    /// architecture §8.3 for the SDK contract.
    ///
    /// Locale is the user's current locale by default; UI passes through
    /// a single `Locale` per post. Multi-language post tagging is a Phase
    /// D polish item.
    public func createPost(text: String, locale: Locale = .current) async throws -> String {
        guard let bluesky else { throw APIError.notAuthenticated }
        do {
            let ref = try await bluesky.createPostRecord(
                text: text,
                locales: [locale],
                creationDate: Date()
            )
            Log.network.info("Posted record uri=\(ref.recordURI, privacy: .public)")
            return ref.recordURI
        } catch {
            Log.network.error("createPostRecord failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.postFailed(reason: error.localizedDescription)
        }
    }

    /// Posts text with up to 4 image attachments. Each image must already
    /// be JPEG-encoded and ≤1 MB (the SDK enforces both — see architecture
    /// §8.3); `ImageProcessor.encodeJPEG` is the upstream that guarantees
    /// it. Pixel dims are forwarded as the embed's `aspectRatio` so the
    /// Bluesky client can lay the image out without a flash of wrong size.
    ///
    /// `images` is a `Sendable` value tuple so the Compose module can
    /// pack a `ComposeAttachment` into this call without leaking the
    /// Bluesky SDK's `ATProtoTools.ImageQuery` type across module
    /// boundaries (per architecture §6.1).
    public func createPost(
        text: String,
        images: [(jpegData: Data, altText: String, pixelWidth: Int, pixelHeight: Int)],
        locale: Locale = .current
    ) async throws -> String {
        guard let bluesky else { throw APIError.notAuthenticated }
        let queries = images.map { img in
            ATProtoTools.ImageQuery(
                imageData: img.jpegData,
                fileName: "image_\(UUID().uuidString).jpg",
                altText: img.altText,
                aspectRatio: .init(width: img.pixelWidth, height: img.pixelHeight)
            )
        }
        do {
            let ref = try await bluesky.createPostRecord(
                text: text,
                locales: [locale],
                embed: queries.isEmpty ? nil : .images(images: queries),
                creationDate: Date()
            )
            Log.network.info("Posted record with \(images.count, privacy: .public) image(s) uri=\(ref.recordURI, privacy: .public)")
            return ref.recordURI
        } catch {
            Log.network.error("createPostRecord(images) failed: \(error.localizedDescription, privacy: .public)")
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
            // SDK said authentication succeeded but didn't hand us a user
            // session. Shouldn't happen — treat as unknown rather than
            // pretending the credentials were bad.
            throw APIError.authenticationFailed(reason: .unknown)
        }
        let info = SessionInfo(did: user.sessionDID, handle: user.handle)
        Log.auth.info("Signed in did=\(info.did, privacy: .private(mask: .hash)) handle=\(info.handle, privacy: .public)")
        return info
    }
}

// MARK: - Handle normalization

extension String {
    /// Bluesky handle, normalized: leading/trailing whitespace stripped,
    /// any leading `@` removed, lowercased. Module-internal so the
    /// service layer is the only normalization point; exposed for tests.
    var bskyNormalizedHandle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let unprefixed = trimmed.drop(while: { $0 == "@" })
        return unprefixed.lowercased()
    }
}

// MARK: - Auth failure mapping

/// Maps an SDK or transport error to a closed user-facing reason.
///
/// Lives inside `Bluesky` (the only module that imports ATProtoKit) so the
/// translation between SDK error shapes and the public `AuthFailureReason`
/// happens at the boundary. UI never sees the raw SDK string.
///
/// The mapping is intentionally conservative: unknown shapes fall through to
/// `.unknown`. The call site logs the raw description with a
/// `.private(mask: .hash)` privacy specifier so debugging is still possible
/// without surfacing wire-level details.
func mapAuthFailure(_ error: any Error) -> AuthFailureReason {
    // Transport-layer failures (URLSession).
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return .network
        default:
            return .unknown
        }
    }

    // ATProtoKit API errors (HTTP status mapped).
    if let apiError = error as? ATAPIError {
        switch apiError {
        case .unauthorized, .forbidden:
            return .badCredentials
        case .badRequest(let response):
            // The PDS uses 400 for invalid handle/password ("InvalidRequest",
            // "AuthenticationRequired"), and also for "AuthFactorTokenRequired"
            // when 2FA is on for the account.
            if response.error.localizedCaseInsensitiveContains("authfactor") ||
               response.message.localizedCaseInsensitiveContains("auth factor") {
                return .twoFactorRequired
            }
            return .badCredentials
        case .tooManyRequests:
            return .rateLimited
        case .badGateway, .serviceUnavailable, .gatewayTimeout, .internalServerError:
            return .network
        default:
            return .unknown
        }
    }

    // ATProtoKit's request-prep / config errors that surface during auth.
    if let prepError = error as? ATRequestPrepareError {
        switch prepError {
        case .missingActiveSession:
            return .badCredentials
        case .invalidRequestURL, .invalidHostnameURL, .invalidPDS, .emptyPDSURL:
            return .network
        case .failedAfterRetries:
            return .network
        default:
            return .unknown
        }
    }

    if let configError = error as? ATProtocolConfiguration.ATProtocolConfigurationError {
        switch configError {
        case .noSessionToken, .tokensExpired:
            return .badCredentials
        }
    }

    if error is ApplSecureKeychainError {
        // Reached only via the auth path, not the restore probe — means the
        // SDK couldn't read/write its own keychain mid-flow. Treat as
        // unknown rather than bad credentials.
        return .unknown
    }

    return .unknown
}
