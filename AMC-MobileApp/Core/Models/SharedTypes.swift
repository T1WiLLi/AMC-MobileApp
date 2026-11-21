// SharedTypes.swift
// Petits types partagés par plusieurs collections.

import Foundation

/// Montants en cents (CAD) : entiers, donc pas d'erreur d'arrondi et encodables tels quels par Firestore.
typealias Cents = Int

/// Étiquettes alimentaires, utilisées pour les préférences d'un utilisateur et les produits.
nonisolated enum DietaryTag: String, Codable, Sendable, CaseIterable {
    case organic
    case halal
    case kosher
    case vegetarian
    case vegan
    case glutenFree
    case local
}

/// Créneau de cueillette.
nonisolated struct PickupSlot: Codable, Sendable, Hashable {
    var start: Date
    var end: Date
    /// Ménages au plus dans ce créneau (RQ-064) ; nil = sans limite.
    var capacity: Int? = nil
}

/// Palier de prix d'un lot : à partir de `minShares` parts engagées, chaque part coûte `priceCents`.
nonisolated struct PriceTier: Codable, Sendable, Hashable {
    var minShares: Int
    var priceCents: Cents
}
