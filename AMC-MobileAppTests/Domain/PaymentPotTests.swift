import Foundation
import Testing
@testable import AMC_MobileApp

/// E21 : commission de l'app, pot du groupe et versement au vendeur.
struct PaymentPotTests {
    private let offer = TierEngineTests.offer

    private func order(_ status: GroupOrder.Status = .closed, committed: Int = 4) -> GroupOrder {
        TierEngineTests.order(committed: committed, status: status)
    }

    /// h1 : 2 parts (1 980 ¢), h2 : 1 part subventionnée de 700 ¢, h3 : 1 part + 500 ¢ de panier suspendu.
    /// Montants dus : h1 1 980, h2 290, h3 1 490.
    private func allocated(paid: Set<String> = [], pickedUp: Set<String> = []) throws -> [Share] {
        try ShareAllocator.allocate(
            orderId: "go1", offer: offer,
            shares: [
                TierEngineTests.share("h1", 2),
                TierEngineTests.share("h2", 1),
                TierEngineTests.share("h3", 1, suspended: 500),
            ],
            unitPriceCents: 990, eligibleHouseholdIds: ["h2"], solidarityFundCents: 200
        ).shares.map { share in
            var share = share
            share.isPaid = paid.contains(share.householdId)
            share.isPickedUp = pickedUp.contains(share.householdId)
            return share
        }
    }

    // MARK: Commission

    @Test func defaultRateIsOnePercent() {
        #expect(Commission.defaultRate == 100)
        #expect(Commission.standard.rateBasisPoints == 100)
        #expect(Commission.standard.fee(onCents: 10_000) == 100)
        #expect(Commission.standard.net(onCents: 10_000) == 9_900)
    }

    @Test(arguments: [(100, 1), (50, 1), (49, 0), (150, 2), (149, 1), (1_980, 20), (990, 10), (1_000_000, 10_000)])
    func feeIsRoundedToTheNearestCent(amount: Cents, fee: Cents) {
        #expect(Commission.standard.fee(onCents: amount) == fee)
        #expect(Commission.standard.net(onCents: amount) == amount - fee)
    }

    @Test(arguments: [0, -1, -5_000])
    func zeroOrNegativeAmountHasNoFee(amount: Cents) {
        #expect(Commission.standard.fee(onCents: amount) == 0)
        #expect(Commission.standard.net(onCents: amount) == 0)
    }

    @Test func rateIsClampedBetweenZeroAndOneHundredPercent() {
        #expect(Commission(rateBasisPoints: 20_000).rateBasisPoints == 10_000)
        #expect(Commission(rateBasisPoints: 20_000).fee(onCents: 123) == 123)
        #expect(Commission(rateBasisPoints: 20_000).net(onCents: 123) == 0)
        #expect(Commission(rateBasisPoints: -50).rateBasisPoints == 0)
        #expect(Commission(rateBasisPoints: -50).fee(onCents: 123) == 0)
    }

    @Test(arguments: [0, 100, 600, 1_250, 5_000, 9_999, 10_000])
    func feeAndNetAlwaysAddUpToTheAmount(rate: Int) {
        let commission = Commission(rateBasisPoints: rate)
        for amount in 0...3_000 {
            let fee = commission.fee(onCents: amount)
            #expect(fee >= 0 && fee <= amount)
            #expect(fee + commission.net(onCents: amount) == amount)
        }
    }

    // MARK: Pot

    @Test func partiallyPaidPotCountsPartsHouseholdsAndMoney() throws {
        let pot = PaymentPot(order: order(), shares: try allocated(paid: ["h1", "h3"]), offer: offer)
        #expect(pot.paidShareCount == 3)
        #expect(pot.totalShareCount == 4)
        #expect(pot.paidHouseholdCount == 2)
        #expect(pot.householdCount == 3)
        #expect(pot.collectedCents == 3_470)
        #expect(pot.collectedForVendorCents == 2_970)
        #expect(pot.collectedDonationsCents == 500)
        #expect(pot.totalDueCents == 3_760)
        #expect(pot.remainingCents == 290)
        #expect(pot.projectedCents == 3_960)
        #expect(pot.isSettled)
        #expect(!pot.isFullyPaid)
    }

    @Test func fullyPaidPotHasNothingRemaining() throws {
        let pot = PaymentPot(order: order(.delivered), shares: try allocated(paid: ["h1", "h2", "h3"]), offer: offer)
        #expect(pot.collectedCents == 3_760)
        #expect(pot.collectedForVendorCents == 3_260)
        #expect(pot.remainingCents == 0)
        #expect(pot.isFullyPaid)
    }

