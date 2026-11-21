// FirestoreCatalogRepositoryTests.swift
// B-018 : tests d'intégration des dépôts Firestore des vendeurs, produits, lots et points de cueillette,
// contre l'émulateur local (règles de `firestore.rules` comprises). Sautés quand l'émulateur ne répond pas.
// Réutilise `FirestoreEmulator` et `EmulatorDevice` de `FirestoreGroupOrderRepositoryTests.swift`.
//
// Lancer l'émulateur depuis la racine du repo :
//   npx -y firebase-tools@latest emulators:start --project demo-grenier --only auth,firestore

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import Foundation
import Testing
import FirebaseFirestore
@testable import AMC_MobileApp

/// Catalogue de test isolé : ids et zone uniques (la base de l'émulateur est partagée entre les suites).
private nonisolated struct CatalogWorld: Sendable {
    let suffix = UUID().uuidString.prefix(8).lowercased()
    var vendorId: String { "vendor-\(suffix)" }
    var otherVendorId: String { "vendor-autre-\(suffix)" }
    var zone: String { "zone-\(suffix)" }

    /// Vendeur écrit SANS champ `id` : l'id du document doit faire foi.
    func seedVendor(_ id: String, legalName: String) async throws {
        try await FirestoreEmulator.seed("vendors/\(id)", [
            "legalName": legalName, "kind": "farm", "description": "Ferme de test",
            "photoURLs": ["https://example.com/a.jpg"], "servedZones": [zone], "isVerified": true,
        ])
    }

    func seedProduct(_ id: String, vendorId: String, name: String) async throws {
        try await FirestoreEmulator.seed("products/\(id)", [
            "vendorId": vendorId, "name": name, "category": "grains", "unit": "sac de 10 kg",
            "origin": "Québec", "tags": ["organic"], "referenceGroceryPriceCents": 2_500,
        ])
    }

    func seedOffer(_ id: String, vendorId: String, status: String, zones: [String], deadline: Date) async throws {
        try await FirestoreEmulator.seed("offers/\(id)", [
            "vendorId": vendorId, "productId": "product-\(suffix)", "totalShares": 20, "shareUnit": "5 kg",
            "minimumSharesToLaunch": 5, "deadline": deadline, "zones": zones, "status": status,
            "tiers": [["minShares": 5, "priceCents": 1_000]],
        ])
    }

    /// Profil de l'utilisateur ; `vendorId` en fait le vendeur (champ jamais écrit par le client).
    func seedUser(_ device: EmulatorDevice, vendorId: String? = nil) async throws {
        var fields: [String: Any] = [
            "id": device.uid, "displayName": "Test", "language": "fr", "roles": [vendorId == nil ? "family" : "vendor"],
            "neighborhood": "test", "dietaryPreferences": [String](), "seniorMode": false,
        ]
        if let vendorId { fields["vendorId"] = vendorId }
        try await FirestoreEmulator.seed("users/\(device.uid)", fields)
    }

    func product(_ id: String, vendorId: String) -> Product {
        Product(
            id: id, vendorId: vendorId, name: "Lentilles vertes", category: .legumes, unit: "sac de 5 kg",
            origin: "Saskatchewan", tags: [.vegan], photoURL: nil, referenceGroceryPriceCents: 1_899
        )
    }

    func offer(_ id: String, tiers: [PriceTier] = [PriceTier(minShares: 5, priceCents: 900)]) -> Offer {
        Offer(
            id: id, vendorId: vendorId, productId: "product-\(suffix)", totalShares: 30, shareUnit: "2 kg",
            tiers: tiers, minimumSharesToLaunch: 5, deadline: Date(timeIntervalSince1970: 2_000_000_000),
            zones: [zone], status: .active
        )
    }
}

@Suite(.serialized, .enabled(if: FirestoreEmulator.isAvailable, "Émulateur Firebase absent (127.0.0.1:8080 et :9099)"))
struct FirestoreCatalogRepositoryTests {
    // MARK: - Vendeurs et produits

