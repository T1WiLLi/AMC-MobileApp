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
    /// Ville du producteur (« Mirabel »), affichée sur sa page publique (T-157). Posée par le seed, pas par le client.
    var city: String? = nil
    /// Arrivée sur LeGrenier, pour l'ancienneté affichée aux familles (T-157). Posée par le seed, pas par le client.
    var memberSince: Date? = nil
    /// Produits mis en avant sur la vitrine (T-157), dans l'ordre choisi ; modifiable par le vendeur. nil = aucun.
    var featuredProductIds: [String]? = nil
    /// Compte propriétaire (`users/{uid}`) d'un vendeur créé depuis l'app (onboarding producteur, T-158).
    /// nil pour les vendeurs du seed. firestore.rules : posé à la création, jamais modifié par le client.
    var ownerId: String? = nil
    /// Catégories de produits annoncées à l'onboarding (T-158). nil pour les vendeurs du seed.
    var productCategories: [Product.Category]? = nil

    /// Id du vendeur créé par un compte : un seul par compte (firestore.rules l'exige).
    static func ownedId(forUserId userId: String) -> String { "vendor-\(userId)" }
}
