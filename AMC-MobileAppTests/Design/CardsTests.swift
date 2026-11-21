import Testing
@testable import AMC_MobileApp

@MainActor
struct OfferCardTests {
    func card(shares: Int, households: Int) -> OfferCard {
        OfferCard(offer: CardPreviewData.offer, product: CardPreviewData.product, vendor: CardPreviewData.vendor, committedShares: shares, committedHouseholds: households)
    }

    @Test func priceFollowsReachedTier() {
        #expect(card(shares: 0, households: 0).currentPriceCents == 320)
        #expect(card(shares: 24, households: 24).currentPriceCents == 260)
        #expect(card(shares: 30, households: 28).currentPriceCents == 210)
    }

    @Test func savingsMatchesMockup() {
        #expect(card(shares: 24, households: 24).savingsPercent == 37)
    }

    @Test func progressText() {
        #expect(card(shares: 24, households: 24).progressText == "24 familles · 24 parts sur 40")
        #expect(card(shares: 1, households: 1).progressText == "1 famille · 1 parts sur 40")
    }

    @Test func everyCategoryHasASymbol() {
        for category in Product.Category.allCases {
            #expect(!ProductIcon.symbol(for: category).isEmpty)
        }
    }
}

@MainActor
struct GroupCardTests {
    @Test func detailTextMatchesMockup() {
        let card = GroupCard(group: CardPreviewData.group, pickupLabel: "rue Ogilvy", distanceMeters: 450)
        #expect(card.detailText == "24 familles · cueillette rue Ogilvy · 450 m")
    }

    @Test func detailTextWithoutOptionalParts() {
        #expect(GroupCard(group: CardPreviewData.group).detailText == "24 familles")
    }

    @Test func distanceInKilometers() {
        #expect(GroupCard.distanceText(1_200) == "1,2 km")
    }
}
