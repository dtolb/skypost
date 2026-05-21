// LeadIcon — 30pt colored rounded-square SF Symbol glyph.
//
// Mantis iOS settings-row token: a small filled rounded rectangle with a white
// SF Symbol centered inside. Pair with `BrandColor.deterministicColor(for:)` to
// color-code rows by a stable key (e.g., template title).

import SwiftUI

public struct LeadIcon: View {

    private let systemName: String
    private let tint: Color

    public init(systemName: String, tint: Color) {
        self.systemName = systemName
        self.tint = tint
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
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