    @Test func vendorsAndProductsDecodeWithDocumentIdAndSort() async throws {
        let world = CatalogWorld()
        try await world.seedVendor(world.vendorId, legalName: "Zeta \(world.suffix)")
        try await world.seedVendor(world.otherVendorId, legalName: "Alpha \(world.suffix)")
        try await world.seedProduct("p2-\(world.suffix)", vendorId: world.vendorId, name: "Riz")
        try await world.seedProduct("p1-\(world.suffix)", vendorId: world.vendorId, name: "Avoine")
        try await world.seedProduct("p3-\(world.suffix)", vendorId: world.otherVendorId, name: "Farine")
        let device = try await EmulatorDevice.signIn()
        let repository = FirestoreVendorRepository(db: device.db)

        let vendor = try await repository.vendor(id: world.vendorId)
        #expect(vendor.id == world.vendorId)
        #expect(vendor.kind == .farm)
        #expect(vendor.averageRating == nil)
        let mine = try await repository.vendors().map(\.id).filter { $0.hasSuffix(world.suffix) }
        #expect(mine == [world.otherVendorId, world.vendorId])

        let products = try await repository.products(ofVendor: world.vendorId)
        #expect(products.map(\.name) == ["Avoine", "Riz"])
        #expect(products.first?.id == "p1-\(world.suffix)")
        #expect(products.first?.tags == [.organic])
        #expect(try await repository.product(id: "p3-\(world.suffix)").vendorId == world.otherVendorId)

        await #expect(throws: AppError.notFound) { try await repository.vendor(id: "absent-\(world.suffix)") }
        await #expect(throws: AppError.notFound) { try await repository.product(id: "absent-\(world.suffix)") }
    }

