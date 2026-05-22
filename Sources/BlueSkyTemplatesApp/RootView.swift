// RootView — switches on AuthService.state per §6.1.

import SwiftUI
import Auth
import DesignSystem

public struct RootView: View {
    @Environment(AuthService.self) private var auth

    public init() {}

    public var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                RestoringView()
            case .signedOut, .signingIn, .error(_, source: .signIn):
                // Sign-in failures stay inside the login form so the user's
                // typed handle/password survive; LoginView renders the
                // inline error row from `auth.state`.
                LoginView()
            case .signedIn(let session):
                SignedInView(session: session)
            case .error(let error, source: .restore):
                // Cold-launch / session-restore failures escalate to a
                // full-screen retry surface — there's no user input to
                // preserve at this point in the lifecycle.
                ErrorView(error: error) {
                    auth.dismissError()
                }
            }
        }
        .task { await auth.restore() }
    }
}

private struct RestoringView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Restoring session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorView: View {
    let error: Error
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(BrandColor.error)
            Text("Something went wrong")
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
