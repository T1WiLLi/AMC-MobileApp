import Foundation
import Testing
@testable import AMC_MobileApp

/// Onglet Revenus du portail Vendeur (T-037).
@MainActor
struct VendorRevenueModelTests {
    private typealias ID = FakeData.ID

    private func loadedRevenue(_ data: FakeData = .montreal, vendorId: String = ID.fermeRive) async throws -> VendorRevenue {
        let model = VendorRevenueModel(repositories: .fake(behavior: .instant, data: data), vendorId: vendorId)
        await model.load()
        return try #require(model.state.value)
    }

    @Test func totalMatchesTheSaintMichelOrder() async throws {
        let revenue = try await loadedRevenue()
        // 19 parts au palier 1 (11,50 $).
        #expect(revenue.totalCents == 19 * 1_150)
        #expect(revenue.familiesServed == 11)
        #expect(revenue.committedShares == 19)
        #expect(revenue.totalShares == 40 + 25)
    }

    @Test func offersAreSortedByRevenue() async throws {
        let revenue = try await loadedRevenue()
        #expect(revenue.offers.map(\.id) == [ID.potatoOffer, ID.appleOffer])
        #expect(revenue.offers.last?.revenueCents == 0)
        #expect(revenue.topOffer?.id == ID.potatoOffer)
    }

    @Test func neighborhoodsAggregateEveryGroupOrder() async throws {
        let revenue = try await loadedRevenue(.vendorRevenueDemo)
        let byName = Dictionary(uniqueKeysWithValues: revenue.neighborhoods.map { ($0.neighborhood, $0) })
        #expect(byName["Parc-Extension"]?.revenueCents == 16 * 950)
        #expect(byName["Saint-Michel"]?.revenueCents == 19 * 1_150)
        #expect(byName["Hochelaga"]?.revenueCents == 14 * 1_150)
        #expect(byName["Villeray"]?.households == 6)
        #expect(revenue.neighborhoods.first?.neighborhood == "Saint-Michel")
        #expect(revenue.neighborhoods.reduce(0) { $0 + $1.revenueCents } == revenue.totalCents)
    }

    @Test func deliveriesCarryThePickupPoint() async throws {
        let revenue = try await loadedRevenue(.vendorRevenueDemo)
        // Seules les pommes de terre ferment dans les 72 h.
        #expect(Set(revenue.deliveries.map(\.offerTitle)) == ["Pommes de terre jaunes"])
        let saintMichel = try #require(revenue.deliveries.first { $0.id == ID.potatoOrder })
        #expect(saintMichel.pickupPointName == "Chez Amina, rue Jarry")
        #expect(saintMichel.pickupStart != nil)
        #expect(revenue.deliveries.first?.shares == 19)
    }

    @Test func closingOfferWithoutOrderStillShows() async throws {
        let model = VendorRevenueModel(
            repositories: .fake(behavior: .instant), vendorId: ID.fermeRive, closingSoonInterval: 7 * 86_400
        )
        await model.load()
        let revenue = try #require(model.state.value)
        let apples = try #require(revenue.deliveries.first { $0.id == ID.appleOffer })
        #expect(apples.groupName == nil)
        #expect(apples.pickupPointName == nil)
    }

    @Test func unknownVendorIsEmpty() async {
        let model = VendorRevenueModel(repositories: .fake(behavior: .instant), vendorId: "vendor-inconnu")
        await model.load()
        guard case .empty = model.state else {
            Issue.record("État attendu : .empty")
            return
        }
    }

    @Test func offlineFails() async {
        let model = VendorRevenueModel(repositories: .fake(behavior: .failing(.offline)), vendorId: ID.fermeRive)
        await model.load()
        #expect(model.state.error == .offline)
    }
}
