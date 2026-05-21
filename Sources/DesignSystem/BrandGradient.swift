// BrandGradient — Mantis welcome-banner gradient tokens.
//
// The Mantis web kit ships a 5-stop diagonal gradient on its WelcomeBanner.
// Angle 250.38° measured clockwise from "up" — i.e., the gradient runs from
// the lower-right toward the upper-left, with the lightest stop in the
// lower-right. Stops are sourced from Ant Design primary-1, -4, -6, -7, -9.

import SwiftUI

public enum BrandGradient {

    /// 5-stop diagonal welcome gradient used by `WelcomeHero` and the
    /// (currently theoretical) onboarding banners.
    public static let welcome: LinearGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 230 / 255, green: 244 / 255, blue: 255 / 255), location: 0.00),  // primary-1 #e6f4ff
            .init(color: Color(red: 105 / 255, green: 177 / 255, blue: 255 / 255), location: 0.25),  // primary-4 #69b1ff
            .init(color: Color(red:  22 / 255, green: 119 / 255, blue: 255 / 255), location: 0.50),  // primary-6 #1677ff
            .init(color: Color(red:   9 / 255, green:  88 / 255, blue: 217 / 255), location: 0.75),  // primary-7 #0958d9
            .init(color: Color(red:   0 / 255, green:  44 / 255, blue: 140 / 255), location: 1.00),  // primary-9 #002c8c
        ],
        // 250.38° clockwise from "up" → end point is upper-left, start
        // is lower-right. SwiftUI's UnitPoint origin is (0, 0) top-leading,
        // so we approximate via trig: angle 250.38° → dx ≈ -sin(250.38°),
        // dy ≈ -cos(250.38°). Pre-computed below to a literal pair so the
        // gradient is a compile-time constant.
        startPoint: UnitPoint(x: 0.9712, y: 0.8332),  // lower-right
        endPoint: UnitPoint(x: 0.0288, y: 0.1668)     // upper-left
    )
}
