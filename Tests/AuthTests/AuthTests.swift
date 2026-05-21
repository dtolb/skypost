import Testing
@testable import Auth
import Models

@Suite("Auth module surface")
struct AuthSurfaceTests {
    @Test
    @MainActor
    func newAuthServiceStartsSignedOut() {
        let svc = AuthService()
        if case .signedOut = svc.state {
            // pass
        } else {
            Issue.record("Expected .signedOut, got \(svc.state)")
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
