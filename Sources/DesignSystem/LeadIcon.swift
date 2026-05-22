// LeadIcon — 30pt adaptive rounded-square SF Symbol glyph.
//
// Mantis iOS settings-row token: a small rounded rectangle with an SF Symbol
// centered inside. Pair with `BrandColor.deterministicColor(for:)` to color-code
// rows by a stable key (e.g., template title).

import SwiftUI

public struct LeadIcon: View {

    private let systemName: String
    private let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    public init(systemName: String, tint: Color) {
        self.systemName = systemName
        self.tint = tint
    }

    public var body: some View {
        let style = Self.resolvedStyle(for: colorScheme, tint: tint)

        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(style.background)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style.symbol)
            }
            .accessibilityHidden(true)
    }
}

internal struct LeadIconResolvedStyle: Equatable {
    let background: Color
    let symbol: Color
}

extension LeadIcon {

    nonisolated internal static func resolvedStyle(for colorScheme: ColorScheme, tint: Color) -> LeadIconResolvedStyle {
        switch colorScheme {
        case .dark:
            LeadIconResolvedStyle(background: tint.opacity(0.18), symbol: tint)
        default:
            LeadIconResolvedStyle(background: tint, symbol: .white)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        LeadIcon(systemName: "doc.text", tint: BrandColor.tint)
        LeadIcon(systemName: "person.fill", tint: BrandColor.deterministicColor(for: "alice"))
        LeadIcon(systemName: "key.fill", tint: .gray)
        LeadIcon(systemName: "rectangle.portrait.and.arrow.right", tint: .red)
    }
    .padding()
}
