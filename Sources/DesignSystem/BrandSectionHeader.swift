// BrandSectionHeader — uppercase, 13pt, kerned section title.
//
// Intended for use as `Section { ... } header: { BrandSectionHeader("Title") }`.
// Layers cleanly on top of SwiftUI's grouped-form default uppercase styling;
// if you need to disarm SwiftUI's own uppercase pass on the parent Section,
// add `.textCase(nil)` to the Section.

import SwiftUI

public struct BrandSectionHeader: View {

    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .regular))
            // 0.08em at 13pt ≈ 1.04pt — round to 1.0pt of kerning. SwiftUI's
            // `.kerning` is point-based, not em-relative.
            .kerning(1.0)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    Form {
        Section {
            Text("Row content")
        } header: {
            BrandSectionHeader("Brand section")
        }
    }
}
