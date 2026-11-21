import Foundation
import Testing
@testable import AMC_MobileApp

/// Aller-retour JSON de chaque modèle Firestore (B-015).
struct ModelCodingTests {
    private static let date = Date(timeIntervalSince1970: 1_795_000_000)
    private static let slot = PickupSlot(start: date, end: date.addingTimeInterval(7_200))

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    @Test func appUser() throws {
        let user = AppUser(
            id: "u1", displayName: "Amina", photoURL: URL(string: "https://example.com/a.jpg"),
            language: .french, roles: [.family, .host], neighborhood: "Saint-Michel",
            dietaryPreferences: [.halal], seniorMode: false, householdId: "h1", vendorId: nil
        )
        #expect(try roundTrip(user) == user)
    }

    @Test func householdAndPrivate() throws {
        let household = Household(id: "h1", name: "Famille Benali", size: 5, geohash: "f25dv", userIds: ["u1"])
        #expect(try roundTrip(household) == household)
        let privateProfile = HouseholdPrivate(isSubsidized: true, referralCode: "MOISSON-42")
        #expect(try roundTrip(privateProfile) == privateProfile)
    }

    @Test func groupAndMember() throws {
        let group = NeighborhoodGroup(
            id: "g1", name: "Voisins de Saint-Michel", neighborhood: "Saint-Michel", centerGeohash: "f25dv",
            radiusMeters: 1_200, coordinatorIds: ["u1"], householdCount: 18, isPublic: true, inviteCode: "SM-2026"
        )
        #expect(try roundTrip(group) == group)
        let member = GroupMember(householdId: "h1", role: .coordinator, joinedAt: Self.date)
        #expect(try roundTrip(member) == member)
        #expect(member.id == "h1")
    }

    @Test func vendorAndProduct() throws {
        let vendor = Vendor(
            id: "v1", legalName: "Ferme Bio-Rive", kind: .farm, description: "Légumes de Mirabel",
            photoURLs: [], servedZones: ["f25d"], averageRating: nil, isVerified: true
        )
        #expect(try roundTrip(vendor) == vendor)
        let product = Product(
            id: "p1", vendorId: "v1", name: "Pommes de terre", category: .produce, unit: "sac de 10 kg",
            origin: "Mirabel, QC", tags: [.organic, .local], photoURL: nil, referenceGroceryPriceCents: 1_499
        )
        #expect(try roundTrip(product) == product)
    }

    @Test func offerGroupOrderShareAndPickupPoint() throws {
        let offer = Offer(
            id: "o1", vendorId: "v1", productId: "p1", totalShares: 40, shareUnit: "10 kg",
            tiers: [PriceTier(minShares: 10, priceCents: 1_100), PriceTier(minShares: 20, priceCents: 950)],
            minimumSharesToLaunch: 10, deadline: Self.date, zones: ["f25d"], status: .active
        )
        #expect(try roundTrip(offer) == offer)
        let order = GroupOrder(
            id: "go1", groupId: "g1", offerId: "o1", status: .open, currentTierIndex: 0,
            committedShares: 14, committedHouseholds: 11, pickupPointId: "pp1", pickupSlots: [Self.slot]
        )
        #expect(try roundTrip(order) == order)
        let share = Share(
            householdId: "h1", quantity: 2, finalPriceCents: nil, isPaid: false,
            suspendedAmountCents: 500, subsidyCents: 0, qrCode: nil, isPickedUp: false
        )
        #expect(try roundTrip(share) == share)
        let point = PickupPoint(
            id: "pp1", hostUserId: "u1", name: "Chez Amina", address: "Rue Jarry Est, Montréal",
            photoURL: nil, capacity: 20, accessibility: [.stepFree, .nearMetro], slots: [Self.slot]
        )
        #expect(try roundTrip(point) == point)
    }

    /// Les valeurs brutes des énumérations sont celles stockées dans Firestore : elles ne doivent pas changer.
    @Test func enumRawValuesAreStable() {
        #expect(AppUser.Language.french.rawValue == "fr")
        #expect(GroupOrder.Status.reached.rawValue == "reached")
        #expect(DietaryTag.glutenFree.rawValue == "glutenFree")
    }

    @Test func decodesFirestoreShapedJSON() throws {
        let json = Data("""
        {"householdId":"h7","quantity":1,"isPaid":true,"suspendedAmountCents":0,"subsidyCents":950,"isPickedUp":false}
        """.utf8)
        let share = try JSONDecoder().decode(Share.self, from: json)
        #expect(share.id == "h7")
        #expect(share.finalPriceCents == nil)
        #expect(share.subsidyCents == 950)
    }
}

/// Calcul du palier courant et du suivant (sert à TierProgressBar).
struct OfferTierTests {
    private let offer = Offer(
        id: "o1", vendorId: "v1", productId: "p1", totalShares: 60, shareUnit: "10 kg",
        tiers: [
            PriceTier(minShares: 30, priceCents: 900),
            PriceTier(minShares: 10, priceCents: 1_100),
            PriceTier(minShares: 20, priceCents: 1_000),
        ],
        minimumSharesToLaunch: 10, deadline: .now, zones: [], status: .active
    )

    @Test func sortsTiers() {
        #expect(offer.sortedTiers.map(\.minShares) == [10, 20, 30])
    }

    @Test func belowFirstTier() {
        #expect(offer.tierIndex(forCommittedShares: 9) == nil)
        #expect(offer.nextTier(afterCommittedShares: 9)?.minShares == 10)
    }

    @Test func onAndBetweenTiers() {
        #expect(offer.tierIndex(forCommittedShares: 10) == 0)
        #expect(offer.tierIndex(forCommittedShares: 25) == 1)
        #expect(offer.nextTier(afterCommittedShares: 25)?.priceCents == 900)
    }

    @Test func lastTierReached() {
        #expect(offer.tierIndex(forCommittedShares: 45) == 2)
        #expect(offer.nextTier(afterCommittedShares: 45) == nil)
    }
}
