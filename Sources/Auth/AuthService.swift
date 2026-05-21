// AuthService — main-isolated @Observable service holding the auth state.
//
// Verbatim shape from §6.1. The signIn body intentionally fatalErrors —
// real ATProtoKit wiring happens in the next dispatch.

import Foundation
import Bluesky
import Models

@MainActor
@Observable
public final class AuthService {
    public enum State {
        case signedOut
        case signedIn(SessionInfo)
        case error(Error)
    }

    public private(set) var state: State = .signedOut

    private let api: APIClient

    public init(api: APIClient = APIClient()) {
        self.api = api
    }

    public func signIn(handle: String, appPassword: String) async {
        fatalError("AuthService.signIn not yet implemented — wired in the next dispatch")
    }

    public func signOut() async {
        guard case .signedIn(let session) = state else { return }
        do {
            try await api.signOut(session)
            state = .signedOut
        } catch {
            state = .error(error)
        }
    }
}
