// Household.swift
// Collection `households` et sa sous-collection privée `households/{id}/private`.

import Foundation

nonisolated struct Household: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var name: String
    /// Nombre de personnes dans le ménage.
    var size: Int
    /// Adresse approximative : geohash tronqué, jamais l'adresse exacte.
    var geohash: String
    var userIds: [String]
}

/// Document `households/{id}/private/profile`, lisible par le ménage et son organisme seulement.
nonisolated struct HouseholdPrivate: Codable, Sendable, Hashable {
    var isSubsidized: Bool
    var referralCode: String?
}
