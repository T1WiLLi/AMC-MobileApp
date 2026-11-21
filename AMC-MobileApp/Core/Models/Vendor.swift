// Vendor.swift
// Collection `vendors`.

import Foundation

nonisolated struct Vendor: Identifiable, Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case farm
        case wholesaler
        case cooperative
        case bakery
        case other
    }

    var id: String
    var legalName: String
    var kind: Kind
    var description: String
    var photoURLs: [URL]
    /// Quartiers ou geohash desservis.
    var servedZones: [String]
    /// Note moyenne sur 5 ; nil tant qu'il n'y a aucun avis.
    var averageRating: Double?
    var isVerified: Bool
    /// Comptoir ou kiosque du producteur en ville (marché, entrepôt), en geohash, pour la carte des familles (T-091).
    /// nil : le producteur ne vend qu'aux points de cueillette et n'apparaît pas sur la carte.
    var storefrontGeohash: String? = nil
}
