// OrderHistoryViewModel.swift
// Historique des commandes d'une famille (T-062, RQ-048) : commandes clôturées, livrées ou annulées
// où le ménage avait une part, la plus récente d'abord, avec prix final, total et économie.
// Usage : `OrderHistoryViewModel(repositories:householdId:)`, puis `await load()` dans `.task`.

import Foundation
import Observation

@Observable
@MainActor
final class OrderHistoryViewModel {
    /// Une commande terminée où le ménage avait une part.
    nonisolated struct Entry: Identifiable, Sendable, Hashable {
        var offer: Offer
        var product: Product
        var group: NeighborhoodGroup
        var groupOrder: GroupOrder
        var quantity: Int
        /// Prix final d'une part (figé à la clôture), nil si la commande a été annulée.
        var finalPriceCents: Cents?

        var id: String { groupOrder.id }
        var productName: String { product.name }
        var groupName: String { group.name }
        /// Date de clôture (date limite du lot), sert au tri.
        var closedAt: Date { offer.deadline }
        var status: GroupOrder.Status { groupOrder.status }
        var isCancelled: Bool { status == .cancelled }
        /// Total payé (0 si annulée).
        var totalCents: Cents { (finalPriceCents ?? 0) * quantity }
        /// Économie vs l'épicerie (0 si annulée).
        var savingsCents: Cents {
            guard let finalPriceCents else { return 0 }
            return max(0, product.referenceGroceryPriceCents - finalPriceCents) * quantity
        }
        /// « Confirmée », « Livrée » ou « Annulée ».
        var statusLabel: String { OrderHistoryViewModel.statusLabel(status) }
    }

    /// `.empty` si le ménage n'a aucune commande terminée.
    private(set) var state: LoadState<[Entry]> = .idle

    private let repositories: AppRepositories
    private let householdId: String

    init(repositories: AppRepositories, householdId: String) {
        self.repositories = repositories
        self.householdId = householdId
    }

    /// Économie totale sur l'historique (« 112 $ économisés depuis le début »).
    var totalSavingsCents: Cents { state.value?.reduce(0) { $0 + $1.savingsCents } ?? 0 }

    /// Charge (ou recharge) l'historique. Garde le contenu affiché pendant un rechargement.
    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, householdId = householdId
        do {
            state = .from(try await Self.entries(of: householdId, repositories: repositories))
        } catch {
            state = .failed(AppError(error))
        }
    }

    nonisolated static func statusLabel(_ status: GroupOrder.Status) -> String {
        switch status {
        case .open: "Ouverte"
        case .reached: "Palier atteint"
        case .closed: "Confirmée"
        case .delivered: "Livrée"
        case .cancelled: "Annulée"
        }
    }

    /// Commandes terminées : clôturée (confirmée), livrée ou annulée.
    nonisolated static func isFinished(_ order: GroupOrder) -> Bool {
        order.status == .closed || order.status == .delivered || order.status == .cancelled
    }

    /// Prix final : celui figé sur la part, sinon celui du palier atteint à la clôture ; nil si annulée.
    nonisolated static func finalPrice(share: Share, order: GroupOrder, offer: Offer) -> Cents? {
        guard order.status != .cancelled else { return nil }
        if let price = share.finalUnitPriceCents { return price }
        let tiers = offer.sortedTiers
        if let index = order.currentTierIndex, tiers.indices.contains(index) { return tiers[index].priceCents }
        if case .confirmed(_, let price) = TierEngine.closureOutcome(offer: offer, committedShares: order.committedShares) {
            return price
        }
        return nil
    }

    nonisolated static func entries(of householdId: String, repositories: AppRepositories) async throws -> [Entry] {
        var entries: [Entry] = []
        for group in try await repositories.groups.groups(ofHousehold: householdId) {
            for order in try await repositories.groupOrders.groupOrders(ofGroup: group.id) where isFinished(order) {
                let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id)
                guard let share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else { continue }
                let offer = try await repositories.offers.offer(id: order.offerId)
                let product = try await repositories.vendors.product(id: offer.productId)
                entries.append(Entry(
                    offer: offer, product: product, group: group, groupOrder: order, quantity: share.quantity,
                    finalPriceCents: finalPrice(share: share, order: order, offer: offer)
                ))
            }
        }
        return entries.sorted { ($0.closedAt, $0.id) > ($1.closedAt, $1.id) }
    }
}
