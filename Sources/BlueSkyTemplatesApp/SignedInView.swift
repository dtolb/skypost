// SignedInView — TabView shell shown once auth.state == .signedIn.
//
// Architecture §6.1 anticipates "one Router per tab". Four tabs:
//   1. Home      — Mantis welcome hero + quick actions + this-session log.
//   2. Templates — primary feature (CRUD over saved post templates).
//   3. Compose   — text-only post composer (Phase B).
//   4. Settings  — account display + Sign Out.
//
// `selectedTab` defaults to `.compose` so cold launch lands on the composer
// (Phase G1 win — preserved). Home is browsable from tab position 1 but is
// NOT the default selection.
//
// `AppTab` is `public` (not exported, but visible within the
// `BlueSkyTemplatesApp` module) so `HomeView` can accept a
// `Binding<AppTab>` in its public init.

import SwiftUI
import Models
import Templates
import Compose

public enum AppTab: Hashable {
    case home, templates, compose, settings
}

public struct SignedInView: View {

    public let session: SessionInfo

    @State private var selectedTab: AppTab = .compose
    @Environment(TemplateApplier.self) private var applier: TemplateApplier?

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // HomeView owns its own NavigationStack — don't wrap here.
            HomeView(session: session, selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

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
