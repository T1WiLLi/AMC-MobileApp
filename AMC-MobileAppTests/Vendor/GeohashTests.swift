import CoreLocation
import Testing
@testable import AMC_MobileApp

struct GeohashTests {
    @Test func decodesKnownReferenceHashes() throws {
        // Valeurs de référence du format geohash (Wikipedia, geohash.org).
        let jutland = try #require(Geohash.decode("u4pruydqqvj"))
        #expect(abs(jutland.latitude - 57.64911) < 0.0001)
        #expect(abs(jutland.longitude - 10.40744) < 0.0001)

        let spain = try #require(Geohash.decode("ezs42"))
        #expect(abs(spain.latitude - 42.605) < 0.001)
        #expect(abs(spain.longitude - -5.603) < 0.001)
    }

    @Test func montrealGroupsLandInMontreal() throws {
        for hash in ["f25dv", "f25ej", "f25eh8", "f25dud"] {
            let coordinate = try #require(Geohash.decode(hash))
            #expect((45.4...45.7).contains(coordinate.latitude), "\(hash)")
            #expect((-73.8 ... -73.4).contains(coordinate.longitude), "\(hash)")
        }
    }

    @Test func boundsShrinkWithPrecisionAndContainCenter() throws {
        let coarse = try #require(Geohash.bounds(of: "f25"))
        let fine = try #require(Geohash.bounds(of: "f25dv"))
        #expect(fine.maxLatitude - fine.minLatitude < coarse.maxLatitude - coarse.minLatitude)
        #expect(fine.minLatitude >= coarse.minLatitude && fine.maxLatitude <= coarse.maxLatitude)
        #expect(fine.minLongitude >= coarse.minLongitude && fine.maxLongitude <= coarse.maxLongitude)
    }

    @Test func isCaseInsensitive() {
        #expect(Geohash.bounds(of: "F25DV") == Geohash.bounds(of: "f25dv"))
    }

    @Test func rejectsInvalidHashes() {
        #expect(Geohash.decode("") == nil)
        #expect(Geohash.decode("f25a") == nil) // « a » n'est pas en base 32 geohash
        #expect(Geohash.decode("f2 5") == nil)
    }
}

struct DemandMapFormattingTests {
    private func product(_ unit: String, shares: Int) -> DemandMapViewModel.ProductDemand {
        .init(productId: "p", name: "Riz basmati", shareUnit: unit, committedShares: shares)
    }

    @Test func wantedQuantityUsesKilogramsWhenUnitHasWeight() {
        #expect(DemandFormatting.wantedQuantity(of: product("sac de 10 kg", shares: 26)) == "260 kg voulus")
        #expect(DemandFormatting.kilogramsPerShare(in: "caisse de 2,5 kg") == 2.5)
    }

    @Test func wantedQuantityFallsBackToShares() {
        #expect(DemandFormatting.wantedQuantity(of: product("douzaine", shares: 3)) == "3 parts voulues")
        #expect(DemandFormatting.wantedQuantity(of: product("douzaine", shares: 1)) == "1 part voulue")
    }

    @Test func familiesAreSingularOrPlural() {
        #expect(DemandFormatting.families(1) == "1 famille")
        #expect(DemandFormatting.families(24) == "24 familles")
    }

    @MainActor
    @Test func accessibilityDescriptionMentionsHighDemand() {
        let point = DemandMapViewModel.DemandPoint(
            id: "Parc-Ex Ouest", grouping: .neighborhood, label: "Parc-Ex Ouest", geohash: "f25eh8", groupIds: ["g"],
            committedShares: 26, committedHouseholds: 24, householdCount: 31, products: [], intensity: 1
        )
        #expect(point.accessibilityDescription == "Parc-Ex Ouest, 24 familles, forte demande")
    }

    /// Bulles de la carte Demande : « Saint-Michel » (f25dv) tombait près du Mont-Royal, « Hochelaga » (f25ej) sur le Plateau.
    @Test func demandBubblesSitOnTheirNeighborhood() throws {
        func point(_ grouping: DemandMapViewModel.Grouping, _ label: String, _ geohash: String,
                   neighborhood: String?) -> DemandMapViewModel.DemandPoint {
            DemandMapViewModel.DemandPoint(
                id: label, grouping: grouping, label: label, geohash: geohash, groupIds: ["g"], committedShares: 19,
                committedHouseholds: 11, householdCount: 12, products: [], intensity: 1, neighborhood: neighborhood
            )
        }
        func isNear(_ coordinate: CLLocationCoordinate2D?, _ latitude: Double, _ longitude: Double) -> Bool {
            guard let coordinate else { return false }
            return abs(coordinate.latitude - latitude) < 0.002 && abs(coordinate.longitude - longitude) < 0.002
        }

        // Quartiers : le centre connu du quartier, même avec un geohash de groupe à 5 caractères.
        #expect(isNear(point(.neighborhood, "Saint-Michel", "f25dv", neighborhood: "Saint-Michel").coordinate, 45.565, -73.615))
        #expect(isNear(point(.neighborhood, "hochelaga", "f25ej", neighborhood: nil).coordinate, 45.548, -73.540))
        // Groupes : un centre loin de son quartier est ramené au quartier…
        #expect(isNear(point(.group, "Voisins de Saint-Michel", "f25dv", neighborhood: "Saint-Michel").coordinate, 45.565, -73.615))
        // … un centre précis dans son quartier est gardé.
        let precise = try #require(Geohash.decode("f25eh8"))
        #expect(isNear(point(.group, "Parc-Ex Ouest", "f25eh8", neighborhood: "Parc-Extension").coordinate,
                       precise.latitude, precise.longitude))
        // Zones, ou quartier inconnu : le centre du geohash.
        let zone = try #require(Geohash.decode("f25d"))
        #expect(isNear(point(.geohash, "f25d", "f25d", neighborhood: "Saint-Michel").coordinate, zone.latitude, zone.longitude))
        #expect(isNear(point(.neighborhood, "Laval", "f25dv", neighborhood: nil).coordinate, 45.5054, -73.5864))
    }
}
