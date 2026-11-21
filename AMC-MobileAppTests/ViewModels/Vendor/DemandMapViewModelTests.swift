import Foundation
import Testing
@testable import AMC_MobileApp

/// V3 Carte de la demande (T-022).
@MainActor
struct DemandMapViewModelTests {
    private typealias ID = FakeData.ID

    private let hochelagaApples = VendorTestData.order(
        id: "order-hochelaga-pommes", group: ID.hochelaga, offer: ID.appleOffer, shares: 7, households: 4, tierIndex: 0
    )
    private let saintMichelRice = VendorTestData.order(
        id: "order-saint-michel-riz", group: ID.saintMichel, offer: ID.riceOffer, shares: 5, households: 3, tierIndex: nil
    )

    @Test func aggregatesByNeighborhoodByDefault() async throws {
        let model = DemandMapViewModel(repositories: .fake(behavior: .instant), vendorId: ID.fermeRive)
        #expect(model.state == .idle)
        await model.load()
        let points = try #require(model.state.value)

        #expect(points.count == 1)
        let point = points[0]
        #expect(point.id == "Saint-Michel")
        #expect(point.grouping == .neighborhood)
        #expect(point.geohash == "f25dv")
        #expect(point.groupIds == [ID.saintMichel])
        #expect(point.committedShares == 19)
        #expect(point.committedHouseholds == 11)
        #expect(point.householdCount == 12)
        #expect(point.intensity == 1)
        #expect(point.isHighDemand)
        #expect(point.products.map(\.name) == ["Pommes de terre jaunes"])
        #expect(point.products.first?.committedShares == 19)
        #expect(model.totalCommittedShares == 19)
    }

    @Test func switchesGroupingWithoutReloading() async throws {
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(adding: [hochelagaApples]), vendorId: ID.fermeRive)
        await model.load()

        #expect(model.points.map(\.id) == ["Saint-Michel", "Hochelaga"])
        #expect(model.points.map(\.committedShares) == [19, 7])
        #expect(model.points[1].intensity == 7.0 / 19.0)
        #expect(!model.points[1].isHighDemand)

        model.grouping = .group
        #expect(model.points.map(\.id) == [ID.saintMichel, ID.hochelaga])
        #expect(model.points.map(\.label) == ["Voisins de Saint-Michel", "Hochelaga solidaire"])

        model.grouping = .geohash
        #expect(model.points.map(\.id) == ["f25d", "f25e"])
        #expect(model.points.map(\.geohash) == ["f25dv", "f25ej"])

        model.geohashPrecision = 2
        #expect(model.points.map(\.id) == ["f2"])
        #expect(model.points.first?.committedShares == 26)
        #expect(model.points.first?.householdCount == 12 + 27)
        #expect(model.points.first?.products.map(\.productId) == [ID.potatoes, ID.apples])
    }

    @Test func filtersByProductAndSelectsAPoint() async {
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(adding: [hochelagaApples]), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.availableProducts.map(\.productId) == [ID.apples, ID.potatoes])

        model.productFilter = ID.apples
        #expect(model.points.map(\.id) == ["Hochelaga"])
        #expect(model.points.first?.intensity == 1)

        model.selectedPointID = "Hochelaga"
        #expect(model.selectedPoint?.committedShares == 7)

        model.productFilter = "product-inconnu"
        #expect(model.state == .empty)
        #expect(model.selectedPoint == nil)
    }

    @Test func scopeKeepsOnlyTheVendorsOffers() async {
        let repos = VendorTestData.repositories(adding: [hochelagaApples, saintMichelRice])
        let model = DemandMapViewModel(repositories: repos, vendorId: ID.moulinsDuNord)
        await model.load()
        #expect(model.totalCommittedShares == 31)

        model.scope = .myOffers
        #expect(model.points.map(\.id) == ["Saint-Michel"])
        #expect(model.points.first?.committedShares == 5)
        #expect(model.points.first?.products.map(\.name) == ["Riz basmati"])
        #expect(model.availableProducts.map(\.productId) == [ID.rice])
    }

    @Test func countsGroupHouseholdsOnceAcrossOrders() async {
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(adding: [saintMichelRice]), vendorId: ID.fermeRive)
        await model.load()
        let point = model.points.first
        #expect(model.points.count == 1)
        #expect(point?.committedShares == 24)
        #expect(point?.committedHouseholds == 14)
        #expect(point?.householdCount == 12)
        #expect(point?.products.map(\.committedShares) == [19, 5])
    }

    @Test func ignoresClosedOrders() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        data.groupOrders.append(VendorTestData.order(
            id: "order-livree", group: ID.hochelaga, offer: ID.appleOffer, shares: 9, households: 3, tierIndex: 0,
            status: .delivered
        ))
        let model = DemandMapViewModel(repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func offlineFails() async {
        let model = DemandMapViewModel(repositories: .fake(behavior: .failing(.offline)), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.state == .failed(.offline))
        #expect(model.points.isEmpty)
    }
}
