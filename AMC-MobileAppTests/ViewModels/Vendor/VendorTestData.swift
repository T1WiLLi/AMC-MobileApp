import Foundation
@testable import AMC_MobileApp

/// Jeux de données dérivés de `FakeData.montreal` pour les tests du portail Vendeur (T-022).
enum VendorTestData {
    typealias ID = FakeData.ID

    static func order(
        id: String,
        group: String,
        offer: String,
        shares: Int,
        households: Int,
        tierIndex: Int?,
        status: GroupOrder.Status = .open
    ) -> GroupOrder {
        GroupOrder(id: id, groupId: group, offerId: offer, status: status, currentTierIndex: tierIndex,
                   committedShares: shares, committedHouseholds: households, pickupPointId: nil, pickupSlots: [])
    }

    /// Montréal + commandes supplémentaires.
    static func data(adding orders: [GroupOrder]) -> FakeData {
        var data = FakeData.montreal
        data.groupOrders += orders
        return data
    }

    static func repositories(adding orders: [GroupOrder] = []) -> AppRepositories {
        .fake(behavior: .instant, data: data(adding: orders))
    }
}
