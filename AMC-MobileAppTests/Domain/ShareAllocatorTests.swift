import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-057 : tests de ShareAllocator (RQ-055).
struct ShareAllocatorTests {
    private let offer = TierEngineTests.offer
    private func share(_ household: String, _ quantity: Int, suspended: Cents = 0) -> Share {
        TierEngineTests.share(household, quantity, suspended: suspended)
    }

    @Test func finalPricesQRCodesAndLeftovers() throws {
        let allocation = try ShareAllocator.allocate(
            orderId: "go1", offer: offer,
            shares: [share("h2", 3), share("h1", 2), share("h3", 0)],
            unitPriceCents: 990
        )
        #expect(allocation.shares.map(\.householdId) == ["h1", "h2"])
        #expect(allocation.shares.map(\.finalPriceCents) == [1_980, 2_970])
        #expect(allocation.shares.allSatisfy { $0.subsidyCents == 0 && $0.qrCode != nil })
        #expect(allocation.unallocatedShares == 35)
        #expect(allocation.totalDueCents == 4_950)
        #expect(allocation.fundUsedCents == 0)
    }

    @Test func fundPaysEligibleSharesInFullWhenItIsEnough() throws {
        let allocation = try ShareAllocator.allocate(
            orderId: "go1", offer: offer, shares: [share("h1", 2), share("h2", 1)],
            unitPriceCents: 990, eligibleHouseholdIds: ["h2"], solidarityFundCents: 5_000
        )
        #expect(allocation.shares.first { $0.householdId == "h2" }?.subsidyCents == 990)
        #expect(allocation.shares.first { $0.householdId == "h1" }?.subsidyCents == 0)
        #expect(allocation.fundUsedCents == 990)
        #expect(allocation.fundRemainingCents == 4_010)
        #expect(allocation.totalDueCents == 1_980)
    }

    @Test func suspendedBasketsFeedTheFund() throws {
        let allocation = try ShareAllocator.allocate(
            orderId: "go1", offer: offer,
            shares: [share("h1", 1, suspended: 500), share("h2", 1, suspended: 490), share("h3", 1)],
            unitPriceCents: 990, eligibleHouseholdIds: ["h3"]
        )
        #expect(allocation.shares.first { $0.householdId == "h3" }?.subsidyCents == 990)
        #expect(allocation.fundRemainingCents == 0)
    }

    @Test func insufficientFundIsSplitProRataWithoutLosingACent() throws {
        let allocation = try ShareAllocator.allocate(
            orderId: "go1", offer: offer, shares: [share("h1", 1), share("h2", 2), share("h3", 3)],
            unitPriceCents: 1_000, eligibleHouseholdIds: ["h1", "h2", "h3"], solidarityFundCents: 1_000
        )
        let subsidies = allocation.shares.map(\.subsidyCents)
        #expect(subsidies.reduce(0, +) == 1_000)
        #expect(subsidies == [167, 333, 500])
        #expect(allocation.fundRemainingCents == 0)
        #expect(allocation.totalDueCents == 5_000)
    }

    @Test func proportionalSplitProperties() {
        #expect(ShareAllocator.proportionalSplit(100, weights: [1, 1, 1]) == [1, 1, 1])
        #expect(ShareAllocator.proportionalSplit(2, weights: [1, 1, 1]) == [1, 1, 0])
        #expect(ShareAllocator.proportionalSplit(10, weights: [0, 0]) == [0, 0])
        #expect(ShareAllocator.proportionalSplit(0, weights: [5, 5]) == [0, 0])
        for amount in [1, 7, 333, 999, 1_000] {
            let weights = [990, 1_980, 2_970, 13]
            let parts = ShareAllocator.proportionalSplit(amount, weights: weights)
            #expect(parts.reduce(0, +) == amount)
            #expect(zip(parts, weights).allSatisfy { $0 <= $1 })
        }
    }

    @Test func refusesMoreSharesThanTheLotAndNegativeAmounts() {
        #expect(throws: AppError.self) {
            try ShareAllocator.allocate(orderId: "go1", offer: offer, shares: [share("h1", 41)], unitPriceCents: 990)
        }
        #expect(throws: AppError.self) {
            try ShareAllocator.allocate(orderId: "go1", offer: offer, shares: [], unitPriceCents: -1)
        }
    }

    @Test func qrCodeRoundTripsAndRejectsTampering() {
        let code = ShareAllocator.qrCode(orderId: "go1", householdId: "household-benali")
        #expect(ShareAllocator.householdId(fromQRCode: code, orderId: "go1") == "household-benali")
        #expect(ShareAllocator.householdId(fromQRCode: code, orderId: "go2") == nil)
        let tampered = code.replacingOccurrences(of: "benali", with: "voisin")
        #expect(ShareAllocator.householdId(fromQRCode: tampered, orderId: "go1") == nil)
        #expect(ShareAllocator.householdId(fromQRCode: "n'importe quoi", orderId: "go1") == nil)
    }

    @Test func endToEndClosureOfTheDemoOrder() async throws {
        let data = FakeData.montreal
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        typealias ID = FakeData.ID
        let order = try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let offer = try #require(data.offers.first { $0.id == ID.potatoOffer })
        let (closed, outcome) = try TierEngine.closed(order, offer: offer)
        guard case .confirmed(_, let price) = outcome else {
            Issue.record("La commande de démo devrait être confirmée")
            return
        }
        #expect(price == 990)
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        let allocation = try ShareAllocator.allocate(orderId: closed.id, offer: offer, shares: shares, unitPriceCents: price)
        #expect(allocation.shares.reduce(0) { $0 + $1.quantity } == 20)
        #expect(allocation.totalDueCents == 20 * 990)
    }
}
