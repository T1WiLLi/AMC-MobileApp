import Foundation
import Testing
@testable import AMC_MobileApp

/// T-093 : QA adverse de la logique métier (paliers, parts, solidarité, unités de part, montants).
/// Chaque test a d'abord échoué (ou planté) avant le correctif correspondant.
struct AdversarialDomainTests {
    private let offer = Offer(
        id: "o", vendorId: "v", productId: "p", totalShares: 40, shareUnit: "sac de 5 kg",
        tiers: [PriceTier(minShares: 8, priceCents: 739), PriceTier(minShares: 16, priceCents: 649)],
        minimumSharesToLaunch: 8, deadline: Date(timeIntervalSince1970: 2_000_000_000), zones: [], status: .active
    )
    private let order = GroupOrder(
        id: "g", groupId: "gr", offerId: "o", status: .open, currentTierIndex: nil,
        committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: []
    )

    private func share(_ householdId: String, _ quantity: Int, suspended: Cents = 0) -> Share {
        Share(householdId: householdId, quantity: quantity, finalPriceCents: nil, isPaid: false,
              suspendedAmountCents: suspended, subsidyCents: 0, qrCode: nil, isPickedUp: false)
    }

    // MARK: Paliers

    /// Une part négative effaçait les parts des autres : 20 + (−15) donnait 5 parts, sous le minimum.
    @Test func negativeQuantityIsRefusedByRecalculation() {
        #expect(throws: AppError.self) {
            try TierEngine.recalculated(order, offer: offer, shares: [share("a", 20), share("b", -15)])
        }
    }

    @Test func tierBoundariesAreInclusive() throws {
        let below = try TierEngine.recalculated(order, offer: offer, shares: [share("a", 7)])
        #expect(below.currentTierIndex == nil && below.status == .open)
        let atFirst = try TierEngine.recalculated(order, offer: offer, shares: [share("a", 8)])
        #expect(atFirst.currentTierIndex == 0 && atFirst.status == .reached)
        let beforeSecond = try TierEngine.recalculated(order, offer: offer, shares: [share("a", 15)])
        #expect(beforeSecond.currentTierIndex == 0)
        let atSecond = try TierEngine.recalculated(order, offer: offer, shares: [share("a", 16)])
        #expect(atSecond.currentTierIndex == 1)
        let full = try TierEngine.recalculated(order, offer: offer, shares: [share("a", 40)])
        #expect(full.currentTierIndex == 1 && full.committedShares == 40)
        #expect(throws: AppError.self) {
            try TierEngine.recalculated(order, offer: offer, shares: [share("a", 41)])
        }
    }

    @Test func deadlineBoundary() {
        #expect(!TierEngine.shouldClose(order, offer: offer, now: offer.deadline.addingTimeInterval(-0.001)))
        #expect(TierEngine.shouldClose(order, offer: offer, now: offer.deadline))
    }

    // MARK: Solidarité

    /// `Int.max` faisait déborder l'addition : plantage de l'app au lieu d'un message.
    @Test func hugeSuspendedBasketIsRefusedWithoutOverflow() {
        #expect(throws: AppError.self) {
            try SolidarityLedger.addingSuspendedBasket(Int.max, to: share("a", 1, suspended: 1), in: order)
        }
        #expect(throws: AppError.self) {
            try SolidarityLedger.addingSuspendedBasket(1, to: share("a", 1, suspended: SolidarityLedger.maxSuspendedAmountCents), in: order)
        }
    }

    @Test func suspendedBasketUpToTheCapIsAccepted() throws {
        let filled = try SolidarityLedger.addingSuspendedBasket(
            SolidarityLedger.maxSuspendedAmountCents - 500, to: share("a", 1, suspended: 500), in: order
        )
        #expect(filled.suspendedAmountCents == SolidarityLedger.maxSuspendedAmountCents)
    }

    /// Le total à encaisser oubliait les paniers suspendus que les familles paient (PaymentSimulator.amountDue).
    @Test func totalDueMatchesWhatEveryHouseholdPays() throws {
        let allocation = try ShareAllocator.allocate(
            orderId: "g", offer: offer,
            shares: [share("a", 4, suspended: 500), share("b", 4), share("c", 3, suspended: 1_234)],
            unitPriceCents: 739, eligibleHouseholdIds: ["b"], solidarityFundCents: 100
        )
        let paid = try allocation.shares.map(PaymentSimulator.amountDue).reduce(0, +)
        #expect(allocation.totalDueCents == paid)
        #expect(allocation.fundUsedCents + allocation.fundRemainingCents == 100 + 500 + 1_234)
    }

    @Test func subsidiesNeverExceedPriceNorFundAndLoseNoCent() throws {
        for fund in [0, 1, 2, 738, 739, 1_000, 5_911, 100_000] {
            let allocation = try ShareAllocator.allocate(
                orderId: "g", offer: offer, shares: [share("a", 1), share("b", 2), share("c", 5)],
                unitPriceCents: 739, eligibleHouseholdIds: ["a", "b", "c"], solidarityFundCents: fund
            )
            let subsidies = allocation.shares.map(\.subsidyCents)
            #expect(subsidies.reduce(0, +) == min(fund, 8 * 739))
            #expect(allocation.shares.allSatisfy { $0.subsidyCents <= ($0.finalPriceCents ?? 0) })
        }
    }

    // MARK: Unités de part et montants

    /// Un nombre trop grand dans `shareUnit` (texte libre du vendeur) faisait planter `Int(…)`.
    @Test func absurdShareUnitDoesNotCrash() {
        #expect(ShareMeasure.parse("99999999999999999999 unités") == .unknown)
        #expect(ShareMeasure.parse("99999999999999999999 kg").retailPackagesAvoided == 0)
        #expect(ShareMeasure.parse("99999999999999999999 douzaines") == .unknown)
        #expect(ShareMeasure.parse(String(repeating: "9", count: 400) + " kg").kilograms == 0)
        #expect(ShareMeasure.mass(kilograms: .infinity).retailPackagesAvoided == 0)
        #expect(ShareMeasure.parse("10 kg") == .mass(kilograms: 10))
        #expect(ShareMeasure.parse("10 kg").retailPackagesAvoided == 9)
    }

    @Test @MainActor func savingsPercentStaysBetweenZeroAndHundred() {
        #expect(Money.savingsPercent(price: -500, reference: 1_000) == 0)
        #expect(Money.savingsPercent(price: 0, reference: 1_000) == 100)
        #expect(Money.savingsPercent(price: 1_000, reference: 1_000) == 0)
        #expect(Money.savingsPercent(price: 1, reference: 0) == 0)
    }

    @Test @MainActor func moneyFormatsCentsExactly() {
        #expect(Money.format(1).contains("0,01"))
        #expect(Money.format(-150).contains("1,50"))
        #expect(Money.formatRounded(4_800).contains("48") && !Money.formatRounded(4_800).contains(","))
    }

    // MARK: Geohash

    @Test func geohashNeighborsWrapAroundTheAntimeridian() {
        let neighbors = Geohash.neighbors(of: "zzzzz")
        #expect(neighbors.contains { $0.hasPrefix("b") })
        #expect(Geohash.neighbors(of: "") == [])
        #expect(Geohash.cell(of: "f25dva") == nil) // « a » n'est pas en base 32
    }
}
