import Foundation
import Testing
@testable import AMC_MobileApp

/// Dépôts fake (B-016) : comportement attendu par les ViewModels.
struct FakeRepositoryTests {
    private typealias ID = FakeData.ID

    private func repositories(_ behavior: FakeBehavior = .instant) -> AppRepositories {
        .fake(behavior: behavior)
    }

    @Test func fakeDataIsConsistent() {
        let data = FakeData.montreal
        for order in data.groupOrders {
            let shares = data.shares[order.id, default: []]
            #expect(order.committedShares == shares.reduce(0) { $0 + $1.quantity })
            #expect(order.committedHouseholds == shares.count)
            #expect(data.offers.contains { $0.id == order.offerId })
        }
        for offer in data.offers {
            #expect(data.products.contains { $0.id == offer.productId && $0.vendorId == offer.vendorId })
        }
    }

    @Test func aminaShareCrossesTheTier() async throws {
        let repos = repositories()
        let before = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        #expect(before.currentTierIndex == 0)

        let after = try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        #expect(after.committedShares == 20)
        #expect(after.committedHouseholds == before.committedHouseholds + 1)
        #expect(after.currentTierIndex == 1)
    }

    @Test func changingThenRemovingAShareRecomputesTotals() async throws {
        let repos = repositories()
        try await repos.groupOrders.setShare(quantity: 3, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let changed = try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        #expect(changed.committedShares == 20)
        let removed = try await repos.groupOrders.setShare(quantity: 0, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        #expect(removed.committedShares == 19)
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(!shares.contains { $0.householdId == ID.aminaHousehold })
    }

    @Test func refusesMoreSharesThanTheOfferHas() async {
        let repos = repositories()
        await #expect(throws: AppError.invalidInput("Il ne reste que 21 parts dans ce lot.")) {
            try await repos.groupOrders.setShare(quantity: 22, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        }
    }

    @Test func refusesSharesOnAClosedOrder() async {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        await #expect(throws: AppError.orderClosed) {
            try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        }
    }

    @Test func observerReceivesCurrentStateThenUpdates() async throws {
        let repos = repositories()
        let stream = await repos.groupOrders.observeGroupOrder(id: ID.potatoOrder)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first?.committedShares == 19)

        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let second = try await iterator.next()
        #expect(second?.committedShares == 21)
    }

    @Test func observingAMissingOrderFails() async {
        let stream = await repositories().groupOrders.observeGroupOrder(id: "nope")
        await #expect(throws: AppError.notFound) {
            for try await _ in stream {}
        }
    }

    @Test func joiningAGroupIsIdempotent() async throws {
        let repos = repositories()
        let before = try await repos.groups.group(id: ID.hochelaga)
        try await repos.groups.join(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        try await repos.groups.join(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        let after = try await repos.groups.group(id: ID.hochelaga)
        #expect(after.householdCount == before.householdCount + 1)
        try await repos.groups.leave(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        #expect(try await repos.groups.group(id: ID.hochelaga).householdCount == before.householdCount)
    }

    @Test func offerFeedIsFilteredByZone() async throws {
        let repos = repositories()
        let saintMichel = try await repos.offers.activeOffers(inZone: "f25d").map(\.id)
        // T-180 : le lot de démo Ferme Lafleur (zone f25dt, Parc-Extension) est aussi dans la zone large f25d.
        #expect(Set(saintMichel) == [ID.potatoOffer, ID.riceOffer, ID.lafleurRiceOffer])
        let all = try await repos.offers.activeOffers(inZone: nil)
        #expect(all.count == 4)
    }

    /// T-087 : les zones des lots sont des préfixes geohash ; un lot est visible dans une zone
    /// si une de ses zones est un préfixe de la zone demandée, ou l'inverse.
    @Test func offerFeedMatchesZonesByGeohashPrefix() async throws {
        let repos = repositories()
        // Geohash d'un groupe (plus long que les zones des lots).
        let saintMichel = try await repos.offers.activeOffers(inZone: "f25dv").map(\.id)
        #expect(Set(saintMichel) == [ID.potatoOffer, ID.riceOffer])
        // Zone plus large que celles des lots : tous les lots dedans.
        let wide = try await repos.offers.activeOffers(inZone: "f25").map(\.id)
        #expect(Set(wide) == [ID.potatoOffer, ID.riceOffer, ID.appleOffer, ID.lafleurRiceOffer])
        // Zones sans préfixe commun avec le lot.
        #expect(try await repos.offers.activeOffers(inZone: "f25x").isEmpty)
        #expect(try await repos.offers.activeOffers(inZone: "f25ev").map(\.id).contains(ID.riceOffer) == false)
    }

    @Test func lookupsOfUnknownIdsThrowNotFound() async {
        let repos = repositories()
        await #expect(throws: AppError.notFound) { try await repos.users.user(id: "nope") }
        await #expect(throws: AppError.notFound) { try await repos.vendors.vendor(id: "nope") }
        await #expect(throws: AppError.notFound) { try await repos.pickupPoints.pickupPoint(id: "nope") }
    }

    @Test func failingBehaviorThrowsTheConfiguredError() async {
        let repos = repositories(.failing(.offline))
        await #expect(throws: AppError.offline) { try await repos.offers.activeOffers(inZone: nil) }
        await #expect(throws: AppError.offline) { try await repos.users.user(id: ID.amina) }
    }

    @Test func realisticBehaviorWaitsAtLeast300Milliseconds() async throws {
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await repositories(.realistic).vendors.vendors()
        }
        #expect(elapsed >= .milliseconds(300))
    }
}
