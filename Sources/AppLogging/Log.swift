// Logging — per NEXT_STEPS_MAY_20_2026.md §6.4.
//
// Replaces v1's print(jwt) habit. One Logger per category. Tokens MUST be
// interpolated with an explicit privacy specifier — `.private(mask: .hash)`
// for anything sensitive.

import Foundation
import OSLog

public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tolbnet.bsktemplates"

    public static let auth    = Logger(subsystem: subsystem, category: "auth")
    public static let media   = Logger(subsystem: subsystem, category: "media")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let ui      = Logger(subsystem: subsystem, category: "ui")
}
