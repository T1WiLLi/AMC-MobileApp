// VendorDashboardViewModel.swift
// V1 Tableau de bord vendeur (T-022) : lots actifs, parts engagées, palier, revenus prévus, lots qui ferment bientôt.
//
// Usage dans une vue :
//   @State private var model = VendorDashboardViewModel(repositories: context.repositories, vendorId: context.vendorId)
//   .task { await model.load() }  ·  .refreshable { await model.refresh() }
//   switch model.state { case .loaded(let dashboard): … }

import Foundation
import Observation

@Observable @MainActor
final class VendorDashboardViewModel {
    /// Un lot actif du vendeur, agrégé sur toutes ses commandes groupées.
    nonisolated struct OfferSummary: Identifiable, Sendable, Hashable {
        var offer: Offer
        /// Produit du lot ; nil s'il est introuvable.
        var product: Product?
        /// Commandes groupées liées au lot (hors annulées), triées par parts décroissantes.
        var linkedOrders: [LinkedGroupOrder]
        /// Parts engagées, toutes commandes confondues.
        var committedShares: Int
        /// Ménages engagés, toutes commandes confondues.
        var committedHouseholds: Int
        /// Meilleur palier atteint parmi les commandes (index dans `offer.sortedTiers`), nil si aucun.
        var bestTierIndex: Int?
        /// Revenu prévu : somme, par commande, du revenu de ses parts (prix figé, sinon prix du palier atteint).
        var projectedRevenueCents: Cents
        /// Vrai si la date limite tombe dans la fenêtre « bientôt » du ViewModel.
        var isClosingSoon: Bool
        /// Revenu de chaque commande (id → cents), calculé depuis ses parts (T-129).
        var revenueByOrder: [String: Cents] = [:]

        /// Revenu d'une commande du lot : celui de ses parts, sinon parts engagées × prix du palier.
        func revenue(of linked: LinkedGroupOrder) -> Cents {
            revenueByOrder[linked.order.id] ?? VendorRepositoryQueries.projectedRevenue(of: linked.order, offer: offer)
        }

        /// T-196 : commandes encore ouvertes (`open` ou `reached`), celles que « Fermer la commande » ferme.
        var liveOrders: [LinkedGroupOrder] { linkedOrders.filter { TierEngine.isOpen($0.order) } }
        /// T-196 : ouvert, fermé en préparation ou livré, d'après toutes les commandes du lot.
        var phase: OrderPhase { .aggregate(offer: offer.status, orders: linkedOrders.map(\.order.status)) }
        /// T-196 : ce que la fermeture va faire, pour la confirmation.
        var closureImpact: ClosureImpact { ClosureImpact(offer: offer, liveOrders: liveOrders.map(\.order)) }

        var id: String { offer.id }
        var totalShares: Int { offer.totalShares }
        /// Remplissage du lot, de 0 à 1.
        var fillFraction: Double {
            offer.totalShares > 0 ? min(1, Double(committedShares) / Double(offer.totalShares)) : 0
        }
        /// Meilleur palier atteint.
        var bestTier: PriceTier? { bestTierIndex.map { offer.sortedTiers[$0] } }
        /// Numéro lisible du meilleur palier (« Palier 2 »), nil si aucun.
        var bestTierNumber: Int? { bestTierIndex.map { $0 + 1 } }
        /// Nom du produit, ou l'unité de part à défaut.
        var title: String { product?.name ?? offer.shareUnit }
    }

