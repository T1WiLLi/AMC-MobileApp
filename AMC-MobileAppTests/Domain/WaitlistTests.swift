import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-056 : tests de la liste d'attente d'un lot complet.
struct WaitlistTests {
    static let offer = TierEngineTests.offer // 40 parts
    static let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    static func order(committed: Int = 0, status: GroupOrder.Status = .open) -> GroupOrder {
        TierEngineTests.order(committed: committed, status: status)
    }

    static func share(_ household: String, _ quantity: Int) -> Share {
        TierEngineTests.share(household, quantity)
    }

    static func entry(_ household: String, _ quantity: Int, minutes: Double) -> Waitlist.Entry {
        Waitlist.Entry(householdId: household, quantity: quantity, requestedAt: t0.addingTimeInterval(minutes * 60))
    }

    /// Lot complet : 40 parts sur 40.
    static let fullShares = [share("h1", 20), share("h2", 12), share("h3", 8)]

    // MARK: Inscription

    @Test func fullLotSendsTheRequestToTheWaitlist() throws {
        #expect(Waitlist.isFull(offer: Self.offer, shares: Self.fullShares))
        let waitlist = try Waitlist().joining(householdId: "h4", quantity: 3, at: Self.t0,
                                              order: Self.order(committed: 40, status: .reached), offer: Self.offer, shares: Self.fullShares)
        #expect(waitlist.entries == [Waitlist.Entry(householdId: "h4", quantity: 3, requestedAt: Self.t0)])
        #expect(waitlist.position(of: "h4") == 1)
    }

