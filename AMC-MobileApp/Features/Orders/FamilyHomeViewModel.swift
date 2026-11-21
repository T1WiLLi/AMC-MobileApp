// FamilyHomeViewModel.swift
// F1 Accueil d'une famille (T-019) : salutation, économies, commandes en cours du groupe, nouveaux lots.

import Foundation
import Observation

@Observable
@MainActor
final class FamilyHomeViewModel {
    /// Tout ce que montre l'écran F1.
    nonisolated struct Content: Sendable, Hashable {
        var user: AppUser
        var group: NeighborhoodGroup
        /// Commandes du groupe encore ouvertes ; celles où le ménage a une part d'abord.
        var currentOrders: [OfferSummary]
        /// Lots actifs qui desservent la zone du groupe et que le groupe n'a pas encore lancés.
        var newOffers: [OfferSummary]
        /// Économie du ménage vs l'épicerie sur toutes ses parts dans le groupe (« 48 $ économisés »).
        var savedCents: Cents

        /// « Amina » pour « Bonjour Amina ».
        var firstName: String { user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName }
        /// Commandes où le ménage a une part (« Ta commande en cours »).
        var myOrders: [OfferSummary] { currentOrders.filter(\.hasMyShare) }
    }

    private(set) var state: LoadState<Content> = .idle

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String
    private let groupId: String

    init(repositories: AppRepositories, userId: String, householdId: String, groupId: String) {
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
        self.groupId = groupId
    }

    /// Charge (ou recharge) l'écran. Garde le contenu affiché pendant un rechargement (pull-to-refresh).
    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, userId = userId, householdId = householdId, groupId = groupId
        state = await .run {
            let user = try await repositories.users.user(id: userId)
            let group = try await repositories.groups.group(id: groupId)
            let orders = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
            let activeOrders = orders.filter(OfferSummaryLoader.isActive)

            var orderOffers: [Offer] = []
            for order in activeOrders {
                orderOffers.append(try await repositories.offers.offer(id: order.offerId))
            }
            let current = try await OfferSummaryLoader.summaries(
                for: orderOffers, groupOrders: activeOrders, householdId: householdId, repositories: repositories
            )

            let launchedOfferIds = Set(orders.map(\.offerId))
            let feed = try await repositories.offers.activeOffers(inZone: nil)
                .filter { OfferSummaryLoader.offer($0, serves: group) && !launchedOfferIds.contains($0.id) }
            let newOffers = try await OfferSummaryLoader.summaries(
                for: feed, groupOrders: [], householdId: householdId, repositories: repositories
            )

            let saved = try await Self.savings(of: householdId, in: orders, repositories: repositories)
            return Content(
                user: user,
                group: group,
                currentOrders: current.filter(\.hasMyShare) + current.filter { !$0.hasMyShare },
                newOffers: newOffers,
                savedCents: saved
            )
        }
    }

    /// Économie du ménage sur toutes ses parts (prix final si figé, sinon prix du palier courant).
    nonisolated static func savings(
        of householdId: String, in orders: [GroupOrder], repositories: AppRepositories
    ) async throws -> Cents {
        var total: Cents = 0
        for order in orders where order.status != .cancelled {
            let shares = try await repositories.groupOrders.shares(ofGroupOrder: order.id)
            guard let share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else { continue }
            let offer = try await repositories.offers.offer(id: order.offerId)
            let product = try await repositories.vendors.product(id: offer.productId)
            let price = share.finalUnitPriceCents
                ?? OfferPricing(offer: offer, product: product, committedShares: order.committedShares).currentPriceCents
            total += max(0, product.referenceGroceryPriceCents - price) * share.quantity
        }
        return total
    }
}
