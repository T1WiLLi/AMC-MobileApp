import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct MoneyTests {
    @Test func formatsCentsInCanadianFrench() {
        // fr_CA : « 2,60 $ » (espace insécable possible avant $)
        let text = Money.format(260)
        #expect(text.contains("2,60"))
        #expect(text.contains("$"))
    }

    @Test func roundedDropsDecimalsWhenWhole() {
        #expect(Money.formatRounded(4800).contains("48"))
        #expect(!Money.formatRounded(4800).contains(","))
        #expect(Money.formatRounded(4850).contains("48,50"))
    }

    @Test func savingsPercent() {
        #expect(Money.savingsPercent(price: 260, reference: 410) == 37)
        #expect(Money.savingsPercent(price: 210, reference: 260) == 19)
        #expect(Money.savingsPercent(price: 500, reference: 400) == 0)
        #expect(Money.savingsPercent(price: 100, reference: 0) == 0)
    }
}

@MainActor
struct TierProgressBarTests {
    let tiers = [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260), PriceTier(minShares: 26, priceCents: 210)]

    @Test func currentTierFollowsCommittedShares() {
        #expect(TierProgressBar(tiers: tiers, committedShares: 0).currentIndex == nil)
        #expect(TierProgressBar(tiers: tiers, committedShares: 1).currentIndex == 0)
        #expect(TierProgressBar(tiers: tiers, committedShares: 24).currentIndex == 1)
        #expect(TierProgressBar(tiers: tiers, committedShares: 30).currentIndex == 2)
    }

    @Test func unsortedTiersAreSorted() {
        let bar = TierProgressBar(tiers: tiers.reversed(), committedShares: 24)
        #expect(bar.currentIndex == 1)
    }

    @Test func segmentsFillBetweenThresholds() {
        let bar = TierProgressBar(tiers: tiers, committedShares: 24, totalShares: 40)
        #expect(bar.fill(forSegment: 0) == 1)
        #expect(abs(bar.fill(forSegment: 1) - 13.0 / 15.0) < 0.0001)
        #expect(bar.fill(forSegment: 2) == 0)
    }

    @Test func nudgeMatchesMockup() {
        let bar = TierProgressBar(tiers: tiers, committedShares: 25, unitSingular: "famille", unitPlural: "familles")
        #expect(bar.nudge == "Encore 1 famille pour débloquer −19 %")
    }

    @Test func nudgeBeforeFirstTier() {
        let bar = TierProgressBar(tiers: [PriceTier(minShares: 5, priceCents: 300)], committedShares: 2)
        #expect(bar.nudge == "Encore 3 parts pour lancer la commande")
    }

    @Test func noNudgeOnLastTier() {
        #expect(TierProgressBar(tiers: tiers, committedShares: 26).nudge == nil)
    }

    @Test func shortNudgeMatchesF1() {
        let bar = TierProgressBar(tiers: tiers, committedShares: 25, unitSingular: "famille", unitPlural: "familles")
        #expect(bar.shortNudge == "Encore 1 famille pour −19 %")
    }

    @Test func launchFollowsMinimumToLaunch() {
        // Le premier palier est à 1 part, mais le lot ne part qu'à 10.
        let bar = TierProgressBar(tiers: tiers, committedShares: 3, minimumToLaunch: 10)
        #expect(bar.launchThreshold == 10)
        #expect(bar.nudge == "Encore 7 parts pour lancer la commande")
        #expect(bar.shortNudge == "Encore 7 parts pour lancer la commande")
    }

    @Test func launchSingular() {
        let bar = TierProgressBar(tiers: tiers, committedShares: 9, minimumToLaunch: 10)
        #expect(bar.nudge == "Encore 1 part pour lancer la commande")
    }

    @Test func launchReachedFallsBackToNextTier() {
        let bar = TierProgressBar(tiers: tiers, committedShares: 10, minimumToLaunch: 10)
        #expect(bar.nudge == "Encore 1 part pour débloquer −19 %")
    }

    @Test func withoutMinimumUsesFirstTier() {
        #expect(TierProgressBar(tiers: tiers, committedShares: 0).launchThreshold == 1)
        #expect(TierProgressBar(tiers: tiers, committedShares: 0).nudge == "Encore 1 part pour lancer la commande")
    }

    @Test func accessibilityAgreesInNumber() {
        #expect(TierProgressBar(tiers: tiers, committedShares: 0).accessibilityText.hasPrefix("0 part engagée"))
        #expect(TierProgressBar(tiers: tiers, committedShares: 1).accessibilityText.hasPrefix("1 part engagée,"))
        #expect(TierProgressBar(tiers: tiers, committedShares: 24).accessibilityText.hasPrefix("24 parts engagées,"))
    }
}

