// OfferSummary.swift
// Lot prêt à afficher (T-019) : lot + produit + vendeur + éventuelle commande du groupe + part du ménage.
// Utilisé par l'accueil (F1) et la fiche groupe (F2), par exemple pour remplir un `OfferCard`.

import Foundation

nonisolated struct OfferSummary: Identifiable, Sendable, Hashable {
    var offer: Offer
    var product: Product
    var vendor: Vendor
    /// Commande groupée du groupe sur ce lot, nil si le groupe ne l'a pas encore lancée.
    var groupOrder: GroupOrder?
    /// Parts réservées par le ménage dans `groupOrder` (0 si aucune).
    var myShareQuantity: Int

    var id: String { offer.id }

    /// Parts engagées par le groupe (0 sans commande).
    var committedShares: Int { groupOrder?.committedShares ?? 0 }
    /// Ménages engagés dans la commande du groupe (0 sans commande).
    var committedHouseholds: Int { groupOrder?.committedHouseholds ?? 0 }
    /// Prix, palier et économie pour les parts engagées.
    var pricing: OfferPricing { OfferPricing(offer: offer, product: product, committedShares: committedShares) }
    /// Le ménage a une part dans la commande.
    var hasMyShare: Bool { myShareQuantity > 0 }
}

/// Assemble des `OfferSummary` à partir des dépôts.
nonisolated enum OfferSummaryLoader {
    /// Une entrée par lot de `offers`, reliée à la commande du groupe sur ce lot s'il y en a une.
    /// `includeMyShares` : faux pour un ménage qui n'est pas membre du groupe (T-172) — les règles réservent
    /// `groupOrders/{id}/shares` aux membres, et un visiteur n'a de toute façon aucune part.
    static func summaries(
        for offers: [Offer],
        groupOrders: [GroupOrder],
        householdId: String,
        repositories: AppRepositories,
        includeMyShares: Bool = true
    ) async throws -> [OfferSummary] {
        var vendors: [String: Vendor] = [:]
        var result: [OfferSummary] = []
        for offer in offers {
            let product = try await repositories.vendors.product(id: offer.productId)
            let vendor: Vendor
            if let cached = vendors[offer.vendorId] {
                vendor = cached
            } else {
                vendor = try await repositories.vendors.vendor(id: offer.vendorId)
                vendors[offer.vendorId] = vendor
            }
            let order = groupOrders.first { $0.offerId == offer.id }
            var myQuantity = 0
            if let order, includeMyShares {
                myQuantity = try await shareQuantity(householdId: householdId, groupOrderId: order.id,
                                                     repositories: repositories)
            }
            result.append(OfferSummary(offer: offer, product: product, vendor: vendor,
                                       groupOrder: order, myShareQuantity: myQuantity))
        }
        return result
    }

    /// Parts du ménage dans une commande (0 s'il n'en a pas).
    static func shareQuantity(householdId: String, groupOrderId: String, repositories: AppRepositories) async throws -> Int {
        try await repositories.groupOrders.shares(ofGroupOrder: groupOrderId)
            .first { $0.householdId == householdId }?.quantity ?? 0
    }

    /// Commandes encore modifiables (ouvertes ou palier minimum atteint).
    static func isActive(_ order: GroupOrder) -> Bool {
        order.status == .open || order.status == .reached
    }

    /// Le lot dessert la zone du groupe : une zone du lot est un préfixe du geohash du groupe (ou l'inverse).
    static func offer(_ offer: Offer, serves group: NeighborhoodGroup) -> Bool {
        offer.zones.contains { group.centerGeohash.hasPrefix($0) || $0.hasPrefix(group.centerGeohash) }
    }
}
