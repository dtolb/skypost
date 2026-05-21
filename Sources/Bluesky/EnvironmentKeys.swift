// EnvironmentKeys — SwiftUI environment access for the APIClient actor.
//
// APIClient is an actor, which doesn't conform to @Observable, so it can't
// be used with `@Environment(APIClient.self)`. We expose it via a classic
// EnvironmentKey instead. Defined here in `Bluesky` so every module that
// already depends on Bluesky (App, Compose, …) sees the same key and
// therefore the same env slot — extensions declared in different modules
// would be backed by different `EnvironmentKey` types and the injected
// value would never reach the consumer.

import SwiftUI

// Default is nil so the environment never silently spins up a real
// Keychain-touching APIClient for previews, tests, or un-injected
// subtrees. The App is the single point of injection (see
// `BlueSkyTemplatesApp`); consumers must handle the optional explicitly.
private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

extension EnvironmentValues {
    public var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
