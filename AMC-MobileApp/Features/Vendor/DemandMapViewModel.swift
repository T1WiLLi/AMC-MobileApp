// DemandMapViewModel.swift
// V3 Carte de la demande (T-022) : parts engagées agrégées par groupe, quartier ou geohash, pour une carte ou une liste.
//
// Usage dans une vue :
//   @State private var model = DemandMapViewModel(repositories: repos, vendorId: id)
//   .task { await model.load() }
//   Picker lié à `$model.grouping`, filtres `$model.scope` et `$model.productFilter` : `state` se recalcule seul.
//   switch model.state { case .loaded(let points): bulles de taille `point.intensity`, badge si `point.isHighDemand` }
//
// Demande = commandes groupées ouvertes ou palier atteint (`open`, `reached`) des groupes publics
// (voir la limite dans `VendorRepositoryQueries`).

import Foundation
import Observation

@Observable @MainActor
final class DemandMapViewModel {
    /// Niveau d'agrégation.
    nonisolated enum Grouping: String, CaseIterable, Identifiable, Sendable {
        case group
        case neighborhood
        case geohash

        var id: String { rawValue }
        var title: String {
            switch self {
            case .group: String(localized: "Groupes")
            case .neighborhood: String(localized: "Quartiers")
            case .geohash: String(localized: "Zones")
            }
        }
    }

    /// Lots pris en compte.
    nonisolated enum Scope: String, CaseIterable, Identifiable, Sendable {
        /// Toute la demande du marché (utile pour « Proposer un lot ici »).
        case allOffers
        /// Seulement les lots de ce vendeur.
        case myOffers

        var id: String { rawValue }
        var title: String {
            switch self {
            case .allOffers: String(localized: "Toute la demande")
            case .myOffers: String(localized: "Mes lots")
            }
        }
    }

    /// Demande pour un produit dans une zone.
    nonisolated struct ProductDemand: Identifiable, Sendable, Hashable {
        var productId: String
        /// Nom du produit, ou l'unité de part si le produit est introuvable.
        var name: String
        var shareUnit: String
        var committedShares: Int

        var id: String { productId }
    }

    /// Un point de la carte (ou une ligne de liste).
    nonisolated struct DemandPoint: Identifiable, Sendable, Hashable {
        /// Id du groupe, nom du quartier ou préfixe geohash selon `grouping`.
        var id: String
        var grouping: Grouping
        /// Nom du groupe, du quartier ou geohash.
        var label: String
        /// Geohash du centre (centre du groupe le plus demandeur pour un quartier ou une zone).
        var geohash: String
        var groupIds: [String]
        var committedShares: Int
        var committedHouseholds: Int
        /// Ménages membres des groupes du point.
        var householdCount: Int
        /// Produits demandés, par parts décroissantes.
        var products: [ProductDemand]
        /// Parts relatives au point le plus demandeur, de 0 à 1 (taille des bulles).
        var intensity: Double

        /// Badge « Forte demande ».
        var isHighDemand: Bool { intensity >= DemandMapViewModel.highDemandThreshold }
    }

    /// Une commande groupée vivante avec son lot et son produit (données brutes, avant agrégation).
    nonisolated struct DemandRecord: Sendable, Hashable {
        var linked: LinkedGroupOrder
        var offer: Offer
        var product: Product?
    }

    /// Intensité à partir de laquelle un point est en « Forte demande ».
    nonisolated static let highDemandThreshold = 0.66

    // MARK: Filtres (le résultat se recalcule à chaque changement)

    var grouping: Grouping = .neighborhood
    var scope: Scope = .allOffers
    /// Id de produit à garder ; nil = tous.
    var productFilter: String?
    /// Longueur du préfixe geohash pour `grouping == .geohash` (4 ≈ 39 × 20 km, comme les zones des lots).
    var geohashPrecision: Int = 4
    /// Point sélectionné sur la carte (pour la feuille du bas).
    var selectedPointID: DemandPoint.ID?

    // MARK: État

    /// Données brutes chargées.
    private(set) var records: LoadState<[DemandRecord]> = .idle

