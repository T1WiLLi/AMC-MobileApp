// PublicVendorViewModel.swift
// Page publique d'un vendeur côté familles (T-097, R-009) : en-tête, zones desservies,
// catalogue par catégorie et lots en cours. T-157 : galerie, avis et étoiles des familles, prix par produit,
// dernière vente et indicateurs de confiance ; une famille qui a reçu un lot du producteur peut le noter.
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
        /// Toutes les photos de vitrine (la première est la couverture).
        var photoURLs: [URL] = []
        /// « Mirabel », nil si inconnue.
        var city: String? = nil
        /// Quartier du comptoir (« Saint-Michel »), nil si le producteur n'a pas de comptoir en ville.
        var neighborhood: String? = nil
        var memberSince: Date? = nil
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

    /// Qui regarde la page : sert à savoir s'il peut noter et à signer son avis.
    nonisolated struct Viewer: Hashable, Sendable {
        var userId: String
        var householdId: String
    }

    /// Avis, note et confiance (T-157).
    nonisolated struct Reputation: Hashable, Sendable {
        var summary: VendorReviewRules.Summary
        var recentReviews: [VendorReview]
        var trust: VendorReviewRules.Trust
        /// Avis du ménage lecteur, s'il en a laissé un.
        var myReview: VendorReview?
        /// Vente livrée qui permet au ménage lecteur de noter ; nil = il ne peut pas noter.
        var eligibleSale: VendorSale?

        var canReview: Bool { eligibleSale != nil || myReview != nil }

        static let empty = Reputation(summary: .empty, recentReviews: [],
                                      trust: .init(deliveredLots: 0, familiesServed: 0, since: nil, lastSale: nil),
                                      myReview: nil, eligibleSale: nil)
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
    /// Avis et confiance ; `.empty` jamais (une page sans avis a `Reputation.empty`).
    private(set) var reputation: LoadState<Reputation> = .idle
    /// Meilleur prix d'une part par produit, parmi les lots ouverts (T-157).
    private(set) var bestPriceByProduct: [String: Cents] = [:]

    let vendorId: String
    let viewer: Viewer?
    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    init(vendorId: String, repositories: AppRepositories, viewer: Viewer? = nil,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.vendorId = vendorId
        self.repositories = repositories
        self.viewer = viewer
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
            reputation = .loading
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

            let groups = await loadedGroups ?? []
            let open = await Self.openOffers(offers, products: products, now: now(), repositories: repositories)
            var profile = Self.profile(of: vendor, zoneLabels: zoneLabels)
            profile.neighborhood = Self.neighborhood(ofStorefront: vendor.storefrontGeohash, groups: groups)
            state = .loaded(profile)
            catalog = .from(Self.catalog(of: products))
            openOffers = .from(open)
            bestPriceByProduct = Self.bestPrices(open)
            // Les avis ne bloquent jamais la page : en cas d'erreur, la page s'affiche sans eux.
            reputation = .loaded(await loadReputation(memberSince: vendor.memberSince))
        } catch {
            state = .failed(AppError(error))
            catalog = .idle
            openOffers = .idle
            reputation = .idle
        }
    }

    /// Enregistre (ou modifie) l'avis du ménage lecteur. Renvoie l'erreur, nil si c'est enregistré.
    func saveReview(rating: Int, comment: String) async -> AppError? {
        guard let viewer, !viewer.householdId.isEmpty else { return .unauthenticated }
        guard let current = reputation.value, current.canReview else { return .permissionDenied }
        let groupOrderId = current.myReview?.groupOrderId ?? current.eligibleSale?.id ?? ""
        do {
            let displayName = (try? await repositories.users.user(id: viewer.userId).displayName) ?? ""
            let review = try VendorReviewRules.makeReview(
                vendorId: vendorId, householdId: viewer.householdId,
                authorName: VendorReviewRules.authorName(fromDisplayName: displayName),
                rating: rating, comment: comment, groupOrderId: groupOrderId,
                existing: current.myReview, now: now()
            )
            try await repositories.reviews.saveReview(review)
            reputation = .loaded(await loadReputation(memberSince: state.value?.memberSince))
            return nil
        } catch {
            return AppError(error)
        }
    }

    private func loadReputation(memberSince: Date?) async -> Reputation {
        async let loadedReviews = try? repositories.reviews.reviews(ofVendor: vendorId)
        async let loadedSales = try? repositories.reviews.sales(ofVendor: vendorId, viewerHouseholdId: viewer?.householdId)
        let reviews = await loadedReviews ?? []
        let sales = await loadedSales ?? []
        let householdId = viewer?.householdId ?? ""
        return Reputation(
            summary: VendorReviewRules.summary(of: reviews),
            recentReviews: VendorReviewRules.recent(reviews),
            trust: VendorReviewRules.trust(sales: sales, memberSince: memberSince),
            myReview: householdId.isEmpty ? nil : reviews.first { $0.householdId == householdId },
            eligibleSale: VendorReviewRules.eligibleSale(for: householdId, vendorId: vendorId, in: sales)
        )
    }

    // MARK: Calculs

    static func profile(of vendor: Vendor, zoneLabels: [String: String]) -> Profile {
        Profile(
            id: vendor.id,
            name: vendor.legalName,
            kind: vendor.kind,
            description: vendor.description,
            coverPhotoURL: vendor.photoURLs.first,
            photoURLs: vendor.photoURLs,
            city: vendor.city,
            memberSince: vendor.memberSince,
            zones: vendor.servedZones.map { Zone(id: $0, label: zoneLabels[$0.lowercased()] ?? $0) },
            averageRating: vendor.averageRating,
            isVerified: vendor.isVerified
        )
    }

    /// Quartier du groupe dont le centre est le plus proche (plus long préfixe geohash commun, 5 au moins).
    static func neighborhood(ofStorefront geohash: String?, groups: [NeighborhoodGroup]) -> String? {
        guard let geohash = geohash?.lowercased(), geohash.count >= 5 else { return nil }
        func common(_ other: String) -> Int {
            zip(geohash, other.lowercased()).prefix { $0 == $1 }.count
        }
        return groups
            .map { (group: $0, length: common($0.centerGeohash)) }
            .filter { $0.length >= 5 }
            .max { $0.length < $1.length }?
            .group.neighborhood
    }

    /// Meilleur prix d'une part par produit parmi les lots ouverts.
    static func bestPrices(_ offers: [OpenOffer]) -> [String: Cents] {
        var prices: [String: Cents] = [:]
        for item in offers {
            guard let best = item.bestPriceCents else { continue }
            prices[item.product.id] = min(prices[item.product.id] ?? best, best)
        }
        return prices
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
