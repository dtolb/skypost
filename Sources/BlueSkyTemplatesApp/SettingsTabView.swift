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
import DesignSystem

public struct SettingsTabView: View {

    public let session: SessionInfo

    @Environment(AuthService.self) private var auth

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        LeadIcon(systemName: "person.fill", tint: BrandColor.tint)
                        Text("Handle")
                        Spacer()
                        Text(session.handle)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        LeadIcon(systemName: "key.fill", tint: .gray)
                        Text("DID")
                        Spacer()
                        Text(session.did)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    BrandSectionHeader("Account")
                }

                Section {
                    Button {
                        Task { await auth.signOut() }
                    } label: {
                        HStack(spacing: 12) {
                            LeadIcon(
                                systemName: "rectangle.portrait.and.arrow.right",
                                tint: BrandColor.destructive
                            )
                            Text("Sign out")
                                .foregroundStyle(BrandColor.destructive)
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sign out")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
