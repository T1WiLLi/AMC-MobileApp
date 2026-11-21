// VendorSearchViewModel.swift
// Recherche du portail Vendeur (T-129, QA T-094 n° 16) : cherche dans CE vendeur — son catalogue, ses lots —
// et dans la demande des quartiers (commandes groupées et envies des familles), jamais chez les autres producteurs.
//
// Usage :
//   @State private var model = VendorSearchViewModel(repositories: context.repositories, vendorId: context.vendorId)
//   .task { await model.load() }  ·  .searchable(text: $model.query)
//   model.results → produits, lots, quartiers et groupes filtrés par `query`

import Foundation
import Observation

@Observable @MainActor
final class VendorSearchViewModel {
    /// Lot du vendeur avec son produit (nil s'il est introuvable).
    nonisolated struct OfferItem: Identifiable, Sendable, Hashable {
        var offer: Offer
        var product: Product?

        var id: String { offer.id }
        var title: String { product?.name ?? offer.shareUnit }
    }

    /// Tout ce qui est cherchable, chargé une fois.
    nonisolated struct Catalog: Sendable, Hashable {
        var products: [Product] = []
        var offers: [OfferItem] = []
        /// Demande par quartier, puis par groupe (agrégats de `DemandMapViewModel`).
        var neighborhoods: [DemandMapViewModel.DemandPoint] = []
        var groups: [DemandMapViewModel.DemandPoint] = []

        var isEmpty: Bool { products.isEmpty && offers.isEmpty && neighborhoods.isEmpty && groups.isEmpty }
    }

    var query = ""
    private(set) var state: LoadState<Catalog> = .idle

    let vendorId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
    }

    /// Résultats filtrés par `query` (tout le catalogue si la recherche est vide).
    var results: Catalog { Self.filter(state.value ?? Catalog(), query: query) }

    func load() async {
        if state.value == nil { state = .loading }
        await refresh()
    }

    func refresh() async {
        do {
            async let products = repositories.vendors.products(ofVendor: vendorId)
            async let offers = repositories.offers.offers(ofVendor: vendorId)
            let demand = DemandMapViewModel(repositories: repositories, vendorId: vendorId)
            await demand.load()

            let loadedProducts = try await products
            let productsById = Dictionary(loadedProducts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let offerItems = try await offers
                .filter { $0.status == .active || $0.status == .draft }
                .sorted { $0.deadline < $1.deadline }
                .map { OfferItem(offer: $0, product: productsById[$0.productId]) }

            // La demande est un bonus : si elle ne charge pas, le catalogue et les lots restent cherchables.
            demand.grouping = .neighborhood
            let neighborhoods = demand.points
            demand.grouping = .group
            let groups = demand.points

            let catalog = Catalog(
                products: loadedProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                offers: offerItems,
                neighborhoods: neighborhoods,
                groups: groups
            )
            state = catalog.isEmpty ? .empty : .loaded(catalog)
        } catch {
            state = .failed(AppError(error))
        }
    }

    // MARK: Filtre (pur, testable)

    /// Insensible à la casse et aux accents. Produit : nom, origine, catégorie, unité. Lot : produit, format.
    /// Demande : nom du quartier ou du groupe, produits commandés et catégories des envies.
    nonisolated static func filter(_ catalog: Catalog, query: String) -> Catalog {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return catalog }
        func matches(_ fields: [String]) -> Bool { fields.contains { $0.localizedStandardContains(text) } }
        func matchesPoint(_ point: DemandMapViewModel.DemandPoint) -> Bool {
            matches([point.label] + point.products.map(\.name) + point.wishes.map(\.category.title))
        }
        return Catalog(
            products: catalog.products.filter { matches([$0.name, $0.origin, $0.category.title, $0.unit]) },
            offers: catalog.offers.filter { matches([$0.title, $0.offer.shareUnit, $0.product?.category.title ?? ""]) },
            neighborhoods: catalog.neighborhoods.filter(matchesPoint),
            groups: catalog.groups.filter(matchesPoint)
        )
    }
}
