// VendorRevenueModel.swift
// Onglet Revenus du portail Vendeur (T-037) : lit `VendorDashboardViewModel` (sans le modifier)
// et ajoute les points de cueillette pour les prochaines livraisons.
//
// Usage :
//   @State private var model = VendorRevenueModel(repositories: context.repositories, vendorId: context.vendorId)
//   .task { await model.load() }  ·  .refreshable { await model.refresh() }
//   StateView(state: model.state) { revenue in … }

import Foundation
import Observation

/// Revenus d'un vendeur, prêts à afficher : total, par lot, par quartier, familles et livraisons à venir.
nonisolated struct VendorRevenueSummary: Sendable, Hashable {
    /// Revenu prévu d'un lot.
    struct OfferRevenue: Identifiable, Sendable, Hashable {
        var id: String
        var title: String
        var revenueCents: Cents
        var committedShares: Int
        var totalShares: Int
        var shareUnit: String
        /// Numéro du meilleur palier atteint (« Palier 2 »), nil si aucun.
        var tierNumber: Int?
    }

    /// Revenu prévu d'un quartier, toutes commandes de ses groupes confondues.
    struct NeighborhoodRevenue: Identifiable, Sendable, Hashable {
        var neighborhood: String
        /// Groupes du quartier qui ont commandé, par ordre alphabétique.
        var groupNames: [String]
        var revenueCents: Cents
        var households: Int
        var shares: Int

        var id: String { neighborhood }
    }

    /// Livraison à venir : une commande groupée sur un lot qui ferme bientôt.
    struct Delivery: Identifiable, Sendable, Hashable {
        var id: String
        var offerTitle: String
        var shareUnit: String
        var deadline: Date
        /// Groupe qui a commandé ; nil si le lot n'a encore aucune commande.
        var groupName: String?
        var shares: Int
        var households: Int
        var revenueCents: Cents
        /// Point de cueillette ; nil s'il n'est pas encore choisi ou introuvable.
        var pickupPointName: String?
        var pickupAddress: String?
        /// Premier créneau de cueillette, s'il y en a un.
        var pickupStart: Date?
    }

    var totalCents: Cents
    /// Lots actifs, du plus grand revenu au plus petit (puis par nom).
    var offers: [OfferRevenue]
    /// Quartiers, du plus grand revenu au plus petit (puis par nom).
    var neighborhoods: [NeighborhoodRevenue]
    /// Familles servies (ménages engagés, toutes commandes confondues).
    var familiesServed: Int
    var committedShares: Int
    var totalShares: Int
    /// Commandes des lots qui ferment bientôt, par date limite croissante.
    var deliveries: [Delivery]

    /// Lot qui rapporte le plus, nil si aucun revenu.
    var topOffer: OfferRevenue? { offers.first.flatMap { $0.revenueCents > 0 ? $0 : nil } }

    init(dashboard: VendorDashboardViewModel.Dashboard, pickupPoints: [String: PickupPoint]) {
        totalCents = dashboard.projectedRevenueCents
        familiesServed = dashboard.committedHouseholds
        committedShares = dashboard.totalCommittedShares
        totalShares = dashboard.totalShares

        offers = dashboard.offers
            .map { summary in
                OfferRevenue(
                    id: summary.id, title: summary.title, revenueCents: summary.projectedRevenueCents,
                    committedShares: summary.committedShares, totalShares: summary.totalShares,
                    shareUnit: summary.offer.shareUnit, tierNumber: summary.bestTierNumber
                )
            }
            .sorted { lhs, rhs in
                lhs.revenueCents != rhs.revenueCents
                    ? lhs.revenueCents > rhs.revenueCents
                    : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        var byNeighborhood: [String: NeighborhoodRevenue] = [:]
        for summary in dashboard.offers {
            for linked in summary.linkedOrders {
                let key = linked.group.neighborhood
                var entry = byNeighborhood[key] ?? NeighborhoodRevenue(
                    neighborhood: key, groupNames: [], revenueCents: 0, households: 0, shares: 0
                )
                entry.revenueCents += summary.revenue(of: linked)
                entry.households += linked.order.committedHouseholds
                entry.shares += linked.order.committedShares
                if !entry.groupNames.contains(linked.group.name) { entry.groupNames.append(linked.group.name) }
                byNeighborhood[key] = entry
            }
        }
        neighborhoods = byNeighborhood.values
            .map { entry in
                var sorted = entry
                sorted.groupNames.sort { $0.localizedStandardCompare($1) == .orderedAscending }
                return sorted
            }
            .sorted { lhs, rhs in
                lhs.revenueCents != rhs.revenueCents
                    ? lhs.revenueCents > rhs.revenueCents
                    : lhs.neighborhood.localizedStandardCompare(rhs.neighborhood) == .orderedAscending
            }

        deliveries = dashboard.closingSoon.flatMap { summary -> [Delivery] in
            guard !summary.linkedOrders.isEmpty else {
                return [Delivery(
                    id: summary.id, offerTitle: summary.title, shareUnit: summary.offer.shareUnit,
                    deadline: summary.offer.deadline, groupName: nil, shares: 0, households: 0, revenueCents: 0,
                    pickupPointName: nil, pickupAddress: nil, pickupStart: nil
                )]
            }
            return summary.linkedOrders.map { linked in
                let point = linked.order.pickupPointId.flatMap { pickupPoints[$0] }
                return Delivery(
                    id: linked.order.id, offerTitle: summary.title, shareUnit: summary.offer.shareUnit,
                    deadline: summary.offer.deadline, groupName: linked.group.name,
                    shares: linked.order.committedShares, households: linked.order.committedHouseholds,
                    revenueCents: summary.revenue(of: linked),
                    pickupPointName: point?.name, pickupAddress: point?.address,
                    pickupStart: linked.order.pickupSlots.map(\.start).min()
                )
            }
        }
    }
}

@Observable @MainActor
final class VendorRevenueModel {
    /// Tableau de bord lu tel quel (T-022).
    let dashboard: VendorDashboardViewModel

    private(set) var pickupPoints: [String: PickupPoint] = [:]

    /// T-195 : encaissé réel des commandes fermées (paiements et versements enregistrés à la clôture).
    /// `.empty` tant qu'aucune commande fermée n'a de versement ; son échec ne cache pas le revenu prévu.
    private(set) var settlement: LoadState<VendorSettlement> = .idle

    private let repositories: AppRepositories

    init(
        repositories: AppRepositories,
        vendorId: String,
        closingSoonInterval: TimeInterval = 72 * 3_600,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repositories = repositories
        dashboard = VendorDashboardViewModel(
            repositories: repositories, vendorId: vendorId, closingSoonInterval: closingSoonInterval, now: now
        )
    }

    /// `.empty` si le vendeur n'a aucun lot actif.
    var state: LoadState<VendorRevenueSummary> {
        switch dashboard.state {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed(let error): .failed(error)
        case .loaded(let value): .loaded(VendorRevenueSummary(dashboard: value, pickupPoints: pickupPoints))
        }
    }

    /// Premier chargement (passe par `.loading`).
    func load() async {
        settlement = .loading
        async let points: Void = loadPickupPoints()
        async let settled: Void = loadSettlement()
        await dashboard.load()
        await points
        await settled
    }

    /// Recharge sans repasser par `.loading` (pour `.refreshable`).
    func refresh() async {
        async let points: Void = loadPickupPoints()
        async let settled: Void = loadSettlement()
        await dashboard.refresh()
        await points
        await settled
    }

    /// Relance seulement l'encaissé réel (bouton « Réessayer » de la section).
    func retrySettlement() async {
        settlement = .loading
        await loadSettlement()
    }

    /// Commandes fermées ou livrées du vendeur, avec leurs parts, paiements enregistrés et versement
    /// (`VendorRevenue.report` pour les totaux, `VendorSettlement` pour commission, net, acompte et reste dû).
    private func loadSettlement() async {
        let vendorId = dashboard.vendorId
        let repositories = repositories
        do {
            let offers = try await repositories.offers.offers(ofVendor: vendorId)
            let linked = try await VendorRepositoryQueries.linkedGroupOrders(
                ofOffers: offers.map(\.id), in: repositories, statuses: [.closed, .delivered]
            )
            let orders = linked.map(\.order)
            guard !orders.isEmpty else { settlement = .empty; return }

            var sharesByOrder: [String: [Share]] = [:]
            var payments: [PaymentRecord] = []
            var payouts: [VendorPayoutRecord] = []
            try await withThrowingTaskGroup(of: (String, [Share], [PaymentRecord], VendorPayoutRecord?).self) { group in
                for order in orders {
                    group.addTask {
                        async let shares = repositories.groupOrders.shares(ofGroupOrder: order.id)
                        async let paid = repositories.groupOrders.payments(ofGroupOrder: order.id)
                        async let payout = repositories.groupOrders.vendorPayout(ofGroupOrder: order.id)
                        return try await (order.id, shares, paid, payout)
                    }
                }
                for try await (orderId, shares, paid, payout) in group {
                    sharesByOrder[orderId] = shares
                    payments += paid
                    if let payout { payouts.append(payout) }
                }
            }
            let report = VendorRevenue.report(
                vendorId: vendorId, offers: offers,
                orders: VendorSettlement.settledOrders(orders, payouts: payouts),
                sharesByOrder: sharesByOrder, payments: payments
            )
            let result = VendorSettlement(report: report, payouts: payouts)
            settlement = result.isEmpty ? .empty : .loaded(result)
        } catch {
            settlement = .failed(AppError(error))
        }
    }

    /// Les points de cueillette sont un bonus : en cas d'erreur, les livraisons s'affichent sans le lieu.
    private func loadPickupPoints() async {
        guard let points = try? await repositories.pickupPoints.pickupPoints() else { return }
        pickupPoints = Dictionary(points.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