    /// T-196 : effet de la fermeture d'un lot, groupe par groupe (chaque commande ferme à son propre palier,
    /// `TierEngine.closureOutcome`) : prix figés, familles débitées au pot, commandes annulées sous le minimum.
    nonisolated struct ClosureImpact: Sendable, Equatable {
        /// Commandes confirmées (prix figé au palier atteint).
        var confirmedOrders = 0
        /// Commandes sous le minimum de lancement : annulées, personne n'est débité.
        var cancelledOrders = 0
        /// Familles qui paient leur part au pot (commandes confirmées).
        var payingHouseholds = 0
        /// Familles dont la commande est annulée.
        var cancelledHouseholds = 0
        var lowestPriceCents: Cents?
        var highestPriceCents: Cents?

        init(offer: Offer, liveOrders: [GroupOrder]) {
            for order in liveOrders {
                switch TierEngine.closureOutcome(offer: offer, committedShares: order.committedShares) {
                case .confirmed(_, let price):
                    confirmedOrders += 1
                    payingHouseholds += order.committedHouseholds
                    lowestPriceCents = min(lowestPriceCents ?? price, price)
                    highestPriceCents = max(highestPriceCents ?? price, price)
                case .cancelled:
                    cancelledOrders += 1
                    cancelledHouseholds += order.committedHouseholds
                }
            }
        }

        /// Message de la confirmation : prix figé, paiement au pot, familles concernées.
        @MainActor func message(shareUnit: String) -> String {
            guard confirmedOrders > 0, let low = lowestPriceCents, let high = highestPriceCents else {
                return String(localized: "Le minimum n'est pas atteint : la commande sera annulée et aucune famille ne sera débitée.")
            }
            let families = FrenchPlural.count(payingHouseholds, "famille")
            var text: String
            if low == high {
                text = String(localized: "Le prix est figé à \(Money.format(low)) par \(shareUnit), le palier atteint. Les parts de \(families) seront payées au pot du groupe. Elles ne pourront plus changer.")
            } else {
                text = String(localized: "Le prix est figé au palier atteint par chaque groupe, de \(Money.format(low)) à \(Money.format(high)) par \(shareUnit). Les parts de \(families) seront payées au pot du groupe. Elles ne pourront plus changer.")
            }
            if cancelledOrders > 0 {
                text += " " + String(localized: "Les commandes sous le minimum (\(cancelledOrders)) seront annulées, sans débit.")
            }
            return text
        }

        /// Titre du bouton de confirmation.
        var confirmTitle: String {
            if confirmedOrders > 0 { return String(localized: "Fermer et débiter les familles") }
            return String(localized: "Fermer et annuler")
        }
    }

    /// Contenu du tableau de bord.
    nonisolated struct Dashboard: Sendable, Hashable {
        /// Lots actifs, par date limite croissante.
        var offers: [OfferSummary]

        var totalCommittedShares: Int { offers.reduce(0) { $0 + $1.committedShares } }
        var totalShares: Int { offers.reduce(0) { $0 + $1.totalShares } }
        /// Familles engagées (somme des ménages par commande).
        var committedHouseholds: Int { offers.reduce(0) { $0 + $1.committedHouseholds } }
        var projectedRevenueCents: Cents { offers.reduce(0) { $0 + $1.projectedRevenueCents } }
        /// Lots qui ferment bientôt, par date limite croissante.
        var closingSoon: [OfferSummary] { offers.filter(\.isClosingSoon) }
        /// Commande ayant atteint le palier le plus haut (pour le bandeau « Palier 3 atteint à … »), nil si aucune.
        var highlight: Highlight? {
            var best: Highlight?
            for summary in offers {
                for linked in summary.linkedOrders {
                    guard let tier = linked.order.currentTierIndex else { continue }
                    if tier > (best?.tierIndex ?? -1) { best = Highlight(offer: summary, order: linked, tierIndex: tier) }
                }
            }
            return best
        }
    }

    /// Bandeau « Palier 3 atteint à Parc-Ex Ouest ».
    nonisolated struct Highlight: Sendable, Hashable {
        var offer: OfferSummary
        var order: LinkedGroupOrder
        /// Index du palier atteint dans `offer.offer.sortedTiers`.
        var tierIndex: Int

        var tierNumber: Int { tierIndex + 1 }
        var groupName: String { order.group.name }
    }

    /// `.empty` si le vendeur n'a aucun lot actif.
    private(set) var state: LoadState<Dashboard> = .idle

    let vendorId: String
    /// T-196 : compte du vendeur connecté, pour « Fermer la commande » (vide : le bouton reste caché).
    let userId: String
    /// T-196 : lot en cours de fermeture (indicateur sur le bouton).
    private(set) var closingOfferId: String?
    /// T-196 : dernière fermeture refusée ou échouée ; remise à nil au début de chaque fermeture.
    var closeError: AppError?
    /// T-196 : incrémenté à chaque fermeture réussie (déclencheur de l'haptique de succès).
    private(set) var closeSuccessCount = 0
    private var vendorUser: AppUser?
    /// Fenêtre « ferme bientôt » (72 h par défaut).
    let closingSoonInterval: TimeInterval

    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    init(
        repositories: AppRepositories,
        vendorId: String,
        userId: String = "",
        closingSoonInterval: TimeInterval = 72 * 3_600,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.userId = userId
        self.closingSoonInterval = closingSoonInterval
        self.now = now
    }

    /// Charge le tableau de bord en passant par `.loading`.
    func load() async {
        state = .loading
        await refresh()
    }

    /// Recharge sans repasser par `.loading` (pour `.refreshable`).
    func refresh() async {
        await loadVendorUser()
        do {
            let dashboard = try await fetchDashboard()
            state = dashboard.offers.isEmpty ? .empty : .loaded(dashboard)
        } catch {
            state = .failed(AppError(error))
        }
    }

