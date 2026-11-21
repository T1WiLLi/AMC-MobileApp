import Foundation
import Testing
@testable import AMC_MobileApp

/// Panier et historique d'une famille (T-062), sur `FakeData.montreal` et des variantes.
/// Pommes de terre à Saint-Michel : 19 parts, paliers 10 → 11,50 $, 20 → 9,90 $, 30 → 8,50 $ ; épicerie 15,99 $.
@MainActor
struct CartViewModelTests {
    private typealias ID = FakeData.ID
    private static let day: TimeInterval = 86_400

    private func share(_ householdId: String, _ quantity: Int, finalPrice: Cents? = nil) -> Share {
        Share(householdId: householdId, quantity: quantity, finalPriceCents: finalPrice, isPaid: false,
              suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
    }

    private func order(_ id: String, group: String, offer: String, status: GroupOrder.Status,
                       committed: Int, tierIndex: Int? = nil) -> GroupOrder {
        GroupOrder(id: id, groupId: group, offerId: offer, status: status, currentTierIndex: tierIndex,
                   committedShares: committed, committedHouseholds: 1, pickupPointId: nil, pickupSlots: [])
    }

    /// Amina membre aussi de Hochelaga, avec 4 caisses de pommes là-bas (palier 5 non atteint : prix de départ).
    private func twoGroupsData() -> FakeData {
        var data = FakeData.montreal
        data.members[ID.hochelaga] = [GroupMember(householdId: ID.aminaHousehold, role: .member, joinedAt: .now)]
        data.groupOrders.append(order("order-hochelaga-pommes", group: ID.hochelaga, offer: ID.appleOffer,
                                      status: .open, committed: 4))
        data.shares["order-hochelaga-pommes"] = [share(ID.aminaHousehold, 4)]
        return data
    }

    // MARK: Panier

    @Test func cartListsLinesAcrossGroupsWithTotals() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: twoGroupsData())
        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = CartViewModel(repositories: repos, householdId: ID.aminaHousehold)
        await viewModel.load()

        let content = try #require(viewModel.state.value)
        // Pommes de terre (date limite à 2 jours) avant les pommes (6 jours).
        #expect(content.lines.map(\.offer.id) == [ID.potatoOffer, ID.appleOffer])
        let potatoes = content.lines[0]
        #expect(potatoes.productName == "Pommes de terre jaunes")
        #expect(potatoes.groupName == "Voisins de Saint-Michel")
        #expect(potatoes.quantity == 2)
        #expect(potatoes.unitPriceCents == 990)
        #expect(potatoes.lineTotalCents == 1_980)
        #expect(potatoes.savingsCents == 2 * (1_599 - 990))
        #expect(potatoes.canEdit)
        #expect(potatoes.timeRemaining > 0)

