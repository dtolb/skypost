// BrandTypography — Mantis-tuned type modifiers.
//
// The iOS default `.largeTitle` is close to the Mantis spec but uses different
// tracking. `brandLargeTitle()` matches the Mantis web kit's H1 — 34pt / 700 /
// tracking -0.9pt — and uses the `.tight` leading variant so the gradient hero
// doesn't tower over the subtitle.

import SwiftUI

public extension View {

    /// Applies the Mantis large-title style: 34pt / bold / tight leading,
    /// negative kerning -0.9pt. Use for hero titles and the Home greeting.
    func brandLargeTitle() -> some View {
        self
            .font(.system(size: 34, weight: .bold, design: .default).leading(.tight))
            .kerning(-0.9)
    }
}
