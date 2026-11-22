// PickupPoint.swift
// Collection `pickupPoints`.

import Foundation

nonisolated struct PickupPoint: Identifiable, Codable, Sendable, Hashable {
    enum Accessibility: String, Codable, Sendable, CaseIterable {
        case wheelchair
        case stepFree
        case elevator
        case nearMetro
        case parking
    }

    var id: String
    var hostUserId: String
    var name: String
    var address: String
    var photoURL: URL?
    /// Nombre de parts que l'hôte peut garder en même temps.
    var capacity: Int
    var accessibility: [Accessibility]
    var slots: [PickupSlot]
    /// Position approximative du point (geohash de 6 ou 7 caractères, jamais l'adresse exacte), pour la carte
    /// des familles (T-091). nil : le point n'apparaît pas sur la carte.
    var geohash: String? = nil
    /// Groupe dont c'est la zone de livraison (posé à la création du groupe, immuable ensuite dans
    /// `firestore.rules`) : le vendeur y livre et les familles du groupe y cueillent. nil : point d'un hôte
    /// sans groupe attitré.
    var groupId: String? = nil
}

nonisolated extension PickupPoint {
    /// Zone de livraison d'un groupe : le point créé avec lui, nil s'il n'en a pas.
    static func deliveryZone(ofGroup groupId: String, in points: [PickupPoint]) -> PickupPoint? {
        points.filter { $0.groupId == groupId }.min { $0.id < $1.id }
    }

    /// Point où cueillir une commande : celui choisi par le coordonnateur, sinon la zone de livraison du groupe.
    static func resolvedId(for order: GroupOrder, in points: [PickupPoint]) -> String? {
        if let id = order.pickupPointId, !id.isEmpty { return id }
        return deliveryZone(ofGroup: order.groupId, in: points)?.id
    }

    /// Point de cueillette créé avec un groupe (zone de livraison) : capacité d'une salle communautaire,
    /// accessibilité et créneaux à préciser ensuite par l'hôte ou le coordonnateur.
    static func deliveryZone(
        forGroup groupId: String, hostUserId: String, name: String, address: String, geohash: String?
    ) -> PickupPoint {
        PickupPoint(id: "pickup-\(groupId)", hostUserId: hostUserId, name: name, address: address, photoURL: nil,
                    capacity: deliveryZoneCapacity, accessibility: [], slots: [], geohash: geohash, groupId: groupId)
    }

    /// Parts gardées en même temps par défaut dans la zone de livraison d'un groupe.
    static let deliveryZoneCapacity = 50
}
