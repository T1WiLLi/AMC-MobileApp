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
    /// T-159 : compte qui a créé le ménage ; lui seul accepte les demandes et retire des membres.
    /// Absent sur les ménages d'avant T-159 : le premier de `userIds` (`HouseholdMembership.ownerId`).
    var ownerId: String? = nil
    /// T-159 : clé d'adresse normalisée (`HouseholdAddress.key`), lisible par les membres seulement.
    var addressKey: String? = nil
    /// T-159 : nom affiché de chaque membre (uid → nom), pour « Récupéré par Amina » et la liste des membres.
    /// Les profils (`users/{uid}`) ne se lisent que par leur propriétaire : le ménage garde donc les noms.
    var memberNames: [String: String]? = nil
}

/// Document `households/{id}/private/profile`, lisible par le ménage et son organisme seulement.
nonisolated struct HouseholdPrivate: Codable, Sendable, Hashable {
    var isSubsidized: Bool
    var referralCode: String?
}
