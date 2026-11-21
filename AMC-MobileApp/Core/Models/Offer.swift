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
    /// Ce que contient une part (B-050) : contenant, poids, valeur. Texte affiché : `shareUnit`.
    var share: ShareSpec
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

// MARK: - Part (B-050)

nonisolated extension Offer {
    /// Texte d'une part : « sac de 10 kg ». Écrire une chaîne la relit en `ShareSpec`.
    var shareUnit: String {
        get { share.label }
        set { share = ShareSpec(parsing: newValue) }
    }

    /// Création à partir d'un texte de part (aperçus, tests, anciennes données).
    init(
        id: String, vendorId: String, productId: String, totalShares: Int, shareUnit: String,
        tiers: [PriceTier], minimumSharesToLaunch: Int, deadline: Date, zones: [String], status: Status
    ) {
        self.init(
            id: id, vendorId: vendorId, productId: productId, totalShares: totalShares,
            share: ShareSpec(parsing: shareUnit), tiers: tiers, minimumSharesToLaunch: minimumSharesToLaunch,
            deadline: deadline, zones: zones, status: status
        )
    }
}

// MARK: - Codable

nonisolated extension Offer {
    private enum CodingKeys: String, CodingKey {
        case id, vendorId, productId, totalShares, shareUnit, share, tiers, minimumSharesToLaunch, deadline, zones, status
    }

    /// Un document sans `share` (écrit avant B-050) relit `shareUnit`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let share = try container.decodeIfPresent(ShareSpec.self, forKey: .share)
            ?? ShareSpec(parsing: try container.decode(String.self, forKey: .shareUnit))
        self.init(
            id: try container.decode(String.self, forKey: .id),
            vendorId: try container.decode(String.self, forKey: .vendorId),
            productId: try container.decode(String.self, forKey: .productId),
            totalShares: try container.decode(Int.self, forKey: .totalShares),
            share: share,
            tiers: try container.decode([PriceTier].self, forKey: .tiers),
            minimumSharesToLaunch: try container.decode(Int.self, forKey: .minimumSharesToLaunch),
            deadline: try container.decode(Date.self, forKey: .deadline),
            zones: try container.decode([String].self, forKey: .zones),
            status: try container.decode(Status.self, forKey: .status)
        )
    }

    /// Écrit `share` et, pour les lecteurs existants (règles, scripts), `shareUnit` = son texte.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(vendorId, forKey: .vendorId)
        try container.encode(productId, forKey: .productId)
        try container.encode(totalShares, forKey: .totalShares)
        try container.encode(shareUnit, forKey: .shareUnit)
        try container.encode(share, forKey: .share)
        try container.encode(tiers, forKey: .tiers)
        try container.encode(minimumSharesToLaunch, forKey: .minimumSharesToLaunch)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(zones, forKey: .zones)
        try container.encode(status, forKey: .status)
    }
}
