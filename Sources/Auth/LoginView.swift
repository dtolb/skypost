// LoginView — handle + app-password sign-in screen.
//
// UI consumes AuthService from the environment. Local screen state is a
// small @State enum (per §6.1). No ViewModel.

import SwiftUI
import Models

public struct LoginView: View {

    @Environment(AuthService.self) private var auth

    @State private var handle: String = ""
    @State private var appPassword: String = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case handle, password }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("handle.bsky.social", text: $handle)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focus, equals: .handle)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .disabled(isBusy)

                    SecureField("App password (xxxx-xxxx-xxxx-xxxx)", text: $appPassword)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        // Show `.go` only when both fields are filled —
                        // otherwise `.next` so the return key visibly
                        // cycles focus instead of dead-tapping on submit.
                        .submitLabel(canSubmit ? .go : .next)
                        .onSubmit {
                            if canSubmit {
                                submit()
                            } else {
                                focus = .handle
                            }
                        }
                        .disabled(isBusy)
                } header: {
                    Text("Sign in to Bluesky")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use an app password, not your account password.")
                        Link(
                            "Generate one at bsky.app/settings/app-passwords",
                            destination: URL(string: "https://bsky.app/settings/app-passwords")!
                        )
                        .font(.footnote)
                    }
                }

                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            if isBusy { ProgressView() }
                            Text(isBusy ? "Signing in…" : "Sign in")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("BlueSky Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { focus = .handle }
        }
    }

    // MARK: - Derived state

    private var isBusy: Bool {
        if case .signingIn = auth.state { return true }
        return false
    }

    private var canSubmit: Bool {
        !handle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !appPassword.isEmpty &&
        !isBusy
    }

    private var errorMessage: String? {
        // Only show inline errors for sign-in failures — restore failures
        // route to a full-screen ErrorView from RootView and never reach here.
        guard case .error(let error, source: .signIn) = auth.state else { return nil }
        return error.localizedDescription
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = appPassword
        // Clear any prior sign-in error so the state transitions cleanly:
        // .error(_, .signIn) → .signedOut → .signingIn → .signedIn / .error
        auth.dismissError()
        Task { await auth.signIn(handle: trimmedHandle, appPassword: secret) }
    }
}
