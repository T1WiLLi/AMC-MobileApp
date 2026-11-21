// Offer.swift
// Collection `offers` (lots d'un vendeur, avec paliers de prix).

import Foundation

nonisolated struct Offer: Identifiable, Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable, CaseIterable {
        case draft
        case active
        case closed
        case cancelled
    }

    var id: String
    var vendorId: String
    var productId: String
    /// Nombre total de parts disponibles.
    var totalShares: Int
    /// Ce que contient une part : « 5 kg », « 1 caisse »…
    var shareUnit: String
    var tiers: [PriceTier]
    /// Parts à engager avant que la commande soit lancée.
    var minimumSharesToLaunch: Int
    var deadline: Date
    var zones: [String]
    var status: Status
}

nonisolated extension Offer {
    /// Paliers triés par seuil croissant.
    var sortedTiers: [PriceTier] { tiers.sorted { $0.minShares < $1.minShares } }

    /// Index (dans `sortedTiers`) du palier atteint avec `committedShares` parts, nil si aucun.
    func tierIndex(forCommittedShares committedShares: Int) -> Int? {
        sortedTiers.lastIndex { committedShares >= $0.minShares }
    }

    /// Prochain palier à atteindre, nil si le dernier est déjà atteint.
    func nextTier(afterCommittedShares committedShares: Int) -> PriceTier? {
        sortedTiers.first { committedShares < $0.minShares }
    }
}
