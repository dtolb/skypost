// AppMain — minimal @main shim. The actual App scene lives in the
// BlueSkyTemplatesApp library module (as `AppRoot`). This file is the
// only thing in the app target's source set; everything else is in SPM
// modules so the same code can be unit-tested without booting the
// simulator.

import SwiftUI
import BlueSkyTemplatesApp

@main
struct AppMain {
    static func main() {
        AppRoot.main()
    }
}
