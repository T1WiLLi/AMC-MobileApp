import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de DeliveryManifest (RQ-073, RQ-074).
struct DeliveryManifestTests {
    private func offer(_ id: String, product: String, unit: String, vendor: String = "v1") -> Offer {
        var offer = TierEngineTests.offer
        offer.id = id
        offer.productId = product
        offer.shareUnit = unit
        offer.vendorId = vendor
        return offer
    }

    private func product(_ id: String, _ name: String) -> Product {
        Product(id: id, vendorId: "v1", name: name, category: .grains, unit: "kg", origin: "Québec",
                tags: [], photoURL: nil, referenceGroceryPriceCents: 1_500)
    }

    private func point(_ id: String, _ name: String, _ address: String) -> PickupPoint {
        PickupPoint(id: id, hostUserId: "u-\(id)", name: name, address: address, photoURL: nil,
                    capacity: 50, accessibility: [], slots: [])
    }

    private func order(
        _ id: String, offer: String, point: String?, shares: Int, households: Int,
        status: GroupOrder.Status = .closed
    ) -> GroupOrder {
        GroupOrder(id: id, groupId: "g-\(id)", offerId: offer, status: status, currentTierIndex: nil,
                   committedShares: shares, committedHouseholds: households, pickupPointId: point,
                   pickupSlots: [])
    }

    private var offers: [Offer] {
        [offer("o1", product: "p1", unit: "10 kg"), offer("o2", product: "p2", unit: "1 caisse"),
         offer("o3", product: "p3", unit: "5 L", vendor: "v2")]
    }
    private var products: [Product] { [product("p1", "Riz basmati"), product("p2", "Pommes Cortland")] }
    private var points: [PickupPoint] {
        [point("pp1", "Café Le Pivot", "123 rue Ontario Est"), point("pp2", "Bibliothèque Frontenac", "2550 rue Ontario Est")]
    }

    private var orders: [GroupOrder] {
        [
            order("go1", offer: "o1", point: "pp1", shares: 12, households: 5),
            order("go2", offer: "o1", point: "pp1", shares: 8, households: 3),
            order("go3", offer: "o2", point: "pp1", shares: 4, households: 4),
            order("go4", offer: "o1", point: "pp2", shares: 10, households: 6),
            order("go5", offer: "o2", point: nil, shares: 2, households: 1),
            order("go6", offer: "o1", point: "pp2", shares: 30, households: 9, status: .open),
            order("go7", offer: "o1", point: "pp2", shares: 5, households: 2, status: .delivered),
            order("go8", offer: "o1", point: "pp2", shares: 0, households: 0),
            order("go9", offer: "missing", point: "pp2", shares: 3, households: 1),
        ]
    }

    // MARK: - RQ-073

    @Test func groupsClosedOrdersByPickupPointAndMergesSameProduct() {
        let manifest = DeliveryManifest(orders: orders, offers: offers, products: products, pickupPoints: points)
        #expect(manifest.stops.map(\.name) == ["Bibliothèque Frontenac", "Café Le Pivot", "Point de cueillette à confirmer"])

        let pivot = manifest.stops[1]
        #expect(pivot.pickupPointId == "pp1")
        #expect(pivot.lines.map(\.productName) == ["Pommes Cortland", "Riz basmati"])
        let rice = pivot.lines[1]
        #expect(rice.shareUnit == "10 kg")
        #expect(rice.totalShares == 20)
        #expect(rice.households == 8)
        #expect(rice.orderIds == ["go1", "go2"])
        #expect(pivot.totalShares == 24)
        #expect(pivot.totalHouseholds == 12)
        #expect(pivot.orderIds == ["go1", "go2", "go3"])

        let unassigned = manifest.stops[2]
        #expect(unassigned.pickupPointId == nil)
        #expect(unassigned.id == DeliveryManifest.unassignedStopId)
        #expect(unassigned.totalShares == 2)

        #expect(manifest.totalShares == 36)
        #expect(manifest.totalHouseholds == 19)
        #expect(manifest.orderCount == 5)
    }

    @Test func ignoresNonClosedEmptyAndOrphanOrders() {
        let manifest = DeliveryManifest(orders: orders, offers: offers, products: products, pickupPoints: points)
        let ids = Set(manifest.stops.flatMap(\.orderIds))
        #expect(ids.isDisjoint(with: ["go6", "go7", "go8", "go9"]))
    }

    @Test func filtersByVendorAndHandlesUnknownProduct() {
        let manifest = DeliveryManifest(
            orders: [order("go1", offer: "o1", point: "pp1", shares: 2, households: 1),
                     order("go2", offer: "o3", point: "pp1", shares: 3, households: 2)],
            offers: offers, products: products, pickupPoints: points, vendorId: "v2"
        )
        #expect(manifest.orderCount == 1)
        #expect(manifest.stops.first?.lines.first?.productName == "Produit inconnu")
        #expect(manifest.stops.first?.lines.first?.shareUnit == "5 L")
    }

    @Test func emptyManifest() {
        let manifest = DeliveryManifest(orders: [], offers: offers, products: products, pickupPoints: points)
        #expect(manifest.isEmpty)
        #expect(manifest.totalShares == 0)
        #expect(manifest.plainText() == "Bordereau de livraison\n\nAucune commande fermée à livrer.")
    }

    @Test func plainTextExport() {
        let manifest = DeliveryManifest(
            orders: [order("go1", offer: "o1", point: "pp1", shares: 12, households: 5),
                     order("go3", offer: "o2", point: "pp1", shares: 1, households: 1),
                     order("go5", offer: "o2", point: nil, shares: 2, households: 1)],
            offers: offers, products: products, pickupPoints: points
        )
        let expected = """
        Bordereau du 21 novembre
        3 commandes · 2 points de cueillette · 15 parts

        == Café Le Pivot — 123 rue Ontario Est ==
        - Pommes Cortland (1 caisse) : 1 part, 1 ménage
        - Riz basmati (10 kg) : 12 parts, 5 ménages
        Total : 13 parts, 6 ménages

        == Point de cueillette à confirmer ==
        - Pommes Cortland (1 caisse) : 2 parts, 1 ménage
        Total : 2 parts, 1 ménage

        Grand total : 15 parts, 7 ménages
        """
        #expect(manifest.plainText(title: "Bordereau du 21 novembre") == expected)
    }

    // MARK: - RQ-074

    @Test func markDeliveredMovesClosedToDelivered() throws {
        let closed = order("go1", offer: "o1", point: "pp1", shares: 12, households: 5)
        let delivered = try DeliveryManifest.markDelivered(closed)
        #expect(delivered.status == .delivered)
        var expected = closed
        expected.status = .delivered
        #expect(delivered == expected)
    }

    @Test func markDeliveredRejectsOtherStatuses() {
        for status in [GroupOrder.Status.open, .reached, .delivered, .cancelled] {
            let current = order("go1", offer: "o1", point: "pp1", shares: 12, households: 5, status: status)
            #expect(throws: AppError.self) { try DeliveryManifest.markDelivered(current) }
        }
        let delivered = order("go1", offer: "o1", point: "pp1", shares: 1, households: 1, status: .delivered)
        #expect(throws: AppError.invalidInput("Cette livraison est déjà marquée comme faite.")) {
            try DeliveryManifest.markDelivered(delivered)
        }
    }
}