    // MARK: Fermer la commande (T-196)

    /// Profil du vendeur connecté ; une lecture ratée cache simplement le bouton.
    private func loadVendorUser() async {
        guard vendorUser == nil, !userId.isEmpty else { return }
        vendorUser = try? await repositories.users.user(id: userId)
    }

    /// Le bouton « Fermer la commande » est visible : au moins une commande du lot est ouverte et
    /// `ClosurePolicy.canClose` autorise ce vendeur (le lot est le sien).
    func canClose(_ summary: OfferSummary) -> Bool {
        guard let vendorUser else { return false }
        return summary.liveOrders.contains {
            ClosurePolicy.canClose(user: vendorUser, membership: nil, offer: summary.offer, order: $0.order)
        }
    }

    func isClosing(_ summary: OfferSummary) -> Bool { closingOfferId == summary.id }

    /// Ferme toutes les commandes ouvertes du lot (même appel que la fermeture côté famille :
    /// `closeGroupOrder(trigger: .manual)`), puis relit la liste. Une commande déjà fermée ailleurs est ignorée.
    func closeOffer(offerId: String) async {
        guard closingOfferId == nil, let summary = state.value?.offers.first(where: { $0.id == offerId }),
              canClose(summary), let vendorUser else { return }
        closeError = nil
        closingOfferId = offerId
        defer { closingOfferId = nil }
        var failure: AppError?
        for linked in summary.liveOrders {
            do {
                try await repositories.groupOrders.closeGroupOrder(
                    id: linked.order.id, trigger: .manual(user: vendorUser, membership: nil)
                )
            } catch AppError.orderClosed {
                continue
            } catch {
                failure = AppError(error)
                break
            }
        }
        await refresh()
        if let failure {
            closeError = failure
        } else {
            closeSuccessCount += 1
        }
    }

    private func fetchDashboard() async throws -> Dashboard {
        let offers = try await repositories.offers.offers(ofVendor: vendorId).filter { $0.status == .active }
        guard !offers.isEmpty else { return Dashboard(offers: []) }

        let products = try await repositories.vendors.products(ofVendor: vendorId)
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let offerIds = Set(offers.map(\.id))
        let linked = try await VendorRepositoryQueries.linkedGroupOrders(ofOffers: offerIds, in: repositories)
        let ordersByOffer = Dictionary(grouping: linked, by: \.order.offerId)
        let offersById = Dictionary(offers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let revenueByOrder = await Self.revenueByOrder(linked, offers: offersById, repositories: repositories)
        let currentDate = now()

        let summaries = offers.map { offer in
            let orders = (ordersByOffer[offer.id] ?? []).sorted { $0.order.committedShares > $1.order.committedShares }
            let tierCount = offer.tiers.count
            let remaining = offer.deadline.timeIntervalSince(currentDate)
            return OfferSummary(
                offer: offer,
                product: productsById[offer.productId],
                linkedOrders: orders,
                committedShares: orders.reduce(0) { $0 + $1.order.committedShares },
                committedHouseholds: orders.reduce(0) { $0 + $1.order.committedHouseholds },
                bestTierIndex: orders.compactMap(\.order.currentTierIndex).filter { $0 < tierCount }.max(),
                projectedRevenueCents: orders.reduce(0) { total, linked in
                    total + (revenueByOrder[linked.order.id]
                        ?? VendorRepositoryQueries.projectedRevenue(of: linked.order, offer: offer))
                },
                isClosingSoon: remaining > 0 && remaining <= closingSoonInterval,
                revenueByOrder: revenueByOrder.filter { id, _ in orders.contains { $0.order.id == id } }
            )
        }
        return Dashboard(offers: summaries.sorted { $0.offer.deadline < $1.offer.deadline })
    }

    /// Revenu de chaque commande depuis ses parts, lues en parallèle. Une commande dont les parts ne se lisent pas
    /// (réseau, droits) est absente du résultat : on retombe alors sur parts engagées × prix du palier.
    private static func revenueByOrder(
        _ linked: [LinkedGroupOrder], offers: [String: Offer], repositories: AppRepositories
    ) async -> [String: Cents] {
        await withTaskGroup(of: (String, Cents)?.self) { group in
            for item in linked {
                guard let offer = offers[item.order.offerId] else { continue }
                group.addTask {
                    guard let shares = try? await repositories.groupOrders.shares(ofGroupOrder: item.order.id) else { return nil }
                    return (item.order.id, VendorRepositoryQueries.revenue(of: item.order, offer: offer, shares: shares))
                }
            }
            var result: [String: Cents] = [:]
            for await entry in group {
                if let entry { result[entry.0] = entry.1 }
            }
            return result
        }
    }
}
