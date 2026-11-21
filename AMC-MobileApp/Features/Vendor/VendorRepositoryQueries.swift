// VendorRepositoryQueries.swift
// Requêtes composées du portail Vendeur (T-022), partagées par les ViewModels V1 à V3.
//
// Commandes de lots connus : `linkedGroupOrders(ofOffers:in:)` passe par `groupOrders(ofOffer:)` (T-033),
// groupes privés compris. Toutes les commandes (carte de la demande, tous lots) : `linkedGroupOrders(in:)`
// parcourt les groupes PUBLICS seulement.

import Foundation

/// Commande groupée accompagnée de son groupe de quartier.
nonisolated struct LinkedGroupOrder: Identifiable, Sendable, Hashable {
    var order: GroupOrder
    var group: NeighborhoodGroup

    var id: String { order.id }
}

nonisolated enum VendorRepositoryQueries {
    /// Commandes « vivantes » qui engagent encore de la demande.
    static let liveStatuses: Set<GroupOrder.Status> = [.open, .reached]

    /// Toutes les commandes groupées des groupes publics, avec leur groupe.
    /// `statuses` filtre les commandes (par défaut : toutes sauf annulées).
    static func linkedGroupOrders(
        in repositories: AppRepositories,
        statuses: Set<GroupOrder.Status> = Set(GroupOrder.Status.allCases).subtracting([.cancelled])
    ) async throws -> [LinkedGroupOrder] {
        let groups = try await repositories.groups.groups(inNeighborhood: nil)
        var result: [LinkedGroupOrder] = []
        for group in groups {
            let orders = try await repositories.groupOrders.groupOrders(ofGroup: group.id)
            result += orders
                .filter { statuses.contains($0.status) }
                .map { LinkedGroupOrder(order: $0, group: group) }
        }
        return result
    }

    /// Commandes groupées des lots donnés, avec leur groupe, groupes privés compris (T-033).
    /// Une commande dont le groupe n'existe plus est ignorée.
    static func linkedGroupOrders(
        ofOffers offerIds: some Sequence<String>,
        in repositories: AppRepositories,
        statuses: Set<GroupOrder.Status> = Set(GroupOrder.Status.allCases).subtracting([.cancelled])
    ) async throws -> [LinkedGroupOrder] {
        var groups: [String: NeighborhoodGroup] = [:]
        var result: [LinkedGroupOrder] = []
        for offerId in Set(offerIds) {
            for order in try await repositories.groupOrders.groupOrders(ofOffer: offerId) where statuses.contains(order.status) {
                let group: NeighborhoodGroup
                if let cached = groups[order.groupId] {
                    group = cached
                } else {
                    do {
                        group = try await repositories.groups.group(id: order.groupId)
                    } catch AppError.notFound {
                        continue
                    }
                    groups[group.id] = group
                }
                result.append(LinkedGroupOrder(order: order, group: group))
            }
        }
        return result.sorted { $0.order.id < $1.order.id }
    }

    /// Prix par part du palier atteint par la commande (`currentTierIndex` dans `offer.sortedTiers`), nil sous le premier palier.
    static func currentPrice(of order: GroupOrder, offer: Offer) -> Cents? {
        guard let index = order.currentTierIndex else { return nil }
        let tiers = offer.sortedTiers
        guard tiers.indices.contains(index) else { return nil }
        return tiers[index].priceCents
    }

    /// Revenu prévu d'une commande : parts engagées × prix du palier atteint (0 sous le premier palier).
    static func projectedRevenue(of order: GroupOrder, offer: Offer) -> Cents {
        guard let price = currentPrice(of: order, offer: offer) else { return 0 }
        return order.committedShares * price
    }
}
