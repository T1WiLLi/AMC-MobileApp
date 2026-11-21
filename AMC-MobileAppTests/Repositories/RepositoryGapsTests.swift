import Foundation
import Testing
@testable import AMC_MobileApp

/// T-033 : requêtes ajoutées aux dépôts (groupes d'un ménage, commandes d'un lot, ouverture d'une commande).
struct RepositoryGapsTests {
    private typealias ID = FakeData.ID

    @Test func householdGroupsIncludePrivateGroups() async throws {
        let privateGroup = NeighborhoodGroup(
            id: "group-prive", name: "Immeuble Jarry", neighborhood: "Saint-Michel", centerGeohash: "f25dv",
            radiusMeters: 200, coordinatorIds: [], householdCount: 1, isPublic: false, inviteCode: "IJ-1"
        )
        let member = GroupMember(householdId: ID.aminaHousehold, role: .member, joinedAt: .now)
        let repo = FakeGroupRepository(
            groups: FakeData.montreal.groups + [privateGroup],
            members: FakeData.montreal.members.merging([privateGroup.id: [member]]) { $0 + $1 }
        )

        let groups = try await repo.groups(ofHousehold: ID.aminaHousehold)
        #expect(Set(groups.map(\.id)) == [privateGroup.id, ID.saintMichel])
        #expect(groups.map(\.name) == groups.map(\.name).sorted())
        #expect(groups.contains { !$0.isPublic })
        #expect(try await repo.groups(ofHousehold: "household-inconnu").isEmpty)
    }

    @Test func householdGroupsFollowJoinAndLeave() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groups.join(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        #expect(try await repos.groups.groups(ofHousehold: ID.aminaHousehold).map(\.id).contains(ID.hochelaga))
        try await repos.groups.leave(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        #expect(!(try await repos.groups.groups(ofHousehold: ID.aminaHousehold).map(\.id).contains(ID.hochelaga)))
    }

    @Test func groupOrdersOfOfferListsEveryGroup() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let potatoOrders = try await repos.groupOrders.groupOrders(ofOffer: ID.potatoOffer)
        #expect(potatoOrders.map(\.id) == [ID.potatoOrder])

        let hochelagaOrder = try await repos.groupOrders.openGroupOrder(groupId: ID.hochelaga, offerId: ID.potatoOffer)
        let after = try await repos.groupOrders.groupOrders(ofOffer: ID.potatoOffer)
        #expect(Set(after.map(\.id)) == [ID.potatoOrder, hochelagaOrder.id])
        #expect(try await repos.groupOrders.groupOrders(ofOffer: ID.riceOffer).isEmpty)
    }

    @Test func openGroupOrderReturnsTheExistingOpenOrder() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let order = try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: ID.potatoOffer)
        #expect(order.id == ID.potatoOrder)
        #expect(order.committedShares == 19)
    }

    @Test func openGroupOrderCreatesAnEmptyOrderThatAcceptsShares() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let order = try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: ID.riceOffer)
        #expect(order.groupId == ID.saintMichel)
        #expect(order.offerId == ID.riceOffer)
        #expect(order.status == .open)
        #expect(order.committedShares == 0)
        #expect(order.currentTierIndex == nil)
        #expect(try await repos.groupOrders.shares(ofGroupOrder: order.id).isEmpty)

        // Appel répété : même commande, pas de doublon.
        let again = try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: ID.riceOffer)
        #expect(again.id == order.id)
        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).count == 2)

        // Amina peut maintenant réserver du riz.
        let updated = try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: order.id)
        #expect(updated.committedShares == 2)
        #expect(updated.committedHouseholds == 1)
    }

    @Test func openGroupOrderRefusesUnknownOrClosedOffers() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        await #expect(throws: AppError.notFound) {
            try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: "offer-inconnu")
        }

        var closed = FakeData.montreal.offers.first { $0.id == ID.riceOffer }!
        closed.status = .closed
        var expired = FakeData.montreal.offers.first { $0.id == ID.appleOffer }!
        expired.deadline = .now.addingTimeInterval(-60)
        let repo = FakeGroupOrderRepository(offers: [closed, expired])
        await #expect(throws: AppError.orderClosed) {
            try await repo.openGroupOrder(groupId: ID.saintMichel, offerId: closed.id)
        }
        await #expect(throws: AppError.orderClosed) {
            try await repo.openGroupOrder(groupId: ID.saintMichel, offerId: expired.id)
        }
    }

    @Test func openGroupOrderPropagatesTheFakeError() async {
        let repos = AppRepositories.fake(behavior: .failing(.offline))
        await #expect(throws: AppError.offline) {
            try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: ID.riceOffer)
        }
    }

    @Test func setShareStampsUpdatedAt() async throws {
        let fixed = Date(timeIntervalSince1970: 1_795_000_000)
        let data = FakeData.montreal
        let repo = FakeGroupOrderRepository(
            groupOrders: data.groupOrders, shares: data.shares, offers: data.offers, now: { fixed }
        )
        try await repo.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        var share = try await repo.shares(ofGroupOrder: ID.potatoOrder).first { $0.householdId == ID.aminaHousehold }
        #expect(share?.updatedAt == fixed)

        try await repo.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        share = try await repo.shares(ofGroupOrder: ID.potatoOrder).first { $0.householdId == ID.aminaHousehold }
        #expect(share?.quantity == 2)
        #expect(share?.updatedAt == fixed)
    }

    @Test func shareWithoutUpdatedAtStillDecodes() throws {
        let json = Data("""
        {"householdId":"h1","quantity":2,"isPaid":false,"suspendedAmountCents":0,"subsidyCents":0,"isPickedUp":false}
        """.utf8)
        let share = try JSONDecoder().decode(Share.self, from: json)
        #expect(share.quantity == 2)
        #expect(share.updatedAt == nil)
    }
}
