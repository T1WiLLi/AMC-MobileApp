// ShareSpecTests.swift
// B-050 : part structurée (contenant, nombre, poids, valeur), texte affiché, lecture des anciennes
// chaînes et compatibilité Codable de `Offer` (documents écrits avant B-050).

import Foundation
import Testing
@testable import AMC_MobileApp

struct ShareSpecTests {
    // MARK: Texte affiché

    @Test(arguments: [
        (ShareSpec(container: .bag, weight: .init(10, .kilogram)), "sac de 10 kg"),
        (ShareSpec(container: .bag, count: 2, weight: .init(5, .kilogram)), "2 sacs de 5 kg"),
        (ShareSpec(container: .crate, weight: .init(2.5, .kilogram)), "caisse de 2,5 kg"),
        (ShareSpec(container: .tray, count: 3, weight: .init(500, .gram)), "3 plateaux de 500 g"),
        (ShareSpec(container: .bulk, weight: .init(10, .kilogram)), "10 kg"),
        (ShareSpec(container: .bottle, weight: .init(1, .liter)), "bouteille de 1 L"),
        (ShareSpec(container: .bunch, weight: .init(12, .piece)), "botte de 12 unités"),
        (ShareSpec(container: .crate, weight: .init(1, .piece)), "1 caisse"),
        (ShareSpec(container: .crate, count: 3, weight: .init(1, .piece)), "3 caisses"),
        (ShareSpec(container: .box, weight: .init(1, .kilogram)), "boîte de 1 kg"),
    ])
    func label(share: ShareSpec, expected: String) {
        #expect(share.label == expected)
    }

    // MARK: Lecture d'une ancienne chaîne

    @Test(arguments: [
        ("sac de 10 kg", ShareSpec(container: .bag, weight: .init(10, .kilogram))),
        ("caisse de 5 kg", ShareSpec(container: .crate, weight: .init(5, .kilogram))),
        ("2 sacs de 5 kg", ShareSpec(container: .bag, count: 2, weight: .init(5, .kilogram))),
        ("Sac de 2,5 kg", ShareSpec(container: .bag, weight: .init(2.5, .kilogram))),
        ("10 kg", ShareSpec(container: .bulk, weight: .init(10, .kilogram))),
        ("500 g", ShareSpec(container: .bulk, weight: .init(500, .gram))),
        ("5 L", ShareSpec(container: .bulk, weight: .init(5, .liter))),
        ("kg", ShareSpec(container: .bulk, weight: .init(1, .kilogram))),
        ("1 douzaine", ShareSpec(container: .bulk, weight: .init(12, .piece))),
        ("boîte de 12 unités", ShareSpec(container: .box, weight: .init(12, .piece))),
        ("caisse", ShareSpec(container: .crate, weight: .init(1, .piece))),
        ("1 caisse", ShareSpec(container: .crate, weight: .init(1, .piece))),
        ("", ShareSpec(container: .bulk, weight: .init(1, .piece))),
    ])
    func parsing(text: String, expected: ShareSpec) {
        #expect(ShareSpec(parsing: text) == expected)
    }

    @Test(arguments: ["sac de 10 kg", "caisse de 5 kg", "2 sacs de 5 kg", "10 kg", "bouteille de 1 L", "botte de 12 unités", "1 caisse", "3 caisses"])
    func labelRoundTrips(text: String) {
        #expect(ShareSpec(parsing: text).label == text)
    }

    // MARK: Mesure et validité

    @Test func measureMultipliesContainers() {
        #expect(ShareSpec(container: .bag, count: 2, weight: .init(5, .kilogram)).measure == .mass(kilograms: 10))
        #expect(ShareSpec(container: .tray, weight: .init(500, .gram)).measure == .mass(kilograms: 0.5))
        #expect(ShareSpec(container: .bottle, count: 6, weight: .init(500, .milliliter)).measure == .volume(liters: 3))
        #expect(ShareSpec(container: .bunch, weight: .init(12, .piece)).measure == .count(units: 12))
        #expect(ShareSpec(container: .bag, weight: .init(0, .kilogram)).measure == .unknown)
    }

    @Test func measureMatchesTheLegacyParser() {
        for text in ["sac de 10 kg", "2 sacs de 5 kg", "5 L", "500 g", "1 douzaine"] {
            #expect(ShareSpec(parsing: text).measure == ShareMeasure.parse(text), "\(text)")
        }
    }

    @Test func validity() {
        #expect(ShareSpec.default.isValid)
        #expect(!ShareSpec(container: .bag, weight: .init(0, .kilogram)).isValid)
        #expect(!ShareSpec(container: .bag, count: 0, weight: .init(5, .kilogram)).isValid)
        #expect(!ShareSpec(container: .bag, weight: .init(.infinity, .kilogram)).isValid)
        #expect(!ShareSpec(container: .bag, weight: .init(5, .kilogram), valueCents: -1).isValid)
    }

    // MARK: Codable

    @Test func codableRoundTrip() throws {
        let share = ShareSpec(container: .crate, count: 2, weight: .init(2.5, .kilogram), valueCents: 1_299)
        let data = try JSONEncoder().encode(share)
        #expect(try JSONDecoder().decode(ShareSpec.self, from: data) == share)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"container\":\"caisse\""))
        #expect(json.contains("\"unit\":\"kg\""))
    }

    @Test func offerEncodesShareAndItsLabel() throws {
        let offer = Self.offer(share: ShareSpec(container: .bag, weight: .init(10, .kilogram), valueCents: 1_599))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(offer)) as? [String: Any])
        #expect(object["shareUnit"] as? String == "sac de 10 kg")
        let share = try #require(object["share"] as? [String: Any])
        #expect(share["container"] as? String == "sac")
        #expect(share["valueCents"] as? Int == 1_599)
        #expect(try JSONDecoder().decode(Offer.self, from: JSONEncoder().encode(offer)) == offer)
    }

    @Test func legacyOfferWithoutShareIsReadFromShareUnit() throws {
        let legacy = """
        {"id":"o1","vendorId":"v1","productId":"p1","totalShares":30,"shareUnit":"2 sacs de 5 kg",
         "tiers":[{"minShares":5,"priceCents":1000}],"minimumSharesToLaunch":5,"deadline":0,
         "zones":["f25d"],"status":"active"}
        """
        let offer = try JSONDecoder().decode(Offer.self, from: Data(legacy.utf8))
        #expect(offer.share == ShareSpec(container: .bag, count: 2, weight: .init(5, .kilogram)))
        #expect(offer.shareUnit == "2 sacs de 5 kg")
    }

    @Test func settingShareUnitParsesIt() {
        var offer = Self.offer(share: .default)
        offer.shareUnit = "caisse de 5 kg"
        #expect(offer.share == ShareSpec(container: .crate, weight: .init(5, .kilogram)))
    }

    @Test func demoOffersAreStructured() {
        for offer in FakeData.montreal.offers {
            #expect(offer.share.isValid, "\(offer.id)")
            #expect(offer.share.valueCents != nil, "\(offer.id)")
        }
    }

    private static func offer(share: ShareSpec) -> Offer {
        Offer(id: "o1", vendorId: "v1", productId: "p1", totalShares: 30, share: share,
              tiers: [PriceTier(minShares: 5, priceCents: 1_000)], minimumSharesToLaunch: 5,
              deadline: Date(timeIntervalSince1970: 0), zones: ["f25d"], status: .active)
    }
}
