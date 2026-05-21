// BrandCard — 10pt continuous-radius white surface card.
//
// Mantis iOS card token: white background on `systemGroupedBackground`,
// 10pt continuous-corner radius, 16pt insets all around.

import SwiftUI

public struct BrandCard<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
            )
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        BrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card title").font(.headline)
                Text("Card body — preview only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
