import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-057 : tests de TierEngine (RQ-051 à RQ-054).
struct TierEngineTests {
    static let deadline = Date(timeIntervalSince1970: 1_795_000_000)

    static let offer = Offer(
        id: "o1", vendorId: "v1", productId: "p1", totalShares: 40, shareUnit: "10 kg",
        tiers: [
            PriceTier(minShares: 20, priceCents: 990),
            PriceTier(minShares: 10, priceCents: 1_150),
            PriceTier(minShares: 30, priceCents: 850),
        ],
        minimumSharesToLaunch: 10, deadline: deadline, zones: [], status: .active
    )

    static func order(committed: Int = 0, status: GroupOrder.Status = .open) -> GroupOrder {
        GroupOrder(
            id: "go1", groupId: "g1", offerId: "o1", status: status,
            currentTierIndex: offer.tierIndex(forCommittedShares: committed),
            committedShares: committed, committedHouseholds: 0, pickupPointId: nil, pickupSlots: []
        )
    }

    static func share(_ household: String, _ quantity: Int, suspended: Cents = 0) -> Share {
        Share(householdId: household, quantity: quantity, finalPriceCents: nil, isPaid: false,
              suspendedAmountCents: suspended, subsidyCents: 0, qrCode: nil, isPickedUp: false)
    }

    // MARK: Progress

    @Test func progressBelowFirstTierShowsTheLaunchPrice() {
        let progress = TierEngine.progress(offer: Self.offer, committedShares: 7)
        #expect(progress.currentTierIndex == nil)
        #expect(progress.unitPriceCents == 1_150)
        #expect(progress.sharesToNextTier == 3)
        #expect(!progress.isLaunchable)
        #expect(progress.remainingShares == 33)
    }

    @Test func progressBetweenTiers() {
        let progress = TierEngine.progress(offer: Self.offer, committedShares: 19)
        #expect(progress.currentTierIndex == 0)
        #expect(progress.unitPriceCents == 1_150)
        #expect(progress.nextTier == PriceTier(minShares: 20, priceCents: 990))
        #expect(progress.sharesToNextTier == 1)
        #expect(progress.isLaunchable)
    }

    @Test func progressAtLastTier() {
        let progress = TierEngine.progress(offer: Self.offer, committedShares: 40)
        #expect(progress.currentTierIndex == 2)
        #expect(progress.unitPriceCents == 850)
        #expect(progress.nextTier == nil)
        #expect(progress.sharesToNextTier == nil)
        #expect(progress.remainingShares == 0)
    }

    @MainActor @Test func summaryForVoiceOver() {
        #expect(TierEngine.nextTierSummary(TierEngine.progress(offer: Self.offer, committedShares: 19))
            .hasPrefix("Encore 1 part pour passer à"))
        #expect(TierEngine.nextTierSummary(TierEngine.progress(offer: Self.offer, committedShares: 25))
            .hasPrefix("Encore 5 parts"))
        #expect(TierEngine.nextTierSummary(TierEngine.progress(offer: Self.offer, committedShares: 30)) == "Meilleur prix atteint")
    }

    // MARK: RQ-051 recalcul

    @Test func recalculationUpdatesTotalsTierAndStatus() throws {
        let shares = [Self.share("h1", 12), Self.share("h2", 8), Self.share("h3", 0)]
        let order = try TierEngine.recalculated(Self.order(), offer: Self.offer, shares: shares)
        #expect(order.committedShares == 20)
        #expect(order.committedHouseholds == 2)
        #expect(order.currentTierIndex == 1)
        #expect(order.status == .reached)
    }

    @Test func recalculationGoesBackToOpenBelowTheMinimum() throws {
        let order = try TierEngine.recalculated(Self.order(committed: 12, status: .reached), offer: Self.offer,
                                                shares: [Self.share("h1", 9)])
        #expect(order.status == .open)
        #expect(order.currentTierIndex == nil)
    }

    @Test func recalculationRefusesMoreThanTheLot() {
        #expect(throws: AppError.invalidInput("Ce lot ne compte que 40 parts.")) {
            try TierEngine.recalculated(Self.order(), offer: Self.offer, shares: [Self.share("h1", 41)])
        }
    }

    @Test func recalculationRefusesAClosedOrder() {
        for status in [GroupOrder.Status.closed, .delivered, .cancelled] {
            #expect(throws: AppError.orderClosed) {
                try TierEngine.recalculated(Self.order(status: status), offer: Self.offer, shares: [])
            }
        }
    }

    // MARK: RQ-052

    @Test func crossingDetectsOnlyUpwardMoves() {
        #expect(TierEngine.crossedNewTier(from: Self.order(committed: 19), to: Self.order(committed: 20)))
        #expect(TierEngine.crossedNewTier(from: Self.order(committed: 9), to: Self.order(committed: 10)))
        #expect(!TierEngine.crossedNewTier(from: Self.order(committed: 20), to: Self.order(committed: 19)))
        #expect(!TierEngine.crossedNewTier(from: Self.order(committed: 21), to: Self.order(committed: 25)))
    }

    @Test func priceIsFrozenAfterClosure() throws {
        let (closed, _) = try TierEngine.closed(Self.order(committed: 25, status: .reached), offer: Self.offer)
        #expect(closed.status == .closed)
        #expect(closed.currentTierIndex == 1)
        // Plus aucun changement de part possible : le prix ne peut ni monter ni descendre.
        #expect(throws: AppError.orderClosed) {
            try TierEngine.recalculated(closed, offer: Self.offer, shares: [Self.share("h1", 2)])
        }
        #expect(throws: AppError.orderClosed) { try TierEngine.closed(closed, offer: Self.offer) }
    }

    // MARK: RQ-053, RQ-054

    @Test func shouldCloseOnlyAfterTheDeadlineWhileOpen() {
        let before = Self.deadline.addingTimeInterval(-1)
        #expect(!TierEngine.shouldClose(Self.order(committed: 12), offer: Self.offer, now: before))
        #expect(TierEngine.shouldClose(Self.order(committed: 12), offer: Self.offer, now: Self.deadline))
        #expect(!TierEngine.shouldClose(Self.order(status: .cancelled), offer: Self.offer, now: Self.deadline))
    }

    @Test func closureConfirmsAtTheReachedTier() throws {
        let (order, outcome) = try TierEngine.closed(Self.order(committed: 33, status: .reached), offer: Self.offer)
        #expect(outcome == .confirmed(tierIndex: 2, unitPriceCents: 850))
        #expect(order.status == .closed)
    }

    @Test func closureCancelsBelowTheMinimum() throws {
        let (order, outcome) = try TierEngine.closed(Self.order(committed: 9), offer: Self.offer)
        #expect(outcome == .cancelled)
        #expect(order.status == .cancelled)
    }
}
