// App composition root — per §6.1.
//
// Long-lived services live as @State on this App struct, so SwiftUI keeps
// them alive for the process lifetime. Pass them into the view tree via
// `.environment(...)`. SwiftData is wired via `.modelContainer`.
//
// The actual `@main` attribute lives on the app-target shim (`AppMain.swift`
// in App/Sources) so the executable can be discovered by the linker. This
// struct is `public` so the shim can wrap it.

import SwiftUI
import SwiftData
import Auth
import Templates

public struct BlueSkyTemplatesApp: App {
    @State private var auth = AuthService()
    @State private var router = AppRouter()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(router)
        }
        .modelContainer(for: Template.self)
    }
}
