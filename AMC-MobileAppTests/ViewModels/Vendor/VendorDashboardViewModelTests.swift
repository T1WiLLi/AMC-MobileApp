import Foundation
import Testing
@testable import AMC_MobileApp

/// V1 Tableau de bord vendeur (T-022).
@MainActor
struct VendorDashboardViewModelTests {
    private typealias ID = FakeData.ID

    @Test func loadsActiveOffersOfTheVendor() async throws {
        let model = VendorDashboardViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive)
        #expect(model.state == .idle)
        await model.load()
        let dashboard = try #require(model.state.value)

        #expect(dashboard.offers.map(\.id) == [ID.potatoOffer, ID.appleOffer])
        let potato = dashboard.offers[0]
        #expect(potato.title == "Pommes de terre jaunes")
        #expect(potato.committedShares == 19)
        #expect(potato.totalShares == 40)
        #expect(potato.fillFraction == 19.0 / 40.0)
        #expect(potato.committedHouseholds == 11)
        #expect(potato.linkedOrders.map(\.id) == [ID.potatoOrder])
        #expect(potato.linkedOrders.first?.group.id == ID.saintMichel)
        #expect(potato.bestTierIndex == 0)
        #expect(potato.bestTierNumber == 1)
        #expect(potato.bestTier == PriceTier(minShares: 10, priceCents: 1_150))
        #expect(potato.projectedRevenueCents == 19 * 1_150)

        let apple = dashboard.offers[1]
        #expect(apple.committedShares == 0)
        #expect(apple.bestTierIndex == nil)
        #expect(apple.projectedRevenueCents == 0)

        #expect(dashboard.totalCommittedShares == 19)
        #expect(dashboard.totalShares == 65)
        #expect(dashboard.committedHouseholds == 11)
        #expect(dashboard.projectedRevenueCents == 19 * 1_150)
        #expect(dashboard.closingSoon.map(\.id) == [ID.potatoOffer])
        #expect(dashboard.highlight?.groupName == "Voisins de Saint-Michel")
        #expect(dashboard.highlight?.tierNumber == 1)
    }

    @Test func sumsRevenuePerOrderAndShowsTheBestTier() async throws {
        let hochelagaOrder = VendorTestData.order(
            id: "order-hochelaga-patates", group: ID.hochelaga, offer: ID.potatoOffer,
            shares: 20, households: 9, tierIndex: 1, status: .reached
        )
        let model = VendorDashboardViewModel(
            repositories: VendorTestData.repositories(adding: [hochelagaOrder]), vendorId: ID.fermeRive
        )
        await model.load()
        let dashboard = try #require(model.state.value)
        let potato = try #require(dashboard.offers.first { $0.id == ID.potatoOffer })

        #expect(potato.committedShares == 39)
        #expect(potato.committedHouseholds == 20)
        #expect(potato.linkedOrders.map(\.id) == ["order-hochelaga-patates", ID.potatoOrder])
        #expect(potato.bestTierIndex == 1)
        // Chaque commande paie le prix de son propre palier.
        #expect(potato.projectedRevenueCents == 19 * 1_150 + 20 * 990)
        #expect(dashboard.highlight?.groupName == "Hochelaga solidaire")
        #expect(dashboard.highlight?.tierNumber == 2)
    }

    @Test func ignoresInactiveOffersAndCancelledOrders() async throws {
        var data = VendorTestData.data(adding: [
            VendorTestData.order(id: "order-annulee", group: ID.hochelaga, offer: ID.potatoOffer,
                                 shares: 15, households: 5, tierIndex: 0, status: .cancelled),
        ])
        let appleIndex = try #require(data.offers.firstIndex { $0.id == ID.appleOffer })
        data.offers[appleIndex].status = .draft
        let model = VendorDashboardViewModel(repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive)
        await model.load()
        let dashboard = try #require(model.state.value)

        #expect(dashboard.offers.map(\.id) == [ID.potatoOffer])
        #expect(dashboard.offers[0].committedShares == 19)
    }

    @Test func closingSoonFollowsTheInterval() async throws {
        let model = VendorDashboardViewModel(
            repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, closingSoonInterval: 7 * 86_400
        )
        await model.load()
        #expect(model.state.value?.closingSoon.map(\.id) == [ID.potatoOffer, ID.appleOffer])
    }

    @Test func vendorWithoutActiveOffersIsEmpty() async {
        let model = VendorDashboardViewModel(repositories: .fake(behavior: .instant), vendorId: "vendor-inconnu")
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func offlineFails() async {
        let model = VendorDashboardViewModel(repositories: .fake(behavior: .failing(.offline)), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.state == .failed(.offline))
    }

    @Test func refreshPicksUpNewShares() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let model = VendorDashboardViewModel(repositories: repos, vendorId: ID.fermeRive)
        await model.load()
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        await model.refresh()
        let potato = try #require(model.state.value?.offers.first)
        #expect(potato.committedShares == 20)
        #expect(potato.bestTierIndex == 1)
        #expect(potato.projectedRevenueCents == 20 * 990)
    }

    @Test func countsOrdersOfPrivateGroups() async throws {
        let privateGroup = NeighborhoodGroup(
            id: "group-prive", name: "Immeuble Jarry", neighborhood: "Saint-Michel", centerGeohash: "f25dv",
            radiusMeters: 200, coordinatorIds: [], householdCount: 4, isPublic: false, inviteCode: "IJ-1"
        )
        var data = VendorTestData.data(adding: [
            VendorTestData.order(id: "order-prive", group: privateGroup.id, offer: ID.appleOffer,
                                 shares: 3, households: 2, tierIndex: nil)
        ])
        data.groups.append(privateGroup)
        let model = VendorDashboardViewModel(repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive)
        await model.load()
        let apple = try #require(model.state.value?.offers.first { $0.id == ID.appleOffer })
        #expect(apple.linkedOrders.map(\.id) == ["order-prive"])
        #expect(apple.linkedOrders.first?.group.isPublic == false)
        #expect(apple.committedShares == 3)
        #expect(apple.committedHouseholds == 2)
    }
}
