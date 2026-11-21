import Foundation
import Testing
@testable import AMC_MobileApp

/// Page publique d'un vendeur côté familles (T-097, R-009).
@MainActor
struct PublicVendorViewModelTests {
    private typealias ID = FakeData.ID

    /// Instant fixe : les dates limites des lots de test sont relatives à lui.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func offer(_ id: String, product: String, deadlineInDays: Double, status: Offer.Status) -> Offer {
        Offer(id: id, vendorId: ID.fermeRive, productId: product, totalShares: 20, shareUnit: "1 caisse",
              tiers: [PriceTier(minShares: 5, priceCents: 1_200), PriceTier(minShares: 10, priceCents: 900)],
              minimumSharesToLaunch: 5, deadline: now.addingTimeInterval(deadlineInDays * day),
              zones: ["f25d"], status: status)
    }

    /// Montréal, avec pour la Ferme Bio-Rive : des œufs au catalogue, des lots dans tous les états,
    /// et un vendeur sans rien.
    private func data() -> FakeData {
        var data = FakeData.montreal
        data.products.append(
            Product(id: "product-oeufs", vendorId: ID.fermeRive, name: "Œufs bio", category: .eggs,
                    unit: "douzaine", origin: "Mirabel, QC", tags: [.organic], photoURL: nil,
                    referenceGroceryPriceCents: 699)
        )
        data.offers = [
            offer("offer-late", product: ID.apples, deadlineInDays: 5, status: .active),
            offer("offer-soon", product: ID.potatoes, deadlineInDays: 1, status: .active),
            offer("offer-eggs", product: "product-oeufs", deadlineInDays: 3, status: .active),
            offer("offer-expired", product: ID.potatoes, deadlineInDays: -1, status: .active),
            offer("offer-closed", product: ID.apples, deadlineInDays: 2, status: .closed),
            offer("offer-draft", product: ID.apples, deadlineInDays: 2, status: .draft),
            offer("offer-cancelled", product: ID.apples, deadlineInDays: 2, status: .cancelled),
        ]
        data.vendors.append(
            Vendor(id: "vendor-nouveau", legalName: "Boulangerie Nouvelle", kind: .bakery,
                   description: "Pains au levain cuits chaque matin à Rosemont.", photoURLs: [],
                   servedZones: ["zzzz"], averageRating: nil, isVerified: false)
        )
        return data
    }

    private func model(vendorId: String = ID.fermeRive, behavior: FakeBehavior = .instant) -> PublicVendorViewModel {
        PublicVendorViewModel(
            vendorId: vendorId,
            repositories: .fake(behavior: behavior, data: data()),
            now: { [now] in now }
        )
    }

    // MARK: Chargement

    @Test func startsIdleThenLoadsProfile() async throws {
        let model = model()
        #expect(model.state == .idle)
        #expect(model.catalog == .idle)
        #expect(model.openOffers == .idle)

        await model.load()

        let profile = try #require(model.state.value)
        #expect(profile.id == ID.fermeRive)
        #expect(profile.name == "Ferme Bio-Rive")
        #expect(profile.kind == .farm)
        #expect(profile.description == "Légumes biologiques cultivés à Mirabel depuis 1998.")
        #expect(profile.isVerified)
        #expect(profile.averageRating == 4.7)
        #expect(profile.coverPhotoURL == nil)
    }

    @Test func namesServedZonesFromGroupsOrFallsBackToCode() async throws {
        let model = model()
        await model.load()
        let zones = try #require(model.state.value?.zones)
        // f25d → Saint-Michel (groupe f25dv), f25e → Hochelaga (groupe f25ej).
        #expect(zones.map(\.id) == ["f25d", "f25e"])
        #expect(zones.map(\.label) == ["Saint-Michel", "Hochelaga"])

        let unknown = self.model(vendorId: "vendor-nouveau")
        await unknown.load()
        #expect(unknown.state.value?.zones.map(\.label) == ["zzzz"])
    }

    @Test func groupsCatalogByCategoryInCategoryOrder() async throws {
        let model = model()
        await model.load()
        let sections = try #require(model.catalog.value)

        // Ordre de `Product.Category.allCases` : … eggs, …, produce.
        #expect(sections.map(\.category) == [.eggs, .produce])
        #expect(sections.map(\.title) == ["Œufs", "Fruits et légumes"])
        #expect(sections[1].products.map(\.name) == ["Pommes Cortland", "Pommes de terre jaunes"])
        #expect(sections.flatMap(\.products).allSatisfy { $0.vendorId == ID.fermeRive })
    }

    @Test func keepsOnlyActiveFutureOffersSortedByDeadline() async throws {
        let model = model()
        await model.load()
        let offers = try #require(model.openOffers.value)

        #expect(offers.map(\.id) == ["offer-soon", "offer-eggs", "offer-late"])
        #expect(offers.map(\.product.name) == ["Pommes de terre jaunes", "Œufs bio", "Pommes Cortland"])
        #expect(offers.allSatisfy { $0.offer.status == .active && $0.offer.deadline > now })
        #expect(offers.first?.route == OfferRoute(offerId: "offer-soon"))
    }

    @Test func openOfferShowsBestPriceAndSavings() async throws {
        let model = model()
        await model.load()
        let soon = try #require(model.openOffers.value?.first)
        // Meilleur palier : 9,00 $ contre 15,99 $ à l'épicerie → −44 %.
        #expect(soon.bestPriceCents == 900)
        #expect(soon.maxSavingsPercent == 44)
    }

    @Test func vendorWithoutProductsOrOffersStillShowsPage() async throws {
        let model = model(vendorId: "vendor-nouveau")
        await model.load()

        #expect(model.state.value?.name == "Boulangerie Nouvelle")
        #expect(model.catalog == .empty)
        #expect(model.openOffers == .empty)
    }

    @Test func refreshKeepsContentWhileReloading() async throws {
        let model = model()
        await model.load()
        let before = try #require(model.state.value)
        await model.refresh()
        #expect(model.state.value == before)
        #expect(model.openOffers.value?.count == 3)
    }

    // MARK: Erreurs

    @Test func unknownVendorFailsWithNotFound() async {
        let model = model(vendorId: "vendor-inconnu")
        await model.load()
        #expect(model.state == .failed(.notFound))
    }

    @Test func offlineRepositoriesFail() async {
        let model = model(behavior: .failing(.offline))
        await model.load()
        #expect(model.state == .failed(.offline))
        #expect(model.state.error?.isRetryable == true)
    }

    // MARK: Confidentialité

    @Test func exposesNoPrivateField() async throws {
        let model = model()
        await model.load()
        let profile = try #require(model.state.value)

        let labels = Set(Mirror(reflecting: profile).children.compactMap(\.label))
        #expect(labels == ["id", "name", "kind", "description", "coverPhotoURL", "zones", "averageRating", "isVerified"])

        let forbidden = ["revenue", "revenu", "email", "courriel", "phone", "telephone", "address", "adresse", "geohash"]
        let allLabels = labels
            .union(Mirror(reflecting: try #require(model.openOffers.value?.first)).children.compactMap(\.label))
            .union(Mirror(reflecting: try #require(model.catalog.value?.first)).children.compactMap(\.label))
        for label in allLabels {
            #expect(!forbidden.contains { label.lowercased().contains($0) }, "Champ privé exposé : \(label)")
        }
    }
}
