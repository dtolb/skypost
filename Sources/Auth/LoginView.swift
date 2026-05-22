// LoginView — handle + app-password sign-in screen.
//
// UI consumes AuthService from the environment. Local screen state is a
// small @State enum (per §6.1). No ViewModel.

import SwiftUI
import DesignSystem
import Models

#if canImport(Pow)
import Pow
#endif

public struct LoginView: View {

    private static let appPasswordSettingsURL: URL = {
        // Force-unwrapped because the literal is checked at compile time; if
        // the URL is invalid, every build would crash on launch — making this
        // a programmer-error guard, not a runtime fallback.
        URL(string: "https://bsky.app/settings/app-passwords")!
    }()

    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var handle: String = ""
    @State private var appPassword: String = ""
    // Monotonic tick that fires the form shake + error haptic on each
    // false→true transition of `hasSignInError` (architecture §11 step 5).
    // We watch a derived bool instead of `auth.state` so AuthService.State
    // doesn't need to be made Equatable for an `.onChange(of:)` here.
    @State private var errorTick: Int = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable { case handle, password }

    public init() {}

    public var body: some View {
        NavigationStack {
            decoratedForm
                .navigationTitle("BlueSky Templates")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .onAppear { focus = .handle }
                // Edge-triggered: bump the tick only when sign-in error appears.
                // Each new attempt cycles through .signingIn (hasSignInError = false),
                // so successive bad attempts each re-fire the shake.
                .onChange(of: hasSignInError) { _, isError in
                    if isError { errorTick += 1 }
                }
        }
    }

    // Pow modifiers attach to the Form so the shake reads at the user's
    // gaze (the inputs they just typed into), not the whole nav chrome.
    @ViewBuilder
    private var decoratedForm: some View {
        #if canImport(Pow)
        // Reduce-motion gate (architecture §9.2): shake AND haptic are
        // disabled together — the pair is treated as one delight unit.
        // The haptic API is iOS-only in Pow; the shake itself is cross-platform.
        #if os(iOS)
        formContent
            .changeEffect(.shake(rate: .fast), value: errorTick, isEnabled: !reduceMotion)
            .changeEffect(.feedback(hapticNotification: .error), value: errorTick, isEnabled: !reduceMotion)
        #else
        formContent
            .changeEffect(.shake(rate: .fast), value: errorTick, isEnabled: !reduceMotion)
        #endif
        #else
        formContent
        #endif
    }

    private var formContent: some View {
        Form {
            Section {
                WelcomeHero(
                    "Welcome to BlueSky Templates",
                    subtitle: "Post from your saved templates."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

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
                BrandSectionHeader("Sign in to Bluesky")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use an app password, not your account password.")
                    Link(
                        "Generate one at bsky.app/settings/app-passwords",
                        destination: Self.appPasswordSettingsURL
                    )
                    .font(.footnote)
                }
            }

            if let message = errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandColor.error)
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

    // Derived boolean watched by `.onChange` to drive `errorTick`. We watch a
    // bool (not `auth.state`) because AuthService.State isn't Equatable —
    // its associated `Error` value can't be compared.
    private var hasSignInError: Bool {
        if case .error(_, source: .signIn) = auth.state { return true }
        return false
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
