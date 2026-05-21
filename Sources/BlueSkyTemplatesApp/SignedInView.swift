// SignedInView — TabView shell shown once auth.state == .signedIn.
//
// Architecture §6.1 anticipates "one Router per tab". Two tabs for now:
// Templates (the primary feature) and Hello (sanity-check post path). The
// Hello tab will be replaced by Compose in Phase B; Settings will absorb
// Sign Out later. Each tab owns its own NavigationStack.

import SwiftUI
import Models
import Templates

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

            // HelloTabView owns its own NavigationStack — don't wrap here.
            HelloTabView(session: session)
                .tabItem {
                    Label("Hello", systemImage: "hand.wave")
                }
        }
    }
}