    @Test func onlyTheVendorSavesItsProducts() async throws {
        let world = CatalogWorld()
        try await world.seedVendor(world.vendorId, legalName: "Ferme \(world.suffix)")
        let vendorDevice = try await EmulatorDevice.signIn()
        let family = try await EmulatorDevice.signIn()
        try await world.seedUser(vendorDevice, vendorId: world.vendorId)
        try await world.seedUser(family)
        let vendorRepository = FirestoreVendorRepository(db: vendorDevice.db)
        let familyRepository = FirestoreVendorRepository(db: family.db)

        let product = world.product("lentilles-\(world.suffix)", vendorId: world.vendorId)
        try await vendorRepository.saveProduct(product)
        #expect(try await familyRepository.product(id: product.id) == product)

        var renamed = product
        renamed.name = "Lentilles corail"
        try await vendorRepository.saveProduct(renamed)
        #expect(try await familyRepository.products(ofVendor: world.vendorId).map(\.name) == ["Lentilles corail"])

        // Une famille ne peut pas modifier le catalogue d'un vendeur.
        await #expect(throws: AppError.permissionDenied) {
            try await familyRepository.saveProduct(world.product("intrus-\(world.suffix)", vendorId: world.vendorId))
        }
        // Vendeur inconnu : refusé avant d'écrire, comme le fake.
        await #expect(throws: AppError.notFound) {
            try await vendorRepository.saveProduct(world.product("orphelin-\(world.suffix)", vendorId: "absent-\(world.suffix)"))
        }
    }

    // MARK: - Lots

    @Test func activeOffersFilterByStatusAndZoneSortedByDeadline() async throws {
        let world = CatalogWorld()
        let now = Date.now
        try await world.seedOffer("late-\(world.suffix)", vendorId: world.vendorId, status: "active",
                                  zones: [world.zone, "ailleurs"], deadline: now.addingTimeInterval(7_200))
        try await world.seedOffer("soon-\(world.suffix)", vendorId: world.otherVendorId, status: "active",
                                  zones: [world.zone], deadline: now.addingTimeInterval(3_600))
        try await world.seedOffer("draft-\(world.suffix)", vendorId: world.vendorId, status: "draft",
                                  zones: [world.zone], deadline: now.addingTimeInterval(1_800))
        try await world.seedOffer("other-zone-\(world.suffix)", vendorId: world.vendorId, status: "active",
                                  zones: ["autre-\(world.suffix)"], deadline: now.addingTimeInterval(900))
        let device = try await EmulatorDevice.signIn()
        let repository = FirestoreOfferRepository(db: device.db)

        let inZone = try await repository.activeOffers(inZone: world.zone)
        #expect(inZone.map(\.id) == ["soon-\(world.suffix)", "late-\(world.suffix)"])
        #expect(inZone.allSatisfy { $0.status == .active })

        let everywhere = try await repository.activeOffers(inZone: nil).map(\.id).filter { $0.hasSuffix(world.suffix) }
        #expect(everywhere == ["other-zone-\(world.suffix)", "soon-\(world.suffix)", "late-\(world.suffix)"])

        let ofVendor = try await repository.offers(ofVendor: world.vendorId)
        #expect(ofVendor.map(\.id) == ["other-zone-\(world.suffix)", "draft-\(world.suffix)", "late-\(world.suffix)"])

        let offer = try await repository.offer(id: "late-\(world.suffix)")
        #expect(offer.tiers == [PriceTier(minShares: 5, priceCents: 1_000)])
        await #expect(throws: AppError.notFound) { try await repository.offer(id: "absent-\(world.suffix)") }
    }

    @Test func onlyTheVendorSavesItsOffers() async throws {
        let world = CatalogWorld()
        try await world.seedVendor(world.vendorId, legalName: "Ferme \(world.suffix)")
        try await world.seedProduct("product-\(world.suffix)", vendorId: world.vendorId, name: "Riz")
        let vendorDevice = try await EmulatorDevice.signIn()
        let family = try await EmulatorDevice.signIn()
        try await world.seedUser(vendorDevice, vendorId: world.vendorId)
        try await world.seedUser(family)
        let vendorRepository = FirestoreOfferRepository(db: vendorDevice.db)
        let familyRepository = FirestoreOfferRepository(db: family.db)

        let offer = world.offer("lot-\(world.suffix)")
        try await vendorRepository.saveOffer(offer)
        #expect(try await familyRepository.offer(id: offer.id) == offer)
        #expect(try await familyRepository.activeOffers(inZone: world.zone).map(\.id) == [offer.id])

        var closed = offer
        closed.status = .closed
        try await vendorRepository.saveOffer(closed)
        #expect(try await familyRepository.activeOffers(inZone: world.zone).isEmpty)

        await #expect(throws: AppError.permissionDenied) {
            try await familyRepository.saveOffer(world.offer("intrus-\(world.suffix)"))
        }
        await #expect(throws: AppError.invalidInput("Ajoute au moins un palier de prix.")) {
            try await vendorRepository.saveOffer(world.offer("vide-\(world.suffix)", tiers: []))
        }
    }

    // MARK: - Points de cueillette

    @Test func pickupPointsDecodeAndSortByName() async throws {
        let world = CatalogWorld()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        for (id, name) in [("b-\(world.suffix)", "Zz Biblio \(world.suffix)"), ("a-\(world.suffix)", "Aa Église \(world.suffix)")] {
            try await FirestoreEmulator.seed("pickupPoints/\(id)", [
                "hostUserId": "host-\(world.suffix)", "name": name, "address": "123 rue Test",
                "capacity": 40, "accessibility": ["wheelchair", "nearMetro"],
                "slots": [["start": start, "end": start.addingTimeInterval(3_600)]],
            ])
        }
        let device = try await EmulatorDevice.signIn()
        let repository = FirestorePickupPointRepository(db: device.db)

        let mine = try await repository.pickupPoints().filter { $0.id.hasSuffix(world.suffix) }
        #expect(mine.map(\.id) == ["a-\(world.suffix)", "b-\(world.suffix)"])
        let point = try await repository.pickupPoint(id: "a-\(world.suffix)")
        #expect(point.accessibility == [.wheelchair, .nearMetro])
        #expect(point.photoURL == nil)
        #expect(point.slots == [PickupSlot(start: start, end: start.addingTimeInterval(3_600))])
        await #expect(throws: AppError.notFound) { try await repository.pickupPoint(id: "absent-\(world.suffix)") }
    }
}
#endif
