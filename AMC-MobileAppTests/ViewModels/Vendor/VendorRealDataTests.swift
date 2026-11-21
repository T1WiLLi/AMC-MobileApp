import Foundation
import Testing
@testable import AMC_MobileApp

/// T-129 : la demande et les revenus du portail Vendeur se calculent depuis les vraies données des dépôts
/// (commandes, parts, envies des familles), plus aucun jeu de démo.
@MainActor
struct VendorRealDataTests {
    private typealias ID = FakeData.ID

    // MARK: Demande : envies des familles

    @Test func wishesAddTheirOwnPointAndCountFamiliesOnce() async throws {
        let wishes = [
            VendorTestData.wish("w1", group: ID.hochelaga, household: "h1", category: .produce, quantity: 15),
            VendorTestData.wish("w2", group: ID.hochelaga, household: "h1", category: .grains, quantity: 10),
            VendorTestData.wish("w3", group: ID.hochelaga, household: "h2", category: .produce, quantity: 5),
        ]
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(wishes: wishes), vendorId: ID.fermeRive)
        await model.load()

        #expect(model.points.map(\.id) == ["Saint-Michel", "Hochelaga"])
        let hochelaga = try #require(model.points.last)
        #expect(hochelaga.committedShares == 0)
        #expect(hochelaga.wishingHouseholds == 2)
        #expect(hochelaga.interestedHouseholds == 2)
        #expect(hochelaga.wishes.map(\.category) == [.produce, .grains])
        #expect(hochelaga.wishes.first?.totalQuantity == 20)
        #expect(hochelaga.wishes.first?.householdCount == 2)
        #expect(hochelaga.geohash == "f25ej")
        // Saint-Michel : 19 parts ; Hochelaga : 2 familles → 2 / 19.
        #expect(hochelaga.intensity == 2.0 / 19.0)
        #expect(model.totalWishingHouseholds == 2)
    }

    /// B-055 : tirer pour rafraîchir garde la demande affichée (pas de retour au squelette) et libère le verrou.
    @Test func refreshKeepsTheDemandShownAndCanRunAgain() async {
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(wishes: []), vendorId: ID.fermeRive)
        await model.load()
        let before = model.points.map(\.id)
        #expect(!before.isEmpty)

        async let first: Void = model.refresh()
        async let second: Void = model.refresh() // ignoré pendant le premier
        _ = await (first, second)

        #expect(model.state.value != nil)
        #expect(model.points.map(\.id) == before)
        #expect(!model.isRefreshing)
        await model.refresh()
        #expect(model.points.map(\.id) == before)
    }

    @Test func wishesWeighOnTheSamePointAsOrders() async throws {
        let wishes = [
            VendorTestData.wish("w1", group: ID.saintMichel, household: "h1", category: .grains, quantity: 10),
            VendorTestData.wish("w2", group: ID.saintMichel, household: "h2", category: .grains, quantity: 20),
        ]
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(wishes: wishes), vendorId: ID.fermeRive)
        await model.load()

        let point = try #require(model.points.first)
        #expect(model.points.count == 1)
        #expect(point.committedShares == 19)
        #expect(point.committedHouseholds == 11)
        #expect(point.wishingHouseholds == 2)
        #expect(point.interestedHouseholds == 13)
        #expect(point.demandScore == 21)
        #expect(point.intensity == 1)
        #expect(point.wishes.first?.totalQuantity == 30)
    }

    @Test func expiredWishesAndPrivateGroupsAreIgnored() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let open = NeighborhoodGroup(id: "g-open", name: "Ouvert", neighborhood: "Villeray", centerGeohash: "f25eh",
                                     radiusMeters: 800, coordinatorIds: [], householdCount: 10, isPublic: true, inviteCode: "")
        var closed = open
        closed.id = "g-private"
        closed.isPublic = false
        let wishes = [
            VendorTestData.wish("ok", group: "g-open", household: "h1", category: .eggs, quantity: 2, unit: .dozen),
            VendorTestData.wish("expired", group: "g-open", household: "h2", category: .eggs, quantity: 2, unit: .dozen,
                                until: now.addingTimeInterval(-60)),
            VendorTestData.wish("private", group: "g-private", household: "h3", category: .eggs, quantity: 2, unit: .dozen),
            VendorTestData.wish("unknown", group: "g-inconnu", household: "h4", category: .eggs, quantity: 2, unit: .dozen),
        ]
        let records = DemandMapViewModel.wishRecords(wishes, groups: [open, closed], now: now)
        #expect(records.map(\.wish.id) == ["ok"])

        let points = DemandMapViewModel.aggregate([], wishes: records, by: .geohash, precision: 4)
        #expect(points.map(\.id) == ["f25e"])
        #expect(points.first?.intensity == 1)
        #expect(points.first.map { DemandFormatting.wishQuantity(of: $0.wishes[0]) } == "2 douzaines")
    }

    @Test func myOffersScopeLeavesWishesOutAndProductFilterKeepsItsCategory() async {
        let wishes = [
            VendorTestData.wish("produce", group: ID.hochelaga, household: "h1", category: .produce, quantity: 15),
            VendorTestData.wish("rice", group: ID.hochelaga, household: "h2", category: .grains, quantity: 10, productId: ID.rice),
        ]
        let model = DemandMapViewModel(repositories: VendorTestData.repositories(wishes: wishes), vendorId: ID.fermeRive)
        await model.load()

        model.productFilter = ID.potatoes
        // Pommes de terre = fruits et légumes : l'envie « produce » sans produit précis compte, pas celle du riz.
        #expect(model.points.map(\.id) == ["Saint-Michel", "Hochelaga"])
        #expect(model.points.last?.wishes.map(\.category) == [.produce])

        model.productFilter = nil
        model.scope = .myOffers
        #expect(model.points.map(\.id) == ["Saint-Michel"])
        #expect(model.totalWishingHouseholds == 0)
    }

    // MARK: Revenus : parts réelles

    private func share(_ household: String, quantity: Int, final: Cents? = nil) -> Share {
        Share(householdId: household, quantity: quantity, finalPriceCents: final, isPaid: final != nil,
              suspendedAmountCents: 500, subsidyCents: 300, qrCode: nil, isPickedUp: false)
    }

    @Test func revenueUsesFrozenPricesThenTheReachedTier() throws {
        let offer = try #require(FakeData.montreal.offers.first { $0.id == ID.potatoOffer })
        let order = VendorTestData.order(id: "o", group: ID.saintMichel, offer: ID.potatoOffer, shares: 5, households: 3, tierIndex: 0)
        let shares = [share("a", quantity: 2, final: 2 * 990), share("b", quantity: 2), share("c", quantity: 1)]

        // Part figée au palier 2 (9,90 $) + 3 parts au palier atteint (11,50 $) ; dons et subventions ignorés.
        #expect(VendorRepositoryQueries.revenue(of: order, offer: offer, shares: shares) == 2 * 990 + 3 * 1_150)
        // Sans parts lues : parts engagées × palier.
        #expect(VendorRepositoryQueries.revenue(of: order, offer: offer, shares: []) == 5 * 1_150)
        // Sous le premier palier, seules les parts figées rapportent.
        var below = order
        below.currentTierIndex = nil
        #expect(VendorRepositoryQueries.revenue(of: below, offer: offer, shares: shares) == 2 * 990)
    }

    @Test func revenueTabReadsTheOrderShares() async throws {
        var data = FakeData.montreal
        // Toutes les parts de Saint-Michel figées à 9,90 $ la part (clôture au palier 2).
        let frozen = try #require(data.shares[ID.potatoOrder]).map { share in
            var share = share
            share.finalPriceCents = share.quantity * 990
            return share
        }
        data.shares[ID.potatoOrder] = frozen
        let total = frozen.reduce(0) { $0 + $1.quantity } * 990

        let model = VendorRevenueModel(repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive)
        await model.load()
        let revenue = try #require(model.state.value)
        #expect(revenue.totalCents == total)
        #expect(revenue.neighborhoods.first { $0.neighborhood == "Saint-Michel" }?.revenueCents == total)
        #expect(revenue.deliveries.first { $0.id == ID.potatoOrder }?.revenueCents == total)
        #expect(revenue.topOffer?.revenueCents == total)
    }

    // MARK: Recherche vendeur

    @Test func searchStaysInTheVendorsOwnCatalogue() async throws {
        let model = VendorSearchViewModel(repositories: VendorTestData.repositories(), vendorId: ID.fermeRive)
        await model.load()
        let all = try #require(model.state.value)
        #expect(Set(all.products.map(\.vendorId)) == [ID.fermeRive])
        #expect(Set(all.offers.map(\.offer.vendorId)) == [ID.fermeRive])
        #expect(all.neighborhoods.map(\.label) == ["Saint-Michel"])

        model.query = "riz"
        #expect(model.results.isEmpty)

        model.query = "pommes de terre"
        #expect(model.results.products.map(\.id) == [ID.potatoes])
        #expect(model.results.offers.map(\.id) == [ID.potatoOffer])
        // La demande de Saint-Michel porte sur les pommes de terre.
        #expect(model.results.neighborhoods.map(\.label) == ["Saint-Michel"])

        model.query = "saint-michel"
        #expect(model.results.products.isEmpty)
        #expect(model.results.groups.map(\.id) == [ID.saintMichel])
    }

    // MARK: Profil : quartiers par leur nom

    @Test func neighborhoodsArePickedByNameAndNeverShowTheGeohash() async throws {
        let model = VendorProfileViewModel(repositories: VendorTestData.repositories(), vendorId: ID.fermeRive)
        await model.load()

        let villeray = try #require(model.neighborhoodMatches("villeray").first)
        #expect(villeray.name == "Villeray")
        #expect(model.addNeighborhood(villeray) == nil)
        let zone = try #require(model.servedZones.last)
        #expect(zone == VendorProfileViewModel.zone(for: villeray))
        #expect(zone.count == VendorProfileViewModel.neighborhoodZonePrecision)
        #expect(model.label(forZone: zone).contains("Villeray"))
        #expect(model.neighborhoodMatches("villeray").isEmpty)
        #expect(model.addNeighborhood(villeray) == .invalidInput("Tu dessers déjà ce quartier."))

        // Point choisi sur la carte, près du centre de Rosemont.
        #expect(model.addZone(latitude: 45.556, longitude: -73.581) == nil)
        let picked = try #require(model.servedZones.last)
        #expect(model.label(forZone: picked).contains("Rosemont"))
        #expect(!model.label(forZone: picked).contains(picked))
    }
}
