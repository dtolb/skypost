// AppRouter — placeholder per §6.1.
//
// One @Observable router per tab when we add tabs. For the scaffold this is
// just the type — real navigation paths and tab state land with the UI
// dispatches.

import Foundation

// `@MainActor` is load-bearing: SwiftUI observes `@Observable` mutations
// from MainActor, and this class isn't opted into Swift 6's
// main-actor-by-default (no `defaultIsolation: MainActor.self` in
// Package.swift). Keep the annotation explicit.
@MainActor
@Observable
public final class AppRouter {
    public init() {}
}
