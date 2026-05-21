import Testing
import Foundation
@testable import Auth
import Models

// MARK: - MockAuthProvider

/// Sendable mock that scripts its outcomes for each call. Used to drive
/// AuthService through both success and failure transitions without
/// touching the network.
private actor MockAuthProvider: AuthProvider {

    enum SessionOutcome: Sendable {
        case success(SessionInfo)
        case failure(any Error)
    }

    /// Restore is tri-state: a real session, "nothing stored" (nil), or a
    /// thrown transient error (network failure mid-restore).
    enum RestoreOutcome: Sendable {
        case success(SessionInfo)
        case empty
        case failure(any Error)
    }

    private let sessionOutcome: SessionOutcome
    private let restoreOutcome: RestoreOutcome
    private let refreshOutcome: SessionOutcome
    private(set) var sessionCalls: Int = 0
    private(set) var restoreCalls: Int = 0
    private(set) var refreshCalls: Int = 0
    private(set) var revokeCalls: Int = 0

    init(
        sessionOutcome: SessionOutcome,
        restoreOutcome: RestoreOutcome = .empty,
        refreshOutcome: SessionOutcome = .failure(APIError.notAuthenticated)
    ) {
        self.sessionOutcome = sessionOutcome
        self.restoreOutcome = restoreOutcome
        self.refreshOutcome = refreshOutcome
    }

    func session(handle: String, secret: String?) async throws -> SessionInfo {
        sessionCalls += 1
        switch sessionOutcome {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }

    func restore() async throws -> SessionInfo? {
        restoreCalls += 1
        switch restoreOutcome {
        case .success(let s): return s
        case .empty: return nil
        case .failure(let e): throw e
        }
    }

    func refresh(_ session: SessionInfo) async throws -> SessionInfo {
        refreshCalls += 1
        switch refreshOutcome {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }

    func revoke(_ session: SessionInfo) async throws {
        revokeCalls += 1
    }
}

private let sampleSession = SessionInfo(did: "did:plc:abc123", handle: "dan.bsky.social")

// MARK: - Surface tests

@Suite("Auth module surface")
struct AuthSurfaceTests {

    @Test
    @MainActor
    func newAuthServiceStartsSignedOut() {
        let svc = AuthService(provider: MockAuthProvider(sessionOutcome: .success(sampleSession)))
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut, got \(svc.state)")
            return
        }
    }

    @Test
    func sessionInfoIsHashableAndSendable() {
        let a = SessionInfo(did: "did:plc:abc", handle: "dan.bsky.social")
        let b = SessionInfo(did: "did:plc:abc", handle: "dan.bsky.social")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - State transition tests

@Suite("AuthService state transitions")
struct AuthServiceStateTests {

    @Test
    @MainActor
    func signInSucceedsTransitionsToSignedIn() async {
        let svc = AuthService(provider: MockAuthProvider(sessionOutcome: .success(sampleSession)))
        await svc.signIn(handle: "dan.bsky.social", appPassword: "abcd-efgh-ijkl-mnop")

        guard case .signedIn(let session) = svc.state else {
            Issue.record("Expected .signedIn, got \(svc.state)")
            return
        }
        #expect(session == sampleSession)
    }

    @Test
    @MainActor
    func signInFailsTransitionsToError() async {
        let provider = MockAuthProvider(
            sessionOutcome: .failure(APIError.authenticationFailed(reason: .badCredentials))
        )
        let svc = AuthService(provider: provider)
        await svc.signIn(handle: "dan.bsky.social", appPassword: "wrong")

        guard case .error(let error, source: .signIn) = svc.state else {
            Issue.record("Expected .error(_, .signIn), got \(svc.state)")
            return
        }
        #expect((error as? APIError) == .authenticationFailed(reason: .badCredentials))
    }

    @Test
    @MainActor
    func dismissErrorReturnsToSignedOut() async {
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .failure(APIError.authenticationFailed(reason: .badCredentials))
        ))
        await svc.signIn(handle: "x", appPassword: "y")
        svc.dismissError()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut, got \(svc.state)")
            return
        }
    }

    @Test
    @MainActor
    func restoreEmptyLandsSignedOut() async {
        // No stored session in the Keychain — this is the cold-launch path
        // and must not produce UI noise.
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .success(sampleSession),
            restoreOutcome: .empty
        ))
        await svc.restore()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut after empty restore, got \(svc.state)")
            return
        }
    }

    @Test
    @MainActor
    func restoreTransientFailureLandsError() async {
        // A token *is* in the Keychain but the refresh call failed
        // transiently (e.g. flaky network at cold launch). Must land in
        // .error so the user can retry, NOT silently in .signedOut.
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .success(sampleSession),
            restoreOutcome: .failure(APIError.restoreFailed(reason: .network))
        ))
        await svc.restore()
        guard case .error(let error, source: .restore) = svc.state else {
            Issue.record("Expected .error(_, .restore) after transient restore failure, got \(svc.state)")
            return
        }
        #expect((error as? APIError) == .restoreFailed(reason: .network))
    }

    @Test
    @MainActor
    func restoreSuccessTransitionsToSignedIn() async {
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .failure(APIError.notAuthenticated),
            restoreOutcome: .success(sampleSession)
        ))
        await svc.restore()
        guard case .signedIn(let session) = svc.state else {
            Issue.record("Expected .signedIn after restore, got \(svc.state)")
            return
        }
        #expect(session == sampleSession)
    }

    @Test
    @MainActor
    func signOutFromSignedInTransitionsToSignedOut() async {
        let provider = MockAuthProvider(sessionOutcome: .success(sampleSession))
        let svc = AuthService(provider: provider)
        await svc.signIn(handle: "dan.bsky.social", appPassword: "x")
        await svc.signOut()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut, got \(svc.state)")
            return
        }
        // Pin that revoke actually fired — otherwise sign-out would be
        // local-only and the PDS would keep the session alive.
        let revokeCount = await provider.revokeCalls
        #expect(revokeCount == 1)
    }

    @Test
    @MainActor
    func signOutFromSigningInShortCircuitsToSignedOut() async {
        // Today the guard in signOut() short-circuits anything that is
        // not .signedIn to .signedOut without calling revoke. Pin that
        // racy mid-sign-in tap behaves the same way (no crash, no
        // network call against a session we don't have yet).
        let provider = MockAuthProvider(sessionOutcome: .success(sampleSession))
        let svc = AuthService(provider: provider)
        async let _ = svc.signIn(handle: "dan.bsky.social", appPassword: "x")
        await svc.signOut()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut, got \(svc.state)")
            return
        }
        // Sign-in may or may not have started before signOut wins on the
        // main actor; we don't assert sessionCalls. We do assert no
        // revoke happened — there was no session to revoke.
        let revokeCount = await provider.revokeCalls
        #expect(revokeCount == 0)
    }

    @Test
    @MainActor
    func restoreUnexpectedErrorLandsInError() async {
        // Pin the broader contract from #6: any throw out of provider.restore()
        // — not just APIError.restoreFailed — lands in .error so the user can
        // retry. Previously these were silently swallowed to .signedOut.
        struct WeirdError: Error, Equatable {}
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .success(sampleSession),
            restoreOutcome: .failure(WeirdError())
        ))
        await svc.restore()
        guard case .error(let error, source: .restore) = svc.state else {
            Issue.record("Expected .error(_, .restore) for unexpected restore throw, got \(svc.state)")
            return
        }
        #expect(error is WeirdError)
    }
}

// MARK: - SessionInfo Codable round-trip

@Suite("SessionInfo Codable")
struct SessionInfoCodableTests {

    @Test
    func roundTripsThroughJSON() throws {
        let original = SessionInfo(did: "did:plc:abc123", handle: "dan.bsky.social")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionInfo.self, from: data)
        #expect(decoded == original)
    }
}
