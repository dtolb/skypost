// RootView — placeholder per §6.1.
//
// In the next dispatch this will branch on AuthService.state:
//   .signedOut       → LoginView()
//   .signedIn        → MainTabView()
//   .error           → ErrorView(retry:)

import SwiftUI
import Auth

public struct RootView: View {
    @Environment(AuthService.self) private var auth

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("BlueSkyTemplates v2")
                .font(.title2.weight(.semibold))
            Text("Scaffold — login + compose land in the next dispatch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
