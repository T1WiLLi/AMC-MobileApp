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
}