    @Test func requestThatFitsMustBeReservedDirectly() {
        let shares = [Self.share("h1", 30)]
        #expect(!Waitlist.isFull(offer: Self.offer, shares: shares))
        #expect(throws: AppError.invalidInput("Il reste assez de parts : réserve-les directement.")) {
            try Waitlist().joining(householdId: "h4", quantity: 5, at: Self.t0, order: Self.order(committed: 30), offer: Self.offer, shares: shares)
        }
    }

    @Test func noDuplicatePerHousehold() throws {
        let order = Self.order(committed: 40, status: .reached)
        let waitlist = try Waitlist().joining(householdId: "h4", quantity: 2, at: Self.t0, order: order, offer: Self.offer, shares: Self.fullShares)
        #expect(throws: AppError.invalidInput("Ton ménage est déjà sur la liste d'attente.")) {
            try waitlist.joining(householdId: "h4", quantity: 1, at: Self.t0.addingTimeInterval(60), order: order, offer: Self.offer, shares: Self.fullShares)
        }
    }

    @Test func invalidQuantitiesAreRefused() {
        let order = Self.order(committed: 40, status: .reached)
        #expect(throws: AppError.invalidInput("Choisis au moins une part.")) {
            try Waitlist().joining(householdId: "h4", quantity: 0, at: Self.t0, order: order, offer: Self.offer, shares: Self.fullShares)
        }
        #expect(throws: AppError.invalidInput("Ce lot ne compte que 40 parts.")) {
            try Waitlist().joining(householdId: "h4", quantity: 41, at: Self.t0, order: order, offer: Self.offer, shares: Self.fullShares)
        }
    }

    @Test func closedOrderRefusesNewEntries() {
        #expect(throws: AppError.orderClosed) {
            try Waitlist().joining(householdId: "h4", quantity: 1, at: Self.t0,
                                   order: Self.order(committed: 40, status: .closed), offer: Self.offer, shares: Self.fullShares)
        }
    }

    @Test func entriesAreServedInRequestOrder() {
        let waitlist = Waitlist(entries: [Self.entry("h5", 1, minutes: 5), Self.entry("h4", 1, minutes: 1), Self.entry("h6", 1, minutes: 5)])
        #expect(waitlist.entries.map(\.householdId) == ["h4", "h5", "h6"])
    }

    @Test func cancellingRemovesOnlyThatHousehold() {
        let waitlist = Waitlist(entries: [Self.entry("h4", 2, minutes: 0), Self.entry("h5", 1, minutes: 1)])
        #expect(waitlist.cancelling(householdId: "h4").entries.map(\.householdId) == ["h5"])
        #expect(waitlist.cancelling(householdId: "h9") == waitlist)
        #expect(!waitlist.cancelling(householdId: "h4").contains(householdId: "h4"))
    }

    // MARK: Promotion

    @Test func freedSharesPromoteInFifoOrder() throws {
        // h2 passe de 12 à 7 : 5 parts libres.
        let shares = [Self.share("h1", 20), Self.share("h2", 7), Self.share("h3", 8)]
        let waitlist = Waitlist(entries: [Self.entry("h4", 3, minutes: 0), Self.entry("h5", 2, minutes: 1), Self.entry("h6", 4, minutes: 2)])
        let result = try waitlist.promoting(order: Self.order(committed: 40, status: .reached), offer: Self.offer, shares: shares, now: Self.t0)

        #expect(result.promoted == [
            Waitlist.Promotion(householdId: "h4", quantity: 3, isPartial: false),
            Waitlist.Promotion(householdId: "h5", quantity: 2, isPartial: false),
        ])
        #expect(result.waitlist.entries.map(\.householdId) == ["h6"])
        #expect(result.shares.first { $0.householdId == "h4" }?.quantity == 3)
        #expect(result.shares.first { $0.householdId == "h5" }?.updatedAt == Self.t0)
        #expect(result.order.committedShares == 40)
        #expect(result.order.committedHouseholds == 5)
        #expect(result.order == (try TierEngine.recalculated(Self.order(committed: 40, status: .reached), offer: Self.offer, shares: result.shares)))
    }

    @Test func headIsPartiallyServedAndKeepsItsPlace() throws {
        // h3 annule : 8 parts libres ; h4 en veut 10.
        let shares = [Self.share("h1", 20), Self.share("h2", 12), Self.share("h3", 0)]
        let waitlist = Waitlist(entries: [Self.entry("h4", 10, minutes: 0), Self.entry("h5", 1, minutes: 1)])
        let result = try waitlist.promoting(order: Self.order(committed: 40, status: .reached), offer: Self.offer, shares: shares, now: Self.t0)

        #expect(result.promoted == [Waitlist.Promotion(householdId: "h4", quantity: 8, isPartial: true)])
        #expect(result.waitlist.entries == [Self.entry("h4", 2, minutes: 0), Self.entry("h5", 1, minutes: 1)])
        #expect(result.order.committedShares == 40)
        #expect(Waitlist.isFull(offer: Self.offer, shares: result.shares))
    }

    @Test func promotionAddsToAnExistingShare() throws {
        let shares = [Self.share("h1", 20), Self.share("h2", 10), Self.share("h3", 8)]
        let waitlist = Waitlist(entries: [Self.entry("h3", 2, minutes: 0)])
        let result = try waitlist.promoting(order: Self.order(committed: 40, status: .reached), offer: Self.offer, shares: shares, now: Self.t0)

        #expect(result.shares.count == 3)
        #expect(result.shares.first { $0.householdId == "h3" }?.quantity == 10)
        #expect(result.waitlist.isEmpty)
    }

    @Test func noFreeSharesMeansNoPromotion() throws {
        let waitlist = Waitlist(entries: [Self.entry("h4", 1, minutes: 0)])
        let result = try waitlist.promoting(order: Self.order(committed: 40, status: .reached), offer: Self.offer, shares: Self.fullShares)
        #expect(result.promoted.isEmpty)
        #expect(result.waitlist == waitlist)
        #expect(result.shares == Self.fullShares)
    }

    @Test(arguments: [GroupOrder.Status.closed, .cancelled, .delivered])
    func closedOrderNeverPromotes(status: GroupOrder.Status) throws {
        let shares = [Self.share("h1", 20)]
        let order = Self.order(committed: 20, status: status)
        let waitlist = Waitlist(entries: [Self.entry("h4", 3, minutes: 0)])
        let result = try waitlist.promoting(order: order, offer: Self.offer, shares: shares)
        #expect(result.promoted.isEmpty)
        #expect(result.waitlist == waitlist)
        #expect(result.shares == shares)
        #expect(result.order == order)
    }

    @Test func promotionCanLiftTheOrderToANewTier() throws {
        // Des ménages ont baissé leurs parts : 25 engagées, 15 libres, la liste en attend 6.
        let shares = [Self.share("h1", 15), Self.share("h2", 10)]
        let waitlist = Waitlist(entries: [Self.entry("h4", 6, minutes: 0)])
        let order = try TierEngine.recalculated(Self.order(), offer: Self.offer, shares: shares)
        let result = try waitlist.promoting(order: order, offer: Self.offer, shares: shares)
        #expect(result.order.committedShares == 31)
        #expect(result.order.currentTierIndex == 2)
        #expect(TierEngine.crossedNewTier(from: order, to: result.order))
    }
}