        let apples = content.lines[1]
        #expect(apples.groupName == "Hochelaga solidaire")
        #expect(apples.unitPriceCents == 1_100)
        #expect(content.estimatedTotalCents == 1_980 + 4 * 1_100)
        #expect(content.totalSavingsCents == 2 * (1_599 - 990) + 4 * (1_499 - 1_100))
        #expect(content.shareCount == 6)
    }

    @Test func cartIsEmptyWithoutShares() async {
        let viewModel = CartViewModel(repositories: .fake(behavior: .instant), householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test func cartFailsOffline() async {
        let viewModel = CartViewModel(repositories: .fake(behavior: .failing(.offline)), householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    @Test func updatingQuantityAcrossATierChangesThePrice() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = CartViewModel(repositories: repos, householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.lines.first?.unitPriceCents == 990)

        // 19 + 11 = 30 parts : palier 3 à 8,50 $.
        await viewModel.updateQuantity(ID.potatoOrder, to: 11)
        let line = try #require(viewModel.lines.first)
        #expect(viewModel.actionError == nil)
        #expect(line.quantity == 11)
        #expect(line.groupOrder.committedShares == 30)
        #expect(line.unitPriceCents == 850)
        #expect(line.lineTotalCents == 11 * 850)
    }

    @Test func cancelRemovesTheLine() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = CartViewModel(repositories: repos, householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.lines.count == 1)

        await viewModel.cancel(ID.potatoOrder)
        #expect(viewModel.actionError == nil)
        #expect(viewModel.state == .empty)
        let order = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        #expect(order.committedShares == 19)
    }

    @Test func editingAfterTheDeadlineIsRefused() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let afterDeadline = Date.now.addingTimeInterval(3 * Self.day)
        let viewModel = CartViewModel(repositories: repos, householdId: ID.aminaHousehold, now: { afterDeadline })
        await viewModel.load()
        let line = try #require(viewModel.lines.first)
        #expect(!line.canEdit)
        #expect(line.timeRemaining == 0)

        await viewModel.updateQuantity(line.id, to: 3)
        #expect(viewModel.actionError == .orderClosed)
        await viewModel.cancel(line.id)
        #expect(viewModel.lines.first?.quantity == 2)
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(shares.first { $0.householdId == ID.aminaHousehold }?.quantity == 2)
    }

    @Test func cartSkipsClosedOrders() async {
        var data = twoGroupsData()
        data.groupOrders = data.groupOrders.map { order in
            var order = order
            if order.id == "order-hochelaga-pommes" { order.status = .closed }
            return order
        }
        let viewModel = CartViewModel(repositories: .fake(behavior: .instant, data: data), householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    // MARK: Historique

    /// Trois commandes terminées d'Amina (livrée il y a 20 j, confirmée il y a 5 j, annulée il y a 10 j)
    /// et une commande confirmée sans part d'Amina.
    private func historyData() -> FakeData {
        var data = FakeData.montreal
        let base = data.offers.first { $0.id == ID.potatoOffer }!
        func pastOffer(_ id: String, daysAgo: Double) -> Offer {
            var offer = base
            offer.id = id
            offer.deadline = Date.now.addingTimeInterval(-daysAgo * Self.day)
            offer.status = .closed
            return offer
        }
        data.offers += [pastOffer("offer-old-delivered", daysAgo: 20), pastOffer("offer-old-closed", daysAgo: 5),
                        pastOffer("offer-old-cancelled", daysAgo: 10), pastOffer("offer-old-other", daysAgo: 1)]
        data.groupOrders += [
            order("order-delivered", group: ID.saintMichel, offer: "offer-old-delivered", status: .delivered,
                  committed: 31, tierIndex: 2),
            order("order-closed", group: ID.saintMichel, offer: "offer-old-closed", status: .closed,
                  committed: 22, tierIndex: 1),
            order("order-cancelled", group: ID.saintMichel, offer: "offer-old-cancelled", status: .cancelled,
                  committed: 4),
            order("order-other", group: ID.saintMichel, offer: "offer-old-other", status: .closed,
                  committed: 12, tierIndex: 0),
        ]
        data.shares["order-delivered"] = [share(ID.aminaHousehold, 2)]
        data.shares["order-closed"] = [share(ID.aminaHousehold, 3, finalPrice: 990)]
        data.shares["order-cancelled"] = [share(ID.aminaHousehold, 1)]
        data.shares["order-other"] = [share("household-voisin-1", 2, finalPrice: 1_150)]
        return data
    }

    @Test func historyListsFinishedOrdersNewestFirst() async throws {
        let viewModel = OrderHistoryViewModel(repositories: .fake(behavior: .instant, data: historyData()),
                                              householdId: ID.aminaHousehold)
        await viewModel.load()
        let entries = try #require(viewModel.state.value)
        #expect(entries.map(\.id) == ["order-closed", "order-cancelled", "order-delivered"])
        #expect(entries.map(\.statusLabel) == ["Confirmée", "Annulée", "Livrée"])

        let closed = entries[0]
        #expect(closed.finalPriceCents == 990)
        #expect(closed.totalCents == 2_970)
        #expect(closed.savingsCents == 3 * (1_599 - 990))

        let cancelled = entries[1]
        #expect(cancelled.finalPriceCents == nil)
        #expect(cancelled.totalCents == 0)
        #expect(cancelled.savingsCents == 0)

        // Sans prix figé sur la part : prix du palier atteint (3e palier, 8,50 $).
        let delivered = entries[2]
        #expect(delivered.finalPriceCents == 850)
        #expect(delivered.totalCents == 1_700)
        #expect(viewModel.totalSavingsCents == 3 * (1_599 - 990) + 2 * (1_599 - 850))
    }

    @Test func historyIsEmptyOnTheDemoData() async {
        let viewModel = OrderHistoryViewModel(repositories: .fake(behavior: .instant), householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test func historyFailsOffline() async {
        let viewModel = OrderHistoryViewModel(repositories: .fake(behavior: .failing(.offline)),
                                              householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }
}
