// BoroughStats.swift
// Collection `boroughStats/{boroughId}` (RQ-093, T-114) : agrégats d'un arrondissement de Montréal,
// en lecture seule pour l'app. Remplie par le seed (ou un script d'administration), jamais par un client :
// aucune donnée personnelle, seulement des totaux. Le classement est calculé côté client
// par `SolidarityLeaderboard`.

import Foundation

nonisolated struct BoroughStats: Identifiable, Codable, Sendable, Hashable {
    /// Identifiant stable, en minuscules : « villeray-saint-michel-parc-extension ».
    var id: String
    /// Nom affiché : « Villeray–Saint-Michel–Parc-Extension ».
    var name: String
    /// Nom court pour les puces et le podium : « Saint-Michel ».
    var shortName: String
    /// Quartiers (`NeighborhoodGroup.neighborhood`) rattachés à l'arrondissement, pour retrouver le sien.
    var neighborhoods: [String]
    /// Centre approximatif (geohash court), pour la carte.
    var centerGeohash: String
    /// Ménages inscrits dans les groupes de l'arrondissement.
    var households: Int
    /// Ménages qui ont pris au moins une part sur la période.
    var activeHouseholds: Int
    /// Groupes de quartier actifs.
    var groupCount: Int
    /// Paniers suspendus offerts sur la période.
    var basketsOffered: Int
    /// Familles aidées par un panier suspendu ou le fonds de solidarité.
    var familiesHelped: Int
    /// Économies totales des ménages par rapport à l'épicerie.
    var savingsCents: Cents
    /// Dernier calcul de l'agrégat ; nil dans les données anciennes.
    var updatedAt: Date? = nil
}

nonisolated extension FirestoreCollection {
    /// Agrégats par arrondissement, lecture seule (RQ-093).
    static let boroughStats = "boroughStats"
}
