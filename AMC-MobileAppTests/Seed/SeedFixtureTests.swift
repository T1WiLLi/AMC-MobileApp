import Foundation
import Testing
@testable import AMC_MobileApp

/// Fixtures du catalogue de démo (B-026) : elles doivent se décoder avec les modèles Swift
/// et respecter les critères de RQ-109, RQ-039 et RQ-113.
/// Les tests tournent sur le simulateur, qui lit les fichiers du repo sur le Mac.
struct SeedFixtureTests {
    private static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Seed/
        .deletingLastPathComponent()  // AMC-MobileAppTests/
        .deletingLastPathComponent()  // racine du repo
        .appending(path: "scripts/seed/fixtures")

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appending(path: "\(name).json"))
    }

    private func vendors() throws -> [Vendor] { try JSONDecoder().decode([Vendor].self, from: data("vendors")) }
    private func products() throws -> [Product] { try JSONDecoder().decode([Product].self, from: data("products")) }

    /// `deadlineInDays` est converti en `deadline` par le script ; on fait pareil ici.
    private func offers() throws -> [Offer] {
        let raw = try #require(try JSONSerialization.jsonObject(with: data("offers")) as? [[String: Any]])
        let now = Date.now.timeIntervalSinceReferenceDate
        let converted: [[String: Any]] = try raw.map { offer in
            var offer = offer
            let days = try #require(offer.removeValue(forKey: "deadlineInDays") as? Int)
            offer["deadline"] = now + Double(days) * 86_400
            return offer
        }
        return try JSONDecoder().decode([Offer].self, from: JSONSerialization.data(withJSONObject: converted))
    }

    @Test func countsMatchRQ109() throws {
        #expect(try vendors().count == 6)
        #expect(try products().count == 40)
        #expect(try offers().count == 25)
    }

    @Test func idsAreUnique() throws {
        #expect(Set(try vendors().map(\.id)).count == 6)
        #expect(Set(try products().map(\.id)).count == 40)
        #expect(Set(try offers().map(\.id)).count == 25)
    }

    @Test func everyRQ039CategoryIsCovered() throws {
        #expect(Set(try products().map(\.category)) == Set(Product.Category.allCases))
    }

    @Test func demoPersonaVendorExists() throws {
        let lafleur = try #require(try vendors().first { $0.legalName == "Ferme Lafleur" })
        #expect(try offers().contains { $0.vendorId == lafleur.id && $0.status == .active })
    }

    @Test func linksBetweenFilesAreValid() throws {
        let vendorIds = Set(try vendors().map(\.id))
        let products = try products()
        #expect(products.allSatisfy { vendorIds.contains($0.vendorId) })
        let productsById = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        for offer in try offers() {
            let product = try #require(productsById[offer.productId], "\(offer.id) : produit inconnu")
            #expect(product.vendorId == offer.vendorId, "\(offer.id) : vendeur différent du produit")
        }
    }

    @Test func everyOfferHasAtLeastThreeDecreasingTiersBelowGroceryPrice() throws {
        let productsById = Dictionary(uniqueKeysWithValues: try products().map { ($0.id, $0) })
        for offer in try offers() {
            let tiers = offer.sortedTiers
            #expect(tiers.count >= 3, "\(offer.id)")
            #expect(zip(tiers, tiers.dropFirst()).allSatisfy { $0.priceCents > $1.priceCents }, "\(offer.id)")
            let reference = try #require(productsById[offer.productId]).referenceGroceryPriceCents
            #expect(tiers.allSatisfy { $0.priceCents < reference }, "\(offer.id)")
            #expect(offer.minimumSharesToLaunch == tiers[0].minShares, "\(offer.id)")
            #expect(tiers.last!.minShares <= offer.totalShares, "\(offer.id)")
        }
    }

    @Test func offerZonesAreServedByTheirVendor() throws {
        let vendorsById = Dictionary(uniqueKeysWithValues: try vendors().map { ($0.id, $0) })
        for offer in try offers() {
            let served = Set(try #require(vendorsById[offer.vendorId]).servedZones)
            #expect(Set(offer.zones).isSubset(of: served), "\(offer.id)")
            #expect(offer.deadline > .now, "\(offer.id)")
        }
    }

    @Test func everyProductNamesThePriceSource() throws {
        let raw = try #require(try JSONSerialization.jsonObject(with: data("products")) as? [[String: Any]])
        #expect(raw.allSatisfy { ($0["referencePriceSource"] as? String)?.isEmpty == false })
    }
}
