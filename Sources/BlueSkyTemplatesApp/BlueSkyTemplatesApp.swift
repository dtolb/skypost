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
import Bluesky
import Templates

public struct BlueSkyTemplatesApp: App {

    // One APIClient for the whole process — AuthService and the Compose
    // post path share it (same Keychain UUID, same session state).
    // Constructed exactly once in `init()` below and stored via `_api`.
    @State private var api: APIClient
    @State private var auth: AuthService
    @State private var router = AppRouter()
    @State private var templateApplier = TemplateApplier()
    // `LiveExternalLinkResolver` is gated on `canImport(LinkPresentation)
    // && canImport(UIKit)`; UIKit is iOS-only, so the App library target's
    // macOS build (used for `swift test`) won't see the type. Gate the
    // declaration + injection identically so the SPM library still builds
    // on macOS.
    #if canImport(LinkPresentation) && canImport(UIKit)
    @State private var linkResolver: any ExternalLinkResolver = LiveExternalLinkResolver()
    #endif

    public init() {
        let api = APIClient()
        self._api = State(initialValue: api)
        self._auth = State(initialValue: AuthService(provider: AppPasswordAuth(api: api)))
    }

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(router)
                .environment(templateApplier)
                .environment(\.apiClient, api)
                #if canImport(LinkPresentation) && canImport(UIKit)
                .environment(\.externalLinkResolver, linkResolver)
                #endif
        }
        .modelContainer(for: Template.self)
    }
}
