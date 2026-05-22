import Testing
import SwiftUI
@testable import DesignSystem

@Suite("BrandColor tokens")
struct BrandColorTests {

    @Test
    func tintMatchesAntDesignBlue6() {
        // Ant Design / Mantis primary-6 = #1677ff.
        #expect(BrandColor._tintRGB.red == 22.0 / 255.0)
        #expect(BrandColor._tintRGB.green == 119.0 / 255.0)
        #expect(BrandColor._tintRGB.blue == 255.0 / 255.0)
    }

    @Test
    func incomeGreenMatchesPolarGreen6() {
        // Mantis polar-green-6 = #52c41a.
        #expect(BrandColor._incomeGreenRGB.red == 82.0 / 255.0)
        #expect(BrandColor._incomeGreenRGB.green == 196.0 / 255.0)
        #expect(BrandColor._incomeGreenRGB.blue == 26.0 / 255.0)
    }

    @Test
    func expenseRedMatchesDustRed6() {
        // Mantis dust-red-6 = #f5222d.
        #expect(BrandColor._expenseRedRGB.red == 245.0 / 255.0)
        #expect(BrandColor._expenseRedRGB.green == 34.0 / 255.0)
        #expect(BrandColor._expenseRedRGB.blue == 45.0 / 255.0)
    }

    @Test
    func destructiveMatchesDustRed6() {
        // BrandColor.destructive == Mantis dust-red-6 (#f5222d) today.
        #expect(BrandColor._destructiveRGB == BrandColor._expenseRedRGB)
    }

    @Test
    func errorMatchesDustRed6() {
        // BrandColor.error == Mantis dust-red-6 today. May diverge later
        // if we adopt a softer error-vs-destructive distinction; the tuple
        // assertion guards intent.
        #expect(BrandColor._errorRGB == BrandColor._expenseRedRGB)
    }

    @Test
    func deterministicColorForStringIsStableWithinProcess() {
        // `String.hashValue` is process-stable (re-seeded each launch);
        // within a single process two calls with the same key must agree.
        let a = BrandColor.deterministicColor(for: "Daily standup")
        let b = BrandColor.deterministicColor(for: "Daily standup")
        #expect(a == b)
    }

    @Test func pageBackgroundIsNonClear() {
        // Smoke: BrandColor.pageBackground resolves to *some* color,
        // not Color.clear. Cross-platform value (UIKit vs macOS fallback).
        #expect(BrandColor.pageBackground != Color.clear)
    }

    @Test func cardBackgroundIsNonClear() {
        // Smoke: card surfaces must use a dynamic system-backed token,
        // not a hard-coded light-only Color.white.
        #expect(BrandColor.cardBackground != Color.clear)
    }

    @Test
    func deterministicColorPaletteMembership() {
        let inputs = [
            "Daily standup", "Reading list", "Pic-of-the-day", "Bug report",
            "Release note", "Coffee", "Quick thought", "Long form essay",
            "Photo dump", "Link share", "Meeting prep", "Sprint retro",
            "Roadmap update", "Standup notes", "Hot take", "Cold take",
            "Weekly summary", "Demo prep", "Pairing notes", "Random",
        ]
        for input in inputs {
            let color = BrandColor.deterministicColor(for: input)
            #expect(
                BrandColor.deterministicPalette.contains(color),
                "deterministicColor(for: \"\(input)\") not in palette"
            )
        }
    }
}

@Suite("LeadIcon adaptive style")
struct LeadIconStyleTests {

    @Test
    func lightModeUsesSolidTintWithWhiteSymbol() {
        let style = LeadIcon.resolvedStyle(for: .light, tint: BrandColor.tint)

        #expect(style.background == BrandColor.tint)
        #expect(style.symbol == .white)
    }

    @Test
    func darkModeUsesTintedSurfaceWithTintSymbol() {
        let style = LeadIcon.resolvedStyle(for: .dark, tint: BrandColor.tint)

        #expect(style.background == BrandColor.tint.opacity(0.18))
        #expect(style.symbol == BrandColor.tint)
    }
}

@Suite("WelcomeHero accessibility")
struct WelcomeHeroAccessibilityTests {

    @Test
    @MainActor
    func welcomeHeroAccessibilityLabelComposesTitleAndSubtitle() {
        let label = WelcomeHero<EmptyView>.composeAccessibilityLabel(
            title: "Posted!",
            subtitle: "at://did:plc:foo/app.bsky.feed.post/abc"
        )
        #expect(label == "Posted!. at://did:plc:foo/app.bsky.feed.post/abc")
    }
}
