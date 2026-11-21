// PublicVendorViewModel.swift
// Page publique d'un vendeur côté familles (T-097, R-009) : en-tête, zones desservies,
// catalogue par catégorie et lots en cours. Lecture seule.
//
// Confidentialité : la vue ne reçoit qu'une projection publique (`Profile`), jamais le `Vendor`
// complet ni de revenus, d'adresse exacte, de courriel ou de téléphone.
//
// Usage :
//   @State private var model = PublicVendorViewModel(vendorId: FakeData.ID.fermeRive, repositories: .fake())
//   .task { await model.load() }
//   .refreshable { await model.refresh() }

import Foundation
import Observation

@Observable @MainActor
final class PublicVendorViewModel {
    /// Ce qu'une famille peut voir d'un vendeur.
    nonisolated struct Profile: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var kind: Vendor.Kind
        var description: String
        /// Première photo de vitrine, nil si le vendeur n'en a pas.
        var coverPhotoURL: URL?
        var zones: [Zone]
        var averageRating: Double?
        var isVerified: Bool
    }

    /// Zone desservie : code (préfixe geohash) et quartiers lisibles.
    nonisolated struct Zone: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
    }

    /// Produits d'une catégorie du catalogue.
    nonisolated struct CatalogSection: Identifiable, Hashable, Sendable {
        var category: Product.Category
        var products: [Product]

        var id: Product.Category { category }
        var title: String { category.title }
    }

    /// Lot ouvert, prêt à afficher, avec sa route vers la fiche du lot.
    nonisolated struct OpenOffer: Identifiable, Hashable, Sendable {
        var offer: Offer
        var product: Product

        var id: String { offer.id }
        @MainActor var route: OfferRoute { OfferRoute(offerId: offer.id) }
        /// Prix d'une part au meilleur palier.
        var bestPriceCents: Cents? { offer.tiers.map(\.priceCents).min() }
        /// Économie maximale par rapport à l'épicerie, en pour cent (0 si aucune).
        @MainActor var maxSavingsPercent: Int {
            guard let bestPriceCents else { return 0 }
            return Money.savingsPercent(price: bestPriceCents, reference: product.referenceGroceryPriceCents)
        }
    }

    // MARK: État

    private(set) var state: LoadState<Profile> = .idle
    /// `.empty` quand le vendeur n'a encore aucun produit.
    private(set) var catalog: LoadState<[CatalogSection]> = .idle
    /// `.empty` quand aucun lot n'est ouvert en ce moment.
    private(set) var openOffers: LoadState<[OpenOffer]> = .idle

    let vendorId: String
    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    init(vendorId: String, repositories: AppRepositories, now: @escaping @Sendable () -> Date = { .now }) {
        self.vendorId = vendorId
        self.repositories = repositories
        self.now = now
    }

    var profile: Profile? { state.value }

    // MARK: Actions

    /// Premier chargement : passe par `.loading` (squelette), sauf si la page est déjà affichée.
    func load() async {
        if state.value == nil {
            state = .loading
            catalog = .loading
            openOffers = .loading
        }
        await refresh()
    }

    /// Recharge sans effacer le contenu affiché (pour `.refreshable`).
    func refresh() async {
        do {
            async let loadedVendor = repositories.vendors.vendor(id: vendorId)
            async let loadedProducts = repositories.vendors.products(ofVendor: vendorId)
            async let loadedOffers = repositories.offers.offers(ofVendor: vendorId)
            async let loadedGroups = try? repositories.groups.groups(inNeighborhood: nil)

            let vendor = try await loadedVendor
            let products = try await loadedProducts
            let offers = try await loadedOffers
            let zoneLabels = VendorProfileViewModel.zoneLabels(from: await loadedGroups ?? [])

            let open = await Self.openOffers(offers, products: products, now: now(), repositories: repositories)
            state = .loaded(Self.profile(of: vendor, zoneLabels: zoneLabels))
            catalog = .from(Self.catalog(of: products))
            openOffers = .from(open)
        } catch {
            state = .failed(AppError(error))
            catalog = .idle
            openOffers = .idle
        }
    }

    // MARK: Calculs

    static func profile(of vendor: Vendor, zoneLabels: [String: String]) -> Profile {
        Profile(
            id: vendor.id,
            name: vendor.legalName,
            kind: vendor.kind,
            description: vendor.description,
            coverPhotoURL: vendor.photoURLs.first,
            zones: vendor.servedZones.map { Zone(id: $0, label: zoneLabels[$0.lowercased()] ?? $0) },
            averageRating: vendor.averageRating,
            isVerified: vendor.isVerified
        )
    }

    /// Une section par catégorie présente, dans l'ordre de `Product.Category.allCases`, produits par nom.
    static func catalog(of products: [Product]) -> [CatalogSection] {
        let byCategory = Dictionary(grouping: products, by: \.category)
        return Product.Category.allCases.compactMap { category in
            guard let products = byCategory[category], !products.isEmpty else { return nil }
            let sorted = products.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return CatalogSection(category: category, products: sorted)
        }
    }

    /// Lots actifs dont la date limite n'est pas passée, du plus urgent au plus lointain.
    private static func openOffers(
        _ offers: [Offer],
        products: [Product],
        now: Date,
        repositories: AppRepositories
    ) async -> [OpenOffer] {
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [OpenOffer] = []
        for offer in offers where offer.status == .active && offer.deadline > now {
            let product: Product? = if let known = productsById[offer.productId] {
                known
            } else {
                try? await repositories.vendors.product(id: offer.productId)
            }
            if let product { result.append(OpenOffer(offer: offer, product: product)) }
        }
        return result.sorted { $0.offer.deadline < $1.offer.deadline }
    }
}
