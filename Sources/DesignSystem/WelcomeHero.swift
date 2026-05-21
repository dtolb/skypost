// WelcomeHero — gradient hero card with title, subtitle, optional trailing view.
//
// Background: `BrandGradient.welcome` (5-stop Mantis primary diagonal).
// Padding 20, corner radius 16, primary-button shadow (tinted, soft, offset
// down — matches Mantis `WelcomeBanner` elevation).

import SwiftUI

public struct WelcomeHero<Trailing: View>: View {

    private let title: String
    private let subtitle: String
    private let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .foregroundStyle(.white)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandGradient.welcome)
        )
        .shadow(
            color: BrandColor.tint.opacity(0.20),
            radius: 12,
            x: 0,
            y: 14
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.composeAccessibilityLabel(title: title, subtitle: subtitle))
    }

    /// The exact label the view applies via `.accessibilityLabel`.
    /// Exposed as a static helper so unit tests can assert composition
    /// without standing up a SwiftUI host.
    public static func composeAccessibilityLabel(title: String, subtitle: String) -> String {
        "\(title). \(subtitle)"
    }
}

// MARK: - EmptyView overload

public extension WelcomeHero where Trailing == EmptyView {

    /// Convenience initializer for heroes with no trailing accessory.
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

#Preview("With trailing") {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        WelcomeHero("Welcome back", subtitle: "@dtolb.bsky.social") {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
        }
        .padding()
    }
}

#Preview("Plain") {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        WelcomeHero("No templates yet", subtitle: "Tap + to save your first.")
            .padding()
    }
}
