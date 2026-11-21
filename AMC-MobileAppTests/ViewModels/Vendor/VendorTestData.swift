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

    /// Dépôts instantanés ; `wishes` remplace les envies de démo (aucune par défaut, pour isoler les commandes).
    static func repositories(adding orders: [GroupOrder] = [], wishes: [GroupWish] = []) -> AppRepositories {
        withWishes(wishes, .fake(behavior: .instant, data: data(adding: orders)))
    }

    /// Mêmes dépôts, avec ces envies seulement.
    static func withWishes(_ wishes: [GroupWish], _ repositories: AppRepositories) -> AppRepositories {
        var repositories = repositories
        repositories.wishes = FakeGroupWishRepository(behavior: .instant, wishes: wishes)
        return repositories
    }

    static func wish(
        _ id: String, group: String, household: String, category: Product.Category, quantity: Double,
        unit: MeasureUnit = .kilogram, productId: String? = nil, until: Date? = nil
    ) -> GroupWish {
        GroupWish(id: id, groupId: group, householdId: household, category: category, productId: productId,
                  quantity: quantity, unit: unit, frequency: .monthly, wantedUntil: until)
    }
}
