// SettingsTabView — third tab in the signed-in TabView.
//
// Holds the account display (Handle + DID) and the Sign Out affordance.
// Extracted from the retired hello-world tab (Phase B3); that tab's
// sanity-check post button retired alongside it.
//
// No ViewModel — the view binds to AuthService directly for the one
// intent it owns (sign out).

import SwiftUI
import Auth
import Models

public struct SettingsTabView: View {

    public let session: SessionInfo

    @Environment(AuthService.self) private var auth

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Handle", value: session.handle)
                    LabeledContent("DID") {
                        Text(session.did)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