    @Test func subsidyIsNotCollectedFromTheFamily() throws {
        let pot = PaymentPot(order: order(), shares: try allocated(paid: ["h2"]), offer: offer)
        #expect(pot.collectedCents == 290)
        #expect(pot.collectedForVendorCents == 290)
        #expect(pot.collectedDonationsCents == 0)
    }

    @Test func emptySharesAreIgnored() throws {
        var shares = try allocated(paid: ["h1"])
        shares.append(TierEngineTests.share("h9", 0))
        let pot = PaymentPot(order: order(), shares: shares, offer: offer)
        #expect(pot.householdCount == 3)
        #expect(pot.totalShareCount == 4)
    }

    @Test(arguments: [(7, 8_050), (10, 11_500), (25, 24_750), (30, 25_500), (0, 0)])
    func openOrderProjectsTheCurrentTierPrice(committed: Int, projected: Cents) {
        let shares = [TierEngineTests.share("h1", committed)]
        let pot = PaymentPot(order: order(.open, committed: committed), shares: shares, offer: offer)
        #expect(pot.projectedCents == projected)
        #expect(!pot.isSettled)
        #expect(pot.totalDueCents == 0)
        #expect(pot.collectedCents == 0)
        #expect(pot.remainingCents == 0)
    }

    @Test func paidFlagBeforeClosureIsNotCounted() {
        var share = TierEngineTests.share("h1", 12)
        share.isPaid = true
        let pot = PaymentPot(order: order(.reached, committed: 12), shares: [share], offer: offer)
        #expect(pot.paidShareCount == 0)
        #expect(pot.paidHouseholdCount == 0)
        #expect(pot.collectedCents == 0)
        #expect(pot.projectedCents == 12 * 1_150)
    }

    @Test func cancelledPotIsEmpty() throws {
        let pot = PaymentPot(order: order(.cancelled), shares: try allocated(paid: ["h1"]), offer: offer)
        #expect(pot.projectedCents == 0)
        #expect(pot.collectedCents == 0)
        #expect(pot.totalDueCents == 0)
        #expect(!pot.isSettled)
        #expect(!pot.isFullyPaid)
        #expect(pot.totalShareCount == 4)
    }

    @Test func emptyPotIsNotFullyPaid() {
        let pot = PaymentPot(order: order(), shares: [], offer: offer)
        #expect(pot.householdCount == 0)
        #expect(!pot.isFullyPaid)
    }

    @Test(arguments: [(0, 3, 3_450), (12, 3, 3_450), (25, 3, 2_970), (35, 2, 1_700), (25, 0, 0), (25, -1, 0)])
    func maxPriceUsesTheCurrentTier(committed: Int, quantity: Int, max: Cents) {
        let order = order(.open, committed: committed)
        #expect(PaymentPot.maxPriceCents(quantity: quantity, offer: offer, order: order) == max)
    }

    @Test func maxPriceNeverIncreasesAsTheGroupGrows() {
        var previous = Cents.max
        for committed in 0...40 {
            let price = PaymentPot.maxPriceCents(quantity: 2, offer: offer, order: order(.open, committed: committed))
            #expect(price <= previous)
            previous = price
        }
    }

    @Test func maxPriceIsZeroWithoutTiers() {
        var offer = offer
        offer.tiers = []
        #expect(PaymentPot.maxPriceCents(quantity: 3, offer: offer, order: order(.open, committed: 12)) == 0)
    }

    // MARK: Versement vendeur

    @Test func modeDependsOnVerification() {
        #expect(VendorPayout.mode(vendorIsVerified: false) == .atPickup)
        #expect(VendorPayout.mode(vendorIsVerified: true) == .deposit)
    }

    @Test func unverifiedVendorIsPaidAtPickup() throws {
        let shares = try allocated(paid: ["h1", "h2", "h3"], pickedUp: ["h1"])
        let payout = VendorPayout(order: order(), shares: shares, vendorIsVerified: false)
        #expect(payout.mode == .atPickup)
        // Subvention comprise (fonds de solidarité), don de h3 exclu.
        #expect(payout.grossCents == 3_960)
        #expect(payout.commissionCents == 20 + 10 + 10)
        #expect(payout.netCents == 3_920)
        #expect(payout.releasedCents == 1_960)
        #expect(payout.heldCents == 1_960)
    }

    @Test func unverifiedVendorGetsNothingBeforePickup() throws {
        let payout = VendorPayout(order: order(), shares: try allocated(paid: ["h1", "h2", "h3"]), vendorIsVerified: false)
        #expect(payout.netCents == 3_920)
        #expect(payout.releasedCents == 0)
        #expect(payout.heldCents == 3_920)
    }

