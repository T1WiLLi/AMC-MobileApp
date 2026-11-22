import Foundation

/// Démo de la Cueillette par lieu (retour samuel) : avec `-demoPickupPlaces`, Amina a des parts à deux endroits.
/// - Cuisine collective de Villeray : riz basmati (Moulins du Nord), commande sans point choisi : elle se cueille
///   à la zone de livraison du groupe, le « Centre communautaire de Villeray » créé avec lui ;
/// - Saint-Michel : pommes de terre, chez Amina rue Jarry.
/// Sans l'argument, la démo du pitch reste telle quelle (Amina n'a encore rien réservé).
nonisolated extension FakeData {
    enum PickupPlacesDemoID {
        static let launchArgument = "-demoPickupPlaces"
        static let villerayZone = "pickup-group-villeray-prive"
        static let villerayRiceOrder = "order-villeray-riz-basmati"
    }

    /// `demo`, plus les parts d'Amina à deux lieux si l'app est lancée avec `-demoPickupPlaces`.
    static func demo(arguments: [String]) -> FakeData {
        var data = arguments.contains(PickupPlacesDemoID.launchArgument) ? demo.withPickupPlacesDemo() : demo
        if arguments.contains(HostDemoID.arrivalLaunchArgument) { data = data.withArrivalDemo() }
        return data
    }

    func withPickupPlacesDemo() -> FakeData {
        var data = self
        let orderId = PickupPlacesDemoID.villerayRiceOrder
        guard !data.groupOrders.contains(where: { $0.id == orderId }) else { return data }
        let saturday = Date.now.addingTimeInterval(3 * 86_400)
        data.pickupPoints.append(PickupPoint(
            id: PickupPlacesDemoID.villerayZone, hostUserId: "user-lucie-tremblay",
            name: "Centre communautaire de Villeray", address: "7378 rue Lajeunesse, Villeray, Montréal",
            photoURL: nil, capacity: PickupPoint.deliveryZoneCapacity,
            accessibility: [.wheelchair, .elevator, .nearMetro],
            slots: PickupSlotBook.consecutiveSlots(from: saturday.addingTimeInterval(3_600), count: 3, duration: 3_600,
                                                   capacity: 8),
            geohash: "f25du8", groupId: ID.villerayKitchen
        ))
        let neighbours = (1...3).map { "household-voisin-\($0)" }
        let riceShares = ([ID.aminaHousehold] + neighbours).enumerated().map { index, householdId in
            Share(householdId: householdId, quantity: index == 0 ? 1 : 2, finalPriceCents: nil, isPaid: false,
                  suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
        }
        let riceCommitted = riceShares.reduce(0) { $0 + $1.quantity }
        let riceOffer = data.offers.first { $0.id == ID.riceOffer }
        data.groupOrders.append(GroupOrder(
            id: orderId, groupId: ID.villerayKitchen, offerId: ID.riceOffer, status: .open,
            currentTierIndex: riceOffer?.tierIndex(forCommittedShares: riceCommitted), committedShares: riceCommitted,
            committedHouseholds: riceShares.count, pickupPointId: nil, pickupSlots: []
        ))
        data.shares[orderId] = riceShares
        // Pommes de terre à Saint-Michel, chez Amina (rue Jarry) : la part d'Amina fait franchir le palier de 20.
        if let index = data.groupOrders.firstIndex(where: { $0.id == ID.potatoOrder }) {
            data.shares[ID.potatoOrder, default: []].append(
                Share(householdId: ID.aminaHousehold, quantity: 1, finalPriceCents: nil, isPaid: false,
                      suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
            )
            var order = data.groupOrders[index]
            order.committedShares += 1
            order.committedHouseholds += 1
            if let offer = data.offers.first(where: { $0.id == order.offerId }) {
                order.currentTierIndex = offer.tierIndex(forCommittedShares: order.committedShares)
            }
            data.groupOrders[index] = order
        }
        return data
    }
}
