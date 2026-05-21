// SignedInView — TabView shell shown once auth.state == .signedIn.
//
// Architecture §6.1 anticipates "one Router per tab". Three tabs:
//   1. Templates — primary feature (CRUD over saved post templates).
//   2. Compose   — text-only post composer (Phase B).
//   3. Settings  — account display + Sign Out.
//
// The Phase-A "Hello" sanity-check tab is gone; Phase B promoted Compose
// into its slot and split Sign Out + account details out into Settings.
// Each tab owns its own NavigationStack.

import SwiftUI
import Models
import Templates
import Compose

public struct SignedInView: View {

    public let session: SessionInfo

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        TabView {
            NavigationStack {
                TemplateListView()
            }
            .tabItem {
                Label("Templates", systemImage: "doc.text")
            }

            // ComposeView owns its own NavigationStack — don't wrap here.
            ComposeView()
                .tabItem {
                    Label("Compose", systemImage: "square.and.pencil")
                }

            // SettingsTabView owns its own NavigationStack — don't wrap here.
            SettingsTabView(session: session)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
