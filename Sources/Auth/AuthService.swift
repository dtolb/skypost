// AuthService — main-isolated @Observable service holding auth state.
//
// Shape per §6.1. UI binds to `state` and calls the three intent methods
// (`signIn`, `restore`, `signOut`). All ATProtoKit work happens behind the
// AuthProvider abstraction — we don't import ATProtoKit here.

import Foundation
import Bluesky
import Models
import AppLogging

@MainActor
@Observable
public final class AuthService {

    /// Total state-space for the auth flow. Exhaustive switching in views
    /// catches missed cases at compile time.
    public enum State {
        /// No session — show the login screen.
        case signedOut
        /// Login in progress (user-initiated). Show a spinner; disable inputs.
        case signingIn
        /// Boot-time refresh in progress. Show a splash spinner.
        case restoring
        /// Live session.
        case signedIn(SessionInfo)
        /// Surface to the user; retry returns to `.signedOut`.
        case error(Error)
    }

    public private(set) var state: State = .signedOut

    private let provider: AuthProvider

    public init(provider: AuthProvider) {
        self.provider = provider
    }

    /// Convenience initializer for the production composition root.
    /// Wires the only ATProtoKit-backed provider.
    public convenience init() {
        self.init(provider: AppPasswordAuth(api: APIClient()))
    }

    // MARK: - Intents

    public func signIn(handle: String, appPassword: String) async {
        state = .signingIn
        do {
            let session = try await provider.session(handle: handle, secret: appPassword)
            state = .signedIn(session)
        } catch {
            Log.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error)
        }
    }

    /// Attempt to restore a session from the Keychain. Call from
    /// `RootView`'s `.task`. Silently returns to `.signedOut` if there's
    /// nothing to restore — that's the cold-launch path.
    public func restore() async {
        state = .restoring
        do {
            // The current SessionInfo isn't known yet at boot, so pass a
            // sentinel; AppPasswordAuth ignores it (the real handle lives
            // in the Keychain).
            let placeholder = SessionInfo(did: "", handle: "")
            let session = try await provider.refresh(placeholder)
            state = .signedIn(session)
        } catch {
            Log.auth.debug("Restore: no session (\(error.localizedDescription, privacy: .public))")
            state = .signedOut
        }
    }

    public func signOut() async {
        guard case .signedIn(let session) = state else {
            state = .signedOut
            return
        }
        do {
            try await provider.revoke(session)
        } catch {
            Log.auth.notice("revoke failed (continuing to signedOut): \(error.localizedDescription, privacy: .public)")
        }
        state = .signedOut
    }

    /// Reset the error state and return to the login screen.
    public func dismissError() {
        if case .error = state {
            state = .signedOut
        }
    }
}
