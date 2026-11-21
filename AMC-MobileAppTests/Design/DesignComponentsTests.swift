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
        #expect(text.contains("2,60"))
        #expect(text.contains("par kg"))
        #expect(text.contains("en épicerie"))
    }
}
