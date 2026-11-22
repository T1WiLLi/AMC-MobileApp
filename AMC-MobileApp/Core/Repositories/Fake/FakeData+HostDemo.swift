import Foundation

/// Démo de l'écran hôte (T-181) : dans l'app en mode fake, une commande est déjà livrée chez Amina pour que
/// « Remettre les parts » montre des ménages à servir, et une autre est fermée (en route) pour qu'Amina, hôte et
/// coordonnatrice, puisse la « Marquer comme arrivée ». `montreal` (tests) reste sans elles : ses chiffres de
/// vendeurs et de commandes ne bougent pas.
/// Avec `-demoArrival`, Amina a aussi une part dans la commande en route : sa Cueillette passe de « En route » à
/// « Arrivée ! Viens la chercher » quand elle la marque arrivée.
nonisolated extension FakeData {
    enum HostDemoID {
        /// Pommes Cortland de la cuisine collective de Villeray, livrées chez Amina (rue Jarry).
        static let deliveredOrder = "order-villeray-pommes-cortland"
        /// Pommes de terre de la cuisine collective de Villeray : fermée, en route vers chez Amina.
        static let onTheWayOrder = "order-villeray-pommes-de-terre"
        /// Ajoute la part d'Amina dans la commande en route (Cueillette « En route », puis « Arrivée ! »).
        static let arrivalLaunchArgument = "-demoArrival"
    }

    /// `montreal` + la commande livrée chez Amina. Utilisé par `AppContext.demo`, le mode fake et « Réinitialiser la démo ».
    static let demo: FakeData = montreal.withHostDemoOrder()

    /// Ajoute la commande de pommes livrée chez Amina : Voisins 1 (2 parts) et Voisins 3 attendus, Voisins 2 déjà passé.
    func withHostDemoOrder(now: Date = .now) -> FakeData {
        var data = self
        let orderId = HostDemoID.deliveredOrder
        guard !data.groupOrders.contains(where: { $0.id == orderId }) else { return data }
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
        return data.withOnTheWayOrder()
    }

    /// Commande de pommes de terre fermée, pas encore arrivée chez Amina : Voisins 1, 2 et 3 attendent.
    func withOnTheWayOrder() -> FakeData {
        var data = self
        let orderId = HostDemoID.onTheWayOrder
        guard !data.groupOrders.contains(where: { $0.id == orderId }),
              let offer = data.offers.first(where: { $0.id == ID.potatoOffer }) else { return data }
        let quantities = [("household-voisin-1", "Voisins 1", 4), ("household-voisin-2", "Voisins 2", 3),
                          ("household-voisin-3", "Voisins 3", 5)]
        let committed = quantities.reduce(0) { $0 + $1.2 }
        let tierIndex = offer.tierIndex(forCommittedShares: committed)
        let unitPrice = tierIndex.map { offer.sortedTiers[$0].priceCents } ?? 0
        let shares = quantities.map { householdId, name, quantity in
            Share(householdId: householdId, quantity: quantity, finalPriceCents: unitPrice * quantity, isPaid: true,
                  suspendedAmountCents: 0, subsidyCents: 0,
                  qrCode: ShareAllocator.qrCode(orderId: orderId, householdId: householdId),
                  isPickedUp: false, householdName: name)
        }
        let slots = data.pickupPoints.first { $0.id == ID.jarryPickup }?.slots ?? []
        data.groupOrders.append(GroupOrder(
            id: orderId, groupId: ID.villerayKitchen, offerId: ID.potatoOffer, status: .closed,
            currentTierIndex: tierIndex, committedShares: committed, committedHouseholds: shares.count,
            pickupPointId: ID.jarryPickup, pickupSlots: slots
        ))
        data.shares[orderId] = shares
        return data
    }

    /// `-demoArrival` : la part d'Amina (1 sac, payée) dans la commande en route.
    func withArrivalDemo() -> FakeData {
        var data = withOnTheWayOrder()
        let orderId = HostDemoID.onTheWayOrder
        guard let index = data.groupOrders.firstIndex(where: { $0.id == orderId }),
              !data.shares[orderId, default: []].contains(where: { $0.householdId == ID.aminaHousehold }),
              let offer = data.offers.first(where: { $0.id == ID.potatoOffer }) else { return data }
        var order = data.groupOrders[index]
        order.committedShares += 1
        order.committedHouseholds += 1
        order.currentTierIndex = offer.tierIndex(forCommittedShares: order.committedShares)
        let unitPrice = order.currentTierIndex.map { offer.sortedTiers[$0].priceCents } ?? 0
        data.groupOrders[index] = order
        data.shares[orderId, default: []].append(Share(
            householdId: ID.aminaHousehold, quantity: 1, finalPriceCents: unitPrice, isPaid: true,
            suspendedAmountCents: 0, subsidyCents: 0,
            qrCode: ShareAllocator.qrCode(orderId: orderId, householdId: ID.aminaHousehold),
            isPickedUp: false, householdName: "Famille Benali"
        ))
        return data
    }
}
