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
// (voir la limite dans `VendorRepositoryQueries`), plus les envies des familles (`groups/{id}/wishes`, S-07)
// encore valables, agrégées sans dire qui (`GroupDemand`). Tout vient des dépôts (Firestore en vrai) (T-129).

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
            case .group: "Groupes"
            case .neighborhood: "Quartiers"
            case .geohash: "Zones"
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
            case .allOffers: "Toute la demande"
            case .myOffers: "Mes lots"
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
        /// Demande relative au point le plus demandeur, de 0 à 1 (taille des bulles), voir `demandScore`.
        var intensity: Double
        /// Envies des familles du point, par catégorie et unité (agrégat anonyme).
        var wishes: [GroupDemand] = []
        /// Ménages distincts qui ont au moins une envie dans le point.
        var wishingHouseholds: Int = 0

        /// Familles prêtes à acheter : engagées dans une commande ou qui ont exprimé une envie.
        /// Un ménage engagé qui a aussi une envie peut compter deux fois : les parts ne disent pas qui les a prises.
        var interestedHouseholds: Int { committedHouseholds + wishingHouseholds }
        /// Poids du point sur la carte : une part engagée = 1, une famille qui exprime une envie = 1.
        var demandScore: Int { committedShares + wishingHouseholds }

        /// Badge « Forte demande ».
        var isHighDemand: Bool { intensity >= DemandMapViewModel.highDemandThreshold }
    }

    /// Une commande groupée vivante avec son lot et son produit (données brutes, avant agrégation).
    nonisolated struct DemandRecord: Sendable, Hashable {
        var linked: LinkedGroupOrder
        var offer: Offer
        var product: Product?
    }

    /// Une envie d'une famille, avec le groupe où elle a été exprimée.
    nonisolated struct WishRecord: Sendable, Hashable {
        var wish: GroupWish
        var group: NeighborhoodGroup
    }

    /// Données brutes chargées : commandes vivantes et envies valables.
    nonisolated struct DemandData: Sendable, Hashable {
        var orders: [DemandRecord] = []
        var wishes: [WishRecord] = []

        var isEmpty: Bool { orders.isEmpty && wishes.isEmpty }
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
    private(set) var records: LoadState<DemandData> = .idle

    let vendorId: String
    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, vendorId: String, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.now = now
    }

    /// Points agrégés selon les filtres, par parts décroissantes ; `.empty` si aucune demande.
    var state: LoadState<[DemandPoint]> {
        switch records {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed(let error): .failed(error)
        case .loaded(let data):
            .from(Self.aggregate(
                filtered(data.orders), wishes: filteredWishes(data), by: grouping, precision: geohashPrecision
            ))
        }
    }

    var points: [DemandPoint] { state.value ?? [] }
    var selectedPoint: DemandPoint? { points.first { $0.id == selectedPointID } }
    var totalCommittedShares: Int { points.reduce(0) { $0 + $1.committedShares } }
    var totalWishingHouseholds: Int { points.reduce(0) { $0 + $1.wishingHouseholds } }

    /// Produits présents dans la demande chargée (pour le filtre), par nom.
    var availableProducts: [ProductDemand] {
        let records = (records.value?.orders ?? []).filter { scope == .allOffers || $0.offer.vendorId == vendorId }
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
            async let orders = fetchRecords()
            async let wishes = fetchWishes()
            let data = DemandData(orders: try await orders, wishes: try await wishes)
            records = data.isEmpty ? .empty : .loaded(data)
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

    /// Envies valables (période pas encore finie) des groupes publics. Les groupes privés restent privés,
    /// comme pour les commandes (`linkedGroupOrders(in:)`).
    private func fetchWishes() async throws -> [WishRecord] {
        async let wishes = repositories.wishes.allWishes()
        async let groups = repositories.groups.groups(inNeighborhood: nil)
        return Self.wishRecords(try await wishes, groups: try await groups, now: now())
    }

    /// Relie chaque envie à son groupe public ; ignore les envies vides, terminées ou d'un groupe inconnu.
    nonisolated static func wishRecords(_ wishes: [GroupWish], groups: [NeighborhoodGroup], now: Date) -> [WishRecord] {
        let groupsById = Dictionary(groups.filter(\.isPublic).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return wishes.compactMap { wish in
            guard wish.quantity > 0, let group = groupsById[wish.groupId] else { return nil }
            if let until = wish.wantedUntil, until < now { return nil }
            return WishRecord(wish: wish, group: group)
        }
    }

    /// Les envies ne sont liées à aucun lot : elles comptent dans « Toute la demande » seulement.
    /// Avec un filtre produit, on garde les envies de ce produit et celles de sa catégorie sans produit précis.
    private func filteredWishes(_ data: DemandData) -> [WishRecord] {
        guard scope == .allOffers else { return [] }
        guard let productFilter else { return data.wishes }
        let category = data.orders.first { $0.offer.productId == productFilter }?.product?.category
        return data.wishes.filter { record in
            if let productId = record.wish.productId { return productId == productFilter }
            return category != nil && record.wish.category == category
        }
    }

    private func filtered(_ records: [DemandRecord]) -> [DemandRecord] {
        records.filter { record in
            (scope == .allOffers || record.offer.vendorId == vendorId)
                && (productFilter == nil || record.offer.productId == productFilter)
        }
    }

    // MARK: Agrégation (pure, testable)

    nonisolated static func aggregate(
        _ records: [DemandRecord],
        wishes: [WishRecord] = [],
        by grouping: Grouping,
        precision: Int = 4
    ) -> [DemandPoint] {
        func key(of group: NeighborhoodGroup) -> String {
            switch grouping {
            case .group: group.id
            case .neighborhood: group.neighborhood
            case .geohash: String(group.centerGeohash.prefix(max(1, precision)))
            }
        }
        let buckets = Dictionary(grouping: records) { key(of: $0.linked.group) }
        let wishBuckets = Dictionary(grouping: wishes) { key(of: $0.group) }
        var points = Set(buckets.keys).union(wishBuckets.keys).map { key -> DemandPoint in
            let records = buckets[key] ?? []
            let wishes = wishBuckets[key] ?? []
            // Un groupe compte une fois pour ses membres, même s'il a plusieurs commandes ou envies.
            // Le groupe le plus demandeur (parts, puis familles qui ont une envie) place la bulle.
            var groups: [String: NeighborhoodGroup] = [:]
            var sharesByGroup: [String: Int] = [:]
            for record in records {
                groups[record.linked.group.id] = record.linked.group
                sharesByGroup[record.linked.group.id, default: 0] += record.linked.order.committedShares
            }
            for (groupId, groupWishes) in Dictionary(grouping: wishes, by: \.group.id) {
                groups[groupId] = groupWishes[0].group
                sharesByGroup[groupId, default: 0] += Set(groupWishes.map(\.wish.householdId)).count
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
                intensity: 0,
                wishes: GroupDemand.aggregate(wishes.map(\.wish)),
                wishingHouseholds: Set(wishes.map(\.wish.householdId)).count
            )
        }
        let maxScore = points.map(\.demandScore).max() ?? 0
        for index in points.indices {
            points[index].intensity = maxScore > 0 ? Double(points[index].demandScore) / Double(maxScore) : 0
        }
        return points.sorted { ($0.demandScore, $1.label) > ($1.demandScore, $0.label) }
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
