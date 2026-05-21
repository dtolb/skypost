// RootView — switches on AuthService.state per §6.1.

import SwiftUI
import Auth

public struct RootView: View {
    @Environment(AuthService.self) private var auth

    public init() {}

    public var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                RestoringView()
            case .signedOut, .signingIn:
                LoginView()
            case .signedIn(let session):
                HomeView(session: session)
            case .error(let error):
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
                .foregroundStyle(.red)
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
