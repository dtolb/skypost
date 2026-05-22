// BrandColor — Mantis brand-token Colors.
//
// All values verified against `mantis/design-system/ui_kits/ios/` README
// (source-of-truth decisions table). The hex literals match Ant Design /
// Mantis primary-6, polar-green-6, dust-red-6 respectively.

import SwiftUI

public enum BrandColor {

    /// Mantis primary tint — Ant Design `blue-6` = `#1677ff`.
    public static let tint: Color = Color(
        red: _tintRGB.red,
        green: _tintRGB.green,
        blue: _tintRGB.blue
    )

    /// Mantis polar-green-6 — used for success / income chips.
    public static let incomeGreen: Color = Color(
        red: _incomeGreenRGB.red,
        green: _incomeGreenRGB.green,
        blue: _incomeGreenRGB.blue
    )

    /// Mantis dust-red-6 — used for failure / expense / destructive copy.
    public static let expenseRed: Color = Color(
        red: _expenseRedRGB.red,
        green: _expenseRedRGB.green,
        blue: _expenseRedRGB.blue
    )

    /// Destructive-action role color. Sign-out, delete, irreversible affordances.
    /// Same hue as `expenseRed` today; named separately so a future fork doesn't
    /// require ripping out call-sites.
    public static let destructive: Color = Color(
        red: _destructiveRGB.red,
        green: _destructiveRGB.green,
        blue: _destructiveRGB.blue
    )

    /// Error-message role color. Inline error rows, failure copy.
    /// Same hue as `expenseRed` today; named separately so a future softer
    /// error tint can land without rewriting consumers.
    public static let error: Color = Color(
        red: _errorRGB.red,
        green: _errorRGB.green,
        blue: _errorRGB.blue
    )

    // MARK: - Internal RGB tuples (test surface)
    //
    // SwiftUI `Color` doesn't expose its components cleanly across platforms
    // (no `Color.resolve` until newer toolchains, and even then the components
    // are color-space-dependent). The tests assert against these tuples,
    // which are the literal inputs to the `Color(red:green:blue:)` initializers
    // above — same source-of-truth, no UIColor/NSColor ceremony.

    internal static let _tintRGB: (red: Double, green: Double, blue: Double) =
        (22 / 255, 119 / 255, 255 / 255)

    internal static let _incomeGreenRGB: (red: Double, green: Double, blue: Double) =
        (82 / 255, 196 / 255, 26 / 255)

    internal static let _expenseRedRGB: (red: Double, green: Double, blue: Double) =
        (245 / 255, 34 / 255, 45 / 255)

    internal static let _destructiveRGB: (red: Double, green: Double, blue: Double) =
        _expenseRedRGB

    internal static let _errorRGB: (red: Double, green: Double, blue: Double) =
        _expenseRedRGB

    // MARK: - Deterministic palette

    /// Fixed Mantis-adjacent palette used by `deterministicColor(for:)`.
    /// Picks (in order): magenta-6, geek-blue-6, cyan-6, polar-green-6, gold-6, purple-6.
    /// Exposed to tests for membership assertions.
    internal static let deterministicPalette: [Color] = [
        Color(red: 235 / 255, green:  47 / 255, blue:  150 / 255),  // magenta-6 #eb2f96
        Color(red:  47 / 255, green:  84 / 255, blue:  235 / 255),  // geek-blue-6 #2f54eb
        Color(red:  19 / 255, green: 194 / 255, blue:  194 / 255),  // cyan-6 #13c2c2
        Color(red:  82 / 255, green: 196 / 255, blue:   26 / 255),  // polar-green-6 #52c41a
        Color(red: 250 / 255, green: 173 / 255, blue:   20 / 255),  // gold-6 #faad14
        Color(red: 114 / 255, green:  46 / 255, blue:  209 / 255),  // purple-6 #722ed1
    ]

    /// Returns a stable color from `deterministicPalette` for the given input.
    ///
    /// - Note: Uses `String.hashValue`, which is **process-stable** but not
    ///   stable across processes (Swift seeds the hasher per-launch). That's
    ///   fine for in-session UI consistency (the same template title gets the
    ///   same icon tint while the app is running) but do **not** persist the
    ///   resulting color or assume it survives an app relaunch.
    public static func deterministicColor(for input: String) -> Color {
        let index = abs(input.hashValue) % deterministicPalette.count
        return deterministicPalette[index]
    }
}
