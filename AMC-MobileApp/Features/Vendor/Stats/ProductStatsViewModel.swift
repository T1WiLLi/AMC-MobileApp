// ProductStatsViewModel.swift
// RQ-077 (T-119) : charge les produits, lots et commandes du vendeur via les dépôts, puis délègue
// l'agrégation à `ProductSalesAggregator`. Changer de période ne recharge rien : on ré-agrège.
//
// Usage :
//   @State private var model = ProductStatsViewModel(repositories: context.repositories, vendorId: context.vendorId)
//   .task { await model.load() }  ·  .refreshable { await model.refresh() }

import Foundation
import Observation

@Observable @MainActor
final class ProductStatsViewModel {
    /// Données brutes du vendeur, gardées pour ré-agréger sans réseau.
    nonisolated struct Source: Sendable, Hashable {
        var products: [Product]
        var offers: [Offer]
        var orders: [GroupOrder]
    }

    /// `.empty` : le vendeur n'a encore aucun lot publié.
    private(set) var state: LoadState<ProductStatsReport> = .idle

    /// Période affichée ; la changer ré-agrège tout de suite.
    var period: ProductStatsPeriod = .twelveWeeks {
        didSet { if period != oldValue { recompute() } }
    }

    /// Produit mis en avant dans le graphique de tendance ; nil = tous les produits.
    var selectedProductId: String?

    let vendorId: String

    private let repositories: AppRepositories
    private let now: @Sendable () -> Date
    private var source: Source?

    init(
        repositories: AppRepositories,
        vendorId: String,
        period: ProductStatsPeriod = .twelveWeeks,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.period = period
        self.now = now
    }

    /// Rapport chargé, s'il y en a un.
    var report: ProductStatsReport? { state.value }

    /// Statistiques du produit sélectionné, nil pour « tous ».
    var selectedProduct: ProductSalesStats? { report?.product(id: selectedProductId) }

    /// Semaines du graphique : celles du produit choisi, sinon le total.
    var chartWeeks: [ProductWeekPoint] { selectedProduct?.weekly ?? report?.weekly ?? [] }

    /// Premier chargement (passe par `.loading`).
    func load() async {
        state = .loading
        await refresh()
    }

    /// Recharge sans repasser par `.loading` (pour `.refreshable`).
    func refresh() async {
        do {
            source = try await fetchSource()
            recompute()
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Choisit (ou désélectionne, si déjà choisi) un produit pour le graphique.
    func toggleSelection(_ productId: String) {
        selectedProductId = selectedProductId == productId ? nil : productId
    }

    // MARK: - Privé

    private func recompute() {
        guard let source else { return }
        guard source.offers.contains(where: { ProductSalesAggregator.countedOfferStatuses.contains($0.status) }) else {
            state = .empty
            return
        }
        let report = ProductSalesAggregator.report(
            products: source.products, offers: source.offers, orders: source.orders, period: period, now: now()
        )
        if let selectedProductId, report.product(id: selectedProductId) == nil {
            self.selectedProductId = nil
        }
        state = .loaded(report)
    }

    private func fetchSource() async throws -> Source {
        let repositories = repositories
        let vendorId = vendorId
        async let productsTask = repositories.vendors.products(ofVendor: vendorId)
        let offers = try await repositories.offers.offers(ofVendor: vendorId)
        let counted = offers.filter { ProductSalesAggregator.countedOfferStatuses.contains($0.status) }
        let orders = try await withThrowingTaskGroup(of: [GroupOrder].self) { group in
            for offer in counted {
                group.addTask { try await repositories.groupOrders.groupOrders(ofOffer: offer.id) }
            }
            var all: [GroupOrder] = []
            for try await batch in group { all += batch }
            return all
        }
        let products = try await productsTask
        // Une commande peut être vue deux fois (cache, flux) : on garde la première.
        var seen: Set<String> = []
        let unique = orders.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        return Source(products: products, offers: offers, orders: unique)
    }
}
