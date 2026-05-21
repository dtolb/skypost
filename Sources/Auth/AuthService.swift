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
        /// Surface to the user; retry returns to `.signedOut`. The `source`
        /// tells the UI whether to keep the user inside the login form
        /// (so typed inputs survive) or show a full-screen restore error.
        case error(Error, source: ErrorSource)
    }

    /// Where in the auth lifecycle an error originated. Drives whether the
    /// UI shows the error inline inside `LoginView` (so the user's typed
    /// handle/password survive) or escalates to a full-screen restore error.
    public enum ErrorSource: Sendable {
        /// Failure during interactive sign-in. Stay on `LoginView`; inline row.
        case signIn
        /// Failure while restoring a session at cold launch. Full-screen.
        case restore
    }

    public private(set) var state: State = .signedOut

    private let provider: AuthProvider

    public init(provider: AuthProvider) {
        self.provider = provider
    }

    // MARK: - Intents

    public func signIn(handle: String, appPassword: String) async {
        state = .signingIn
        do {
            let session = try await provider.session(handle: handle, secret: appPassword)
            state = .signedIn(session)
        } catch {
            Log.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error, source: .signIn)
        }
    }

    /// Attempt to restore a session from the Keychain. Call from
    /// `RootView`'s `.task`.
    ///
    /// Three outcomes:
    /// 1. Provider returns a `SessionInfo` → `.signedIn`.
    /// 2. Provider returns `nil` (no stored session — cold launch, after
    ///    sign-out, past refresh window) → `.signedOut`, no UI noise.
    /// 3. Provider throws (token exists but refresh failed transiently —
    ///    network, server 5xx) → `.error`, so the user can retry instead
    ///    of being silently logged out.
    public func restore() async {
        state = .restoring
        defer {
            // Guard against an early exit (cancellation, unanticipated throw site
            // changes) leaving the UI hung on the splash spinner — if we're
            // still .restoring when this function exits, fall back to signedOut.
            if case .restoring = state {
                state = .signedOut
            }
        }
        do {
            if let session = try await provider.restore() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch {
            Log.auth.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error, source: .restore)
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
