import Foundation

/// Démo de l'écran hôte (T-181) : dans l'app en mode fake, une commande est déjà livrée chez Amina pour que
/// « Remettre les parts » montre des ménages à servir. `montreal` (tests) reste sans elle : ses chiffres de vendeurs
/// et de commandes ne bougent pas.
nonisolated extension FakeData {
    enum HostDemoID {
        /// Pommes Cortland de la cuisine collective de Villeray, livrées chez Amina (rue Jarry).
        static let deliveredOrder = "order-villeray-pommes-cortland"
    }

    /// `montreal` + la commande livrée chez Amina. Utilisé par `AppContext.demo`, le mode fake et « Réinitialiser la démo ».
    static let demo: FakeData = montreal.withHostDemoOrder()

    /// Ajoute la commande de pommes livrée chez Amina : Voisins 1 (2 parts) et Voisins 3 attendus, Voisins 2 déjà passé.
    func withHostDemoOrder(now: Date = .now) -> FakeData {
        var data = self
        let orderId = HostDemoID.deliveredOrder
        let neighbours = (1...3).map { "household-voisin-\($0)" }
        let shares = zip(neighbours, [2, 1, 1]).enumerated().map { index, pair in
            let (householdId, quantity) = pair
            return Share(householdId: householdId, quantity: quantity, finalPriceCents: 1_100 * quantity, isPaid: true,
                         suspendedAmountCents: 0, subsidyCents: 0,
                         qrCode: ShareAllocator.qrCode(orderId: orderId, householdId: householdId),
                         isPickedUp: index == 1, pickedUpAt: index == 1 ? now.addingTimeInterval(-40 * 60) : nil)
        }
        let slots = data.pickupPoints.first { $0.id == ID.jarryPickup }?.slots ?? []
        data.groupOrders.append(GroupOrder(
            id: orderId, groupId: ID.villerayKitchen, offerId: ID.appleOffer, status: .delivered,
            currentTierIndex: 0, committedShares: shares.reduce(0) { $0 + $1.quantity },
            committedHouseholds: shares.count, pickupPointId: ID.jarryPickup, pickupSlots: slots
        ))
        data.shares[orderId] = shares
        return data
    }
}
