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
}