@MainActor
struct AvatarStackTests {
    @Test func announcesShownPlusExtra() {
        #expect(AvatarStack(initials: ["FB", "RK"], extraCount: 21).accessibilityText == "23 membres")
    }

    @Test func neverCountsHiddenInitials() {
        // 5 initiales, seules 3 sont affichées : le groupe de 24 doit être annoncé à 24, pas 26.
        let group = CardPreviewData.group
        let card = GroupCard(group: group, memberInitials: ["AM", "FB", "RK", "LT", "SN"])
        let stack = AvatarStack(initials: card.memberInitials, extraCount: card.extraMembers)
        #expect(stack.memberCount == group.householdCount)
        #expect(stack.accessibilityText == "24 membres")
    }

    @Test func singleMember() {
        #expect(AvatarStack(initials: ["AM"]).accessibilityText == "1 membre")
    }
}

@MainActor
struct PriceTagTests {
    @Test func accessibilityReadsUnit() {
        let text = PriceTag(priceCents: 260, unit: "kg", referenceCents: 410).accessibilityText
        #expect(text == "2 dollars 60 le kilo, au lieu de 4 dollars 10 en épicerie")
    }

    @Test func accessibilityWithoutUnit() {
        #expect(PriceTag(priceCents: 1_450).accessibilityText == "14 dollars 50")
        #expect(PriceTag(priceCents: 900, unit: "caisse").accessibilityText == "9 dollars par caisse")
    }
}

@MainActor
struct SpokenMoneyTests {
    @Test func readsDollarsAndCents() {
        #expect(Money.spoken(260) == "2 dollars 60")
        #expect(Money.spoken(4_800) == "48 dollars")
        #expect(Money.spoken(100) == "1 dollar")
        #expect(Money.spoken(105) == "1 dollar 5")
        #expect(Money.spoken(60) == "60 cents")
        #expect(Money.spoken(1) == "1 cent")
        #expect(Money.spoken(0) == "0 cent")
        #expect(Money.spoken(-250) == "moins 2 dollars 50")
    }

    @Test func readsTheUnit() {
        #expect(Money.spoken(210, per: "kg") == "2 dollars 10 le kilo")
        #expect(Money.spoken(210, per: nil) == "2 dollars 10")
        #expect(Money.spokenPerUnit("L") == "le litre")
    }

    @Test func savingsBadgeReadsAmountAndPercent() {
        #expect(SavingsBadge(kind: .amount(4_800)).accessibilityText == "48 dollars économisés")
        #expect(SavingsBadge(kind: .percent(37), compact: true).accessibilityText == "37 pour cent moins cher qu'en épicerie")
    }

    @Test func tierBarReadsCurrentPrice() {
        let tiers = [PriceTier(minShares: 1, priceCents: 320), PriceTier(minShares: 11, priceCents: 260)]
        #expect(TierProgressBar(tiers: tiers, committedShares: 12).accessibilityText.contains("prix actuel 2 dollars 60"))
    }
}

@MainActor
struct ContrastTests {
    /// Ratio WCAG 2.x entre deux couleurs sRGB opaques (hex 0xRRGGBB).
    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { Double($0) / 255 }
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Couleur `hex` à `alpha` posée sur `background`.
    static func blend(_ hex: UInt32, alpha: Double, on background: UInt32) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let top = Double((hex >> shift) & 0xFF), bottom = Double((background >> shift) & 0xFF)
            return UInt32((top * alpha + bottom * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// Palette Grenier (asset catalog), clair puis sombre.
    struct Palette { let fond, surface, texte, secondaire, grenier, economie, solidarite, onAccent: UInt32 }
    static let light = Palette(fond: 0xFBF7F0, surface: 0xFFFFFF, texte: 0x1C1712, secondaire: 0x6B5F53,
                               grenier: 0xA84D18, economie: 0x1F7A4A, solidarite: 0x6B4FB3, onAccent: 0xFFFFFF)
    static let dark = Palette(fond: 0x14110E, surface: 0x211D19, texte: 0xF5EFE6, secondaire: 0xB8AC9F,
                              grenier: 0xF08A4B, economie: 0x4CC488, solidarite: 0xA992F0, onAccent: 0x1C1712)

    @Test(arguments: [0, 1])
    func textPairsPassAA(_ index: Int) {
        let p = [Self.light, Self.dark][index]
        for background in [p.fond, p.surface] {
            for text in [p.texte, p.secondaire, p.grenier, p.economie, p.solidarite] {
                #expect(Self.ratio(text, background) >= 4.5)
            }
        }
        for fill in [p.grenier, p.economie, p.solidarite] {
            #expect(Self.ratio(p.onAccent, fill) >= 4.5)
            // Pilules et pastilles : couleur sur sa teinte à 12 % (SavingsBadge, AvatarStack).
            #expect(Self.ratio(fill, Self.blend(fill, alpha: 0.12, on: p.surface)) >= 4.5)
        }
    }
}
