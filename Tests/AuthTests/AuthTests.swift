import Testing
import Foundation
@testable import Auth
import Models

// MARK: - MockAuthProvider

/// Sendable mock that scripts its outcomes for each call. Used to drive
/// AuthService through both success and failure transitions without
/// touching the network.
private actor MockAuthProvider: AuthProvider {

    enum Outcome: Sendable {
        case success(SessionInfo)
        case failure(any Error)
    }

    private let sessionOutcome: Outcome
    private let refreshOutcome: Outcome
    private(set) var sessionCalls: Int = 0
    private(set) var refreshCalls: Int = 0
    private(set) var revokeCalls: Int = 0

    init(sessionOutcome: Outcome, refreshOutcome: Outcome = .failure(APIError.notAuthenticated)) {
        self.sessionOutcome = sessionOutcome
        self.refreshOutcome = refreshOutcome
    }

    func session(handle: String, secret: String?) async throws -> SessionInfo {
        sessionCalls += 1
        switch sessionOutcome {
        case .success(let s): return s
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
            sessionOutcome: .failure(APIError.authenticationFailed(reason: "bad password"))
        )
        let svc = AuthService(provider: provider)
        await svc.signIn(handle: "dan.bsky.social", appPassword: "wrong")

        guard case .error(let error) = svc.state else {
            Issue.record("Expected .error, got \(svc.state)")
            return
        }
        #expect(error.localizedDescription.contains("bad password"))
    }

    @Test
    @MainActor
    func dismissErrorReturnsToSignedOut() async {
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .failure(APIError.authenticationFailed(reason: "x"))
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
    func restoreFailureLandsSignedOutNotError() async {
        // A failed restore (e.g. no token in Keychain on first launch) is
        // not user-visible — it's just the empty cold-launch path.
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .success(sampleSession),
            refreshOutcome: .failure(APIError.notAuthenticated)
        ))
        await svc.restore()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut after failed restore, got \(svc.state)")
            return
        }
    }

    @Test
    @MainActor
    func restoreSuccessTransitionsToSignedIn() async {
        let svc = AuthService(provider: MockAuthProvider(
            sessionOutcome: .failure(APIError.notAuthenticated),
            refreshOutcome: .success(sampleSession)
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
        let svc = AuthService(provider: MockAuthProvider(sessionOutcome: .success(sampleSession)))
        await svc.signIn(handle: "dan.bsky.social", appPassword: "x")
        await svc.signOut()
        guard case .signedOut = svc.state else {
            Issue.record("Expected .signedOut, got \(svc.state)")
            return
        }
    }
}