    let vendorId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
    }

    /// Points agrégés selon les filtres, par parts décroissantes ; `.empty` si aucune demande.
    var state: LoadState<[DemandPoint]> {
        switch records {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed(let error): .failed(error)
        case .loaded(let records): .from(Self.aggregate(filtered(records), by: grouping, precision: geohashPrecision))
        }
    }

    var points: [DemandPoint] { state.value ?? [] }
    var selectedPoint: DemandPoint? { points.first { $0.id == selectedPointID } }
    var totalCommittedShares: Int { points.reduce(0) { $0 + $1.committedShares } }

    /// Produits présents dans la demande chargée (pour le filtre), par nom.
    var availableProducts: [ProductDemand] {
        let records = (records.value ?? []).filter { scope == .allOffers || $0.offer.vendorId == vendorId }
        return Self.productDemands(records).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: Actions

    func load() async {
        records = .loading
        await refresh()
    }

    /// Recharge sans repasser par `.loading`.
    func refresh() async {
        do {
            let records = try await fetchRecords()
            self.records = .from(records)
        } catch {
            records = .failed(AppError(error))
        }
    }

    private func fetchRecords() async throws -> [DemandRecord] {
        let linked = try await VendorRepositoryQueries.linkedGroupOrders(
            in: repositories, statuses: VendorRepositoryQueries.liveStatuses
        )
        var offers: [String: Offer] = [:]
        var products: [String: Product] = [:]
        var records: [DemandRecord] = []
        for item in linked where item.order.committedShares > 0 {
            let offer: Offer
            if let cached = offers[item.order.offerId] {
                offer = cached
            } else {
                do {
                    offer = try await repositories.offers.offer(id: item.order.offerId)
                } catch AppError.notFound {
                    continue
                }
                offers[offer.id] = offer
            }
            if products[offer.productId] == nil {
                products[offer.productId] = try? await repositories.vendors.product(id: offer.productId)
            }
            records.append(DemandRecord(linked: item, offer: offer, product: products[offer.productId]))
        }
        return records
    }

    private func filtered(_ records: [DemandRecord]) -> [DemandRecord] {
        records.filter { record in
            (scope == .allOffers || record.offer.vendorId == vendorId)
                && (productFilter == nil || record.offer.productId == productFilter)
        }
    }

    // MARK: Agrégation (pure, testable)

    nonisolated static func aggregate(_ records: [DemandRecord], by grouping: Grouping, precision: Int = 4) -> [DemandPoint] {
        let buckets = Dictionary(grouping: records) { record -> String in
            let group = record.linked.group
            return switch grouping {
            case .group: group.id
            case .neighborhood: group.neighborhood
            case .geohash: String(group.centerGeohash.prefix(max(1, precision)))
            }
        }
        var points = buckets.map { key, records -> DemandPoint in
            // Un groupe compte une fois pour ses membres, même s'il a plusieurs commandes.
            var groups: [String: NeighborhoodGroup] = [:]
            var sharesByGroup: [String: Int] = [:]
            for record in records {
                groups[record.linked.group.id] = record.linked.group
                sharesByGroup[record.linked.group.id, default: 0] += record.linked.order.committedShares
            }
            let topGroup = sharesByGroup.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
                .flatMap { groups[$0.key] }
            let label: String = switch grouping {
            case .group: topGroup?.name ?? key
            case .neighborhood, .geohash: key
            }
            return DemandPoint(
                id: key,
                grouping: grouping,
                label: label,
                geohash: topGroup?.centerGeohash ?? key,
                groupIds: groups.keys.sorted(),
                committedShares: records.reduce(0) { $0 + $1.linked.order.committedShares },
                committedHouseholds: records.reduce(0) { $0 + $1.linked.order.committedHouseholds },
                householdCount: groups.values.reduce(0) { $0 + $1.householdCount },
                products: productDemands(records),
                intensity: 0
            )
        }
        let maxShares = points.map(\.committedShares).max() ?? 0
        for index in points.indices {
            points[index].intensity = maxShares > 0 ? Double(points[index].committedShares) / Double(maxShares) : 0
        }
        return points.sorted { ($0.committedShares, $1.label) > ($1.committedShares, $0.label) }
    }

    nonisolated private static func productDemands(_ records: [DemandRecord]) -> [ProductDemand] {
        Dictionary(grouping: records, by: \.offer.productId)
            .map { productId, records in
                ProductDemand(
                    productId: productId,
                    name: records.first?.product?.name ?? records.first?.offer.shareUnit ?? productId,
                    shareUnit: records.first?.offer.shareUnit ?? "",
                    committedShares: records.reduce(0) { $0 + $1.linked.order.committedShares }
                )
            }
            .sorted { ($0.committedShares, $1.name) > ($1.committedShares, $0.name) }
    }
}
