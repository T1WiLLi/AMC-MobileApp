// ImpactViewModel.swift
// F6 Impact (T-019) : économies du ménage et du quartier, familles, quantités, paniers suspendus.
// Tout est calculé à partir des commandes du groupe et de leurs parts (aucun chiffre en dur).

import Foundation
import Observation

@Observable
@MainActor
final class ImpactViewModel {
    /// Impact d'un produit (pour un graphique ou une liste par produit).
    nonisolated struct ProductImpact: Identifiable, Sendable, Hashable {
        var product: Product
        /// Parts engagées par le quartier.
        var shares: Int
        /// Kilos correspondants (0 si l'unité n'est pas en kg).
        var kilograms: Double
        /// Économie du quartier vs l'épicerie.
        var savingsCents: Cents

        var id: String { product.id }
    }

    nonisolated struct Content: Sendable, Hashable {
        /// Économie du ménage vs l'épicerie (« Tes économies »).
        var mySavingsCents: Cents
        /// Parts réservées par le ménage.
        var myShares: Int
        /// Économie de tout le groupe vs l'épicerie (« Quartier 3 900 $ »).
        var neighborhoodSavingsCents: Cents
        /// Ménages distincts ayant au moins une part.
        var householdCount: Int
        /// Parts engagées par le groupe.
        var totalShares: Int
        /// Nourriture achetée en groupe, en kg (« 1,2 t »).
        var totalKilograms: Double
        /// Parts qui financent un panier suspendu, et montant total offert.
        var suspendedBasketCount: Int
        var suspendedAmountCents: Cents
        /// Détail par produit, économie décroissante.
        var byProduct: [ProductImpact]
    }

    private(set) var state: LoadState<Content> = .idle

    private let repositories: AppRepositories
    private let householdId: String
    private let groupId: String

    init(repositories: AppRepositories, householdId: String, groupId: String) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
    }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, householdId = householdId, groupId = groupId
        state = await .run {
            try await Self.content(householdId: householdId, groupId: groupId, repositories: repositories)
        }
    }

    nonisolated private static func content(
        householdId: String, groupId: String, repositories: AppRepositories
    ) async throws -> Content {
        var content = Content(mySavingsCents: 0, myShares: 0, neighborhoodSavingsCents: 0, householdCount: 0,
                              totalShares: 0, totalKilograms: 0, suspendedBasketCount: 0, suspendedAmountCents: 0,
                              byProduct: [])
        var households: Set<String> = []
        var byProduct: [String: ProductImpact] = [:]

        let orders = try await repositories.groupOrders.groupOrders(ofGroup: groupId).filter { $0.status != .cancelled }
        // Lot, produit et parts de chaque commande en parallèle ; l'agrégat reste dans l'ordre des commandes.
        let loaded = try await withThrowingTaskGroup(of: (Int, Offer, Product, [Share]).self) { group in
            for (index, order) in orders.enumerated() {
                group.addTask {
                    async let sharesLoad = repositories.groupOrders.shares(ofGroupOrder: order.id)
                    let offer = try await repositories.offers.offer(id: order.offerId)
                    let product = try await repositories.vendors.product(id: offer.productId)
                    return (index, offer, product, try await sharesLoad)
                }
            }
            var results: [(Int, Offer, Product, [Share])] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }

        for (index, offer, product, shares) in loaded {
            let order = orders[index]
            let pricing = OfferPricing(offer: offer, product: product, committedShares: order.committedShares)
            let kilogramsPerShare = kilograms(in: offer.shareUnit)
            var impact = byProduct[product.id] ?? ProductImpact(product: product, shares: 0, kilograms: 0, savingsCents: 0)

            for share in shares where share.quantity > 0 {
                let savings = Self.savings(of: share, referenceUnitPriceCents: product.referenceGroceryPriceCents,
                                           currentUnitPriceCents: pricing.currentPriceCents)
                households.insert(share.householdId)
                content.totalShares += share.quantity
                content.neighborhoodSavingsCents += savings
                content.totalKilograms += kilogramsPerShare * Double(share.quantity)
                if share.suspendedAmountCents > 0 {
                    content.suspendedBasketCount += 1
                    content.suspendedAmountCents += share.suspendedAmountCents
                }
                if share.householdId == householdId {
                    content.mySavingsCents += savings
                    content.myShares += share.quantity
                }
                impact.shares += share.quantity
                impact.kilograms += kilogramsPerShare * Double(share.quantity)
                impact.savingsCents += savings
            }
            byProduct[product.id] = impact
        }
        content.householdCount = households.count
        content.byProduct = byProduct.values.sorted { $0.savingsCents > $1.savingsCents }
        return content
    }

    /// Économie d'une part vs l'épicerie, jamais négative.
    /// `Share.finalPriceCents` est le total figé à la clôture pour toute la part (quantité × prix unitaire,
    /// voir `ShareAllocator`) ; tant qu'il est nil, on prend le prix unitaire du palier courant × quantité.
    nonisolated static func savings(
        of share: Share, referenceUnitPriceCents: Cents, currentUnitPriceCents: Cents
    ) -> Cents {
        let quantity = max(0, share.quantity)
        let paidCents = share.finalPriceCents ?? currentUnitPriceCents * quantity
        return max(0, referenceUnitPriceCents * quantity - paidCents)
    }

    /// Kilos dans une unité de part : « sac de 10 kg » → 10, « 2,5 kg » → 2.5 ; 0 si pas de kg.
    nonisolated static func kilograms(in unit: String) -> Double {
        let words = unit.lowercased().split(separator: " ")
        guard let index = words.firstIndex(where: { $0 == "kg" || $0.hasSuffix("kg") }) else { return 0 }
        let word = words[index]
        let number = word == "kg" ? (index > 0 ? words[index - 1] : "") : word.dropLast(2)
        return Double(number.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
