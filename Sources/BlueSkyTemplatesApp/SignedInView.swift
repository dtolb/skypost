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

private enum AppTab: Hashable {
    case templates, compose, settings
}

public struct SignedInView: View {

    public let session: SessionInfo

    @State private var selectedTab: AppTab = .templates
    @Environment(TemplateApplier.self) private var applier: TemplateApplier?

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TemplateListView()
            }
            .tabItem {
                Label("Templates", systemImage: "doc.text")
            }
            .tag(AppTab.templates)

            // ComposeView owns its own NavigationStack — don't wrap here.
            ComposeView()
                .tabItem {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .tag(AppTab.compose)

            // SettingsTabView owns its own NavigationStack — don't wrap here.
            SettingsTabView(session: session)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        // Phase E hand-off: a template applied from any surface flips us
        // to Compose. Composer's own .onChange handles the ingest; this
        // modifier handles only the navigation.
        .onChange(of: applier?.pending?.tick) { _, newTick in
            if newTick != nil { selectedTab = .compose }
        }
    }
}