    @Test func verifiedVendorGetsHalfAtClosure() throws {
        let payout = VendorPayout(order: order(), shares: try allocated(paid: ["h1", "h2", "h3"]), vendorIsVerified: true)
        #expect(payout.mode == .deposit)
        // 1 960 / 2 = 980, 980 / 2 = 490 (deux fois) : arrondi au cent inférieur.
        #expect(payout.releasedCents == 980 + 490 + 490)
        #expect(payout.heldCents == 1_960)
    }

    @Test func verifiedVendorGetsTheRestAtPickup() throws {
        let shares = try allocated(paid: ["h1", "h2", "h3"], pickedUp: ["h1"])
        let payout = VendorPayout(order: order(.delivered), shares: shares, vendorIsVerified: true)
        #expect(payout.releasedCents == 1_960 + 490 + 490)
        #expect(payout.heldCents == 490 + 490)

        let all = try allocated(paid: ["h1", "h2", "h3"], pickedUp: ["h1", "h2", "h3"])
        let done = VendorPayout(order: order(.delivered), shares: all, vendorIsVerified: true)
        #expect(done.releasedCents == done.netCents)
        #expect(done.heldCents == 0)
    }

    @Test func unpaidSharesAreNotPaidOutEvenWhenPickedUp() throws {
        let shares = try allocated(paid: ["h2"], pickedUp: ["h1", "h2"])
        let payout = VendorPayout(order: order(), shares: shares, vendorIsVerified: false)
        #expect(payout.grossCents == 990)
        #expect(payout.commissionCents == 10)
        #expect(payout.releasedCents == 980)
        #expect(payout.heldCents == 0)
    }

    @Test func donationIsNotVendorRevenue() throws {
        let payout = VendorPayout(order: order(), shares: try allocated(paid: ["h3"]), vendorIsVerified: false)
        #expect(payout.grossCents == 990)
    }

    @Test(arguments: [GroupOrder.Status.open, .reached, .cancelled], [false, true])
    func nothingIsPaidOutBeforeClosureOrWhenCancelled(status: GroupOrder.Status, verified: Bool) throws {
        let shares = try allocated(paid: ["h1", "h2", "h3"], pickedUp: ["h1"])
        let payout = VendorPayout(order: order(status), shares: shares, vendorIsVerified: verified)
        #expect(payout.grossCents == 0)
        #expect(payout.commissionCents == 0)
        #expect(payout.netCents == 0)
        #expect(payout.releasedCents == 0)
        #expect(payout.heldCents == 0)
    }

    @Test func customCommissionRateIsApplied() throws {
        let shares = try allocated(paid: ["h1"])
        let payout = VendorPayout(
            order: order(), shares: shares, vendorIsVerified: false, commission: Commission(rateBasisPoints: 0)
        )
        #expect(payout.commissionCents == 0)
        #expect(payout.netCents == 1_980)
    }

    @Test(arguments: [false, true])
    func payoutInvariantsHoldForEveryCombination(verified: Bool) throws {
        let households = ["h1", "h2", "h3"]
        for paidMask in 0..<8 {
            for pickedMask in 0..<8 {
                let paid = Set(households.indices.filter { paidMask & (1 << $0) != 0 }.map { households[$0] })
                let picked = Set(households.indices.filter { pickedMask & (1 << $0) != 0 }.map { households[$0] })
                let shares = try allocated(paid: paid, pickedUp: picked)
                let payout = VendorPayout(order: order(), shares: shares, vendorIsVerified: verified)
                let pot = PaymentPot(order: order(), shares: shares, offer: offer)
                #expect(payout.releasedCents + payout.heldCents == payout.netCents)
                #expect(payout.netCents + payout.commissionCents == payout.grossCents)
                #expect(payout.releasedCents >= 0 && payout.heldCents >= 0)
                // Le vendeur reçoit l'argent des familles (sans dons) plus les subventions des parts payées.
                let subsidies = shares.filter(\.isPaid).reduce(0) { $0 + $1.subsidyCents }
                #expect(payout.grossCents == pot.collectedForVendorCents + subsidies)
                #expect(pot.collectedCents == pot.collectedForVendorCents + pot.collectedDonationsCents)
            }
        }
    }

    @Test func collectedForVendorMatchesVendorRevenue() throws {
        let shares = try allocated(paid: ["h1", "h2", "h3"])
        let payments = try PaymentSimulator().payAll(shares: try allocated(), order: order())
        let report = VendorRevenue.report(
            vendorId: "v1", offers: [offer], orders: [order()], sharesByOrder: ["go1": shares], payments: payments
        )
        let pot = PaymentPot(order: order(), shares: shares, offer: offer)
        let payout = VendorPayout(order: order(), shares: shares, vendorIsVerified: false)
        #expect(pot.collectedForVendorCents == report.total.collectedCents)
        #expect(payout.grossCents == report.total.grossCents)
    }
}
