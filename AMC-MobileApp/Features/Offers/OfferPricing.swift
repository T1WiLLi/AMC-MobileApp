// OfferPricing.swift
// Calculs de prix d'un lot (T-019) : palier courant, prochain palier, économie vs épicerie.
// Tous les montants sont par part (`Offer.shareUnit`), en cents.

import Foundation

/// Prix d'un lot pour un nombre de parts engagées. Valeur pure, partagée par les ViewModels Familles.
nonisolated struct OfferPricing: Sendable, Hashable {
    /// Paliers triés par seuil croissant.
    let tiers: [PriceTier]
    /// Parts engagées par le groupe.
    let committedShares: Int
    /// Prix d'épicerie de référence pour une part (`Product.referenceGroceryPriceCents`).
    let groceryPriceCents: Cents

    init(tiers: [PriceTier], committedShares: Int, groceryPriceCents: Cents) {
        self.tiers = tiers.sorted { $0.minShares < $1.minShares }
        self.committedShares = committedShares
        self.groceryPriceCents = groceryPriceCents
    }

    init(offer: Offer, product: Product, committedShares: Int) {
        self.init(tiers: offer.tiers, committedShares: committedShares,
                  groceryPriceCents: product.referenceGroceryPriceCents)
    }

    /// Même calcul pour un autre nombre de parts (ex. avec la part qu'on s'apprête à réserver).
    func with(committedShares: Int) -> OfferPricing {
        OfferPricing(tiers: tiers, committedShares: committedShares, groceryPriceCents: groceryPriceCents)
    }

    /// Index du palier atteint dans `tiers`, nil sous le premier palier.
    var tierIndex: Int? { tiers.lastIndex { committedShares >= $0.minShares } }

    /// Numéro du palier atteint (1 = premier), 0 sous le premier palier. Pour « Palier 2 sur 3 ».
    var tierNumber: Int { tierIndex.map { $0 + 1 } ?? 0 }

    var tierCount: Int { tiers.count }

    /// Palier atteint, nil sous le premier palier.
    var currentTier: PriceTier? { tierIndex.map { tiers[$0] } }

    /// Prix d'une part : celui du palier atteint, sinon celui du premier palier (prix de départ).
    var currentPriceCents: Cents { currentTier?.priceCents ?? tiers.first?.priceCents ?? groceryPriceCents }

    /// Prochain palier à atteindre, nil si le dernier est atteint.
    var nextTier: PriceTier? { tiers.first { committedShares < $0.minShares } }

    /// Parts manquantes pour le prochain palier, nil si le dernier est atteint.
    var sharesToNextTier: Int? { nextTier.map { $0.minShares - committedShares } }

    /// Baisse du prix au prochain palier, en % du prix courant (19 pour « débloquer −19 % »).
    var nextTierDiscountPercent: Int? {
        nextTier.map { Self.percentOff(price: $0.priceCents, reference: currentPriceCents) }
    }

    /// Économie d'une part vs l'épicerie, en %, arrondie (37 pour « −37 % vs épicerie »).
    var savingsPercent: Int { Self.percentOff(price: currentPriceCents, reference: groceryPriceCents) }

    /// Économie d'une part vs l'épicerie, en cents (jamais négative).
    var savingsPerShareCents: Cents { max(0, groceryPriceCents - currentPriceCents) }

    /// Total à payer pour `shares` parts au prix courant.
    func totalCents(forShares shares: Int) -> Cents { currentPriceCents * shares }

    /// Économie totale vs l'épicerie pour `shares` parts au prix courant.
    func savingsCents(forShares shares: Int) -> Cents { savingsPerShareCents * shares }

    /// Même règle que `Money.savingsPercent`, recopiée ici car `Money` est isolé MainActor (Core) et ce type est nonisolated.
    static func percentOff(price: Cents, reference: Cents) -> Int {
        guard reference > 0, price < reference else { return 0 }
        return Int((Double(reference - price) / Double(reference) * 100).rounded())
    }
}
