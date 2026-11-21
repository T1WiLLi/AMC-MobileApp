// TierEditorViewModel.swift
// V2 Éditeur de paliers (T-022) : créer ou modifier un lot et ses paliers de prix.
//
// Usage dans une vue :
//   @State private var model = TierEditorViewModel(repositories: repos, vendorId: id)          // nouveau lot
//   @State private var model = TierEditorViewModel(repositories: repos, vendorId: id, offerId: offer.id) // modification
//   .task { await model.load() }
//   Champs éditables liés par `$model.…` (`@Bindable var model`), paliers via `$model.tiers`.
//   `model.validationError` pour afficher l'erreur en direct ; `await model.save()` pour « Publier le lot ».
//
// Hypothèses : une part = une unité du produit (l'économie se calcule contre `referenceGroceryPriceCents`) ;
// `minimumSharesToLaunch` = seuil du premier palier.

import Foundation
import Observation

@Observable @MainActor
final class TierEditorViewModel {
    /// Palier en cours d'édition, dans l'ordre saisi (le rang = position dans `tiers`).
    nonisolated struct TierDraft: Identifiable, Sendable, Hashable {
        var id = UUID()
        /// Parts engagées à partir desquelles le palier s'applique.
        var minShares: Int
        var priceCents: Cents

        /// Prix en dollars, pour un `TextField(value:format: .currency(code: "CAD"))`.
        var price: Decimal {
            get { Decimal(priceCents) / 100 }
            set {
                var cents = newValue * 100
                var rounded = Decimal()
                NSDecimalRound(&rounded, &cents, 0, .plain)
                priceCents = NSDecimalNumber(decimal: rounded).intValue
            }
        }
    }

    /// Ligne d'aperçu d'un palier (liste et graphique en escalier).
    nonisolated struct TierPreview: Identifiable, Sendable, Hashable {
        var id: UUID
        /// Rang lisible, à partir de 1.
        var rank: Int
        var minShares: Int
        /// Dernière part couverte par ce palier (seuil suivant − 1), nil pour le dernier palier (« et + »).
        var maxShares: Int?
        var priceCents: Cents
        /// Économie vs épicerie, en pourcentage arrondi (37 pour −37 %) ; 0 si aucune ou prix de référence inconnu.
        var savingsPercent: Int
        /// Économie par part vs épicerie, en cents (0 si aucune).
        var savingsPerShareCents: Cents
    }

    /// Mode de l'éditeur.
    nonisolated enum Mode: Sendable, Hashable {
        case create
        case edit(offerId: String)
    }

    // MARK: Champs éditables

    var productId: String?
    var totalShares: Int = 20
    /// Ce que contient une part (« sac de 10 kg ») ; prérempli avec l'unité du produit choisi.
    var shareUnit: String = ""
    var deadline: Date
    var zones: [String] = []
    var tiers: [TierDraft] = [TierDraft(minShares: 1, priceCents: 0)]

    // MARK: État

    private(set) var mode: Mode
    /// Chargement initial (produits du vendeur, et le lot en mode modification).
    private(set) var loadState: LoadState<Void> = .idle
    /// Produits du vendeur, pour le sélecteur.
    private(set) var products: [Product] = []
    /// Résultat de la dernière sauvegarde : `.loaded(offer)` si publié, `.failed(.invalidInput(…))` si refusé.
    private(set) var saveState: LoadState<Offer> = .idle

    let vendorId: String

    private let repositories: AppRepositories
    private let now: @Sendable () -> Date
    /// Lot chargé en mode modification (garde statut et zones d'origine).
    private var original: Offer?
    /// Catégorie de la disponibilité d'origine (S-08) : choisit un produit de cette catégorie au chargement.
    private var preferredCategory: Product.Category?

    init(
        repositories: AppRepositories,
        vendorId: String,
        offerId: String? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.now = now
        self.mode = offerId.map { .edit(offerId: $0) } ?? .create
        self.deadline = now().addingTimeInterval(3 * 86_400)
    }

    // MARK: Dérivés

    var isEditing: Bool { if case .edit = mode { true } else { false } }
    var selectedProduct: Product? { products.first { $0.id == productId } }
    /// Prix d'épicerie de référence pour une part ; nil sans produit choisi.
    var referenceGroceryPriceCents: Cents? { selectedProduct?.referenceGroceryPriceCents }
    var isSaving: Bool { saveState.isLoading }

    /// Première règle non respectée, en français ; nil si le lot est publiable.
    var validationError: AppError? {
        do {
            _ = try validatedOffer()
            return nil
        } catch {
            return error
        }
    }

    var isValid: Bool { validationError == nil }

    /// Aperçu des paliers dans l'ordre saisi.
    var tierPreviews: [TierPreview] {
        let reference = referenceGroceryPriceCents ?? 0
        return tiers.enumerated().map { index, tier in
            let next = tiers.indices.contains(index + 1) ? tiers[index + 1].minShares - 1 : nil
            return TierPreview(
                id: tier.id,
                rank: index + 1,
                minShares: tier.minShares,
                maxShares: next,
                priceCents: tier.priceCents,
                savingsPercent: Money.savingsPercent(price: tier.priceCents, reference: reference),
                savingsPerShareCents: reference > 0 ? max(0, reference - tier.priceCents) : 0
            )
        }
    }

    /// Revenu estimé si toutes les parts partent : du prix le plus bas au prix le plus haut (« 420 $ à 640 $ »).
    /// nil sans palier ou sans parts.
    var estimatedRevenueRangeCents: ClosedRange<Cents>? {
        let prices = tiers.map(\.priceCents).filter { $0 > 0 }
        guard totalShares > 0, let low = prices.min(), let high = prices.max() else { return nil }
        return (totalShares * low)...(totalShares * high)
    }

    // MARK: Actions

    /// Charge les produits du vendeur et, en mode modification, le lot à éditer.
    /// Lève `.permissionDenied` (dans `loadState`) si le lot appartient à un autre vendeur.
    func load() async {
        loadState = .loading
        do {
            products = try await repositories.vendors.products(ofVendor: vendorId)
            switch mode {
            case .create:
                if zones.isEmpty {
                    zones = (try? await repositories.vendors.vendor(id: vendorId))?.servedZones ?? []
                }
                if productId == nil,
                   let first = products.first(where: { $0.category == preferredCategory }) ?? products.first {
                    selectProduct(id: first.id)
                }
            case .edit(let offerId):
                let offer = try await repositories.offers.offer(id: offerId)
                guard offer.vendorId == vendorId else { throw AppError.permissionDenied }
                apply(offer)
            }
            loadState = .loaded(())
        } catch {
            loadState = .failed(AppError(error))
        }
    }

    /// S-08 (T-109) : préremplit un nouveau lot depuis une disponibilité, avant `load()`.
    /// Zones desservies, produit (ou un produit de la même catégorie) et date limite dans la période,
    /// au plus tôt dans 24 h.
    func prefill(from supply: VendorSupply) {
        guard case .create = mode else { return }
        zones = supply.servedZones
        productId = supply.productId
        preferredCategory = supply.category
        let earliest = now().addingTimeInterval(86_400)
        let wanted = max(earliest, min(deadline, supply.availableTo))
        deadline = wanted
    }

    /// Choisit le produit du lot et préremplit l'unité de part.
    func selectProduct(id: String) {
        productId = id
        if let product = products.first(where: { $0.id == id }) { shareUnit = product.unit }
    }

    /// Ajoute un palier après le dernier : seuil +10 parts (borné au total), prix −10 %.
    func addTier() {
        guard let last = tiers.last else {
            tiers = [TierDraft(minShares: 1, priceCents: referenceGroceryPriceCents ?? 0)]
            return
        }
        let threshold = min(totalShares, last.minShares + 10)
        tiers.append(TierDraft(minShares: threshold, priceCents: last.priceCents * 9 / 10))
    }

    func removeTier(id: TierDraft.ID) {
        tiers.removeAll { $0.id == id }
    }

    func removeTiers(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where tiers.indices.contains(index) { tiers.remove(at: index) }
    }

    /// Valide puis enregistre via `offers.saveOffer`. Renvoie le lot enregistré, nil en cas d'échec (voir `saveState`).
    /// Après une création réussie, l'éditeur passe en mode modification de ce lot.
    @discardableResult
    func save() async -> Offer? {
        let offer: Offer
        do {
            offer = try validatedOffer()
        } catch {
            saveState = .failed(error)
            return nil
        }
        saveState = .loading
        do {
            try await repositories.offers.saveOffer(offer)
            original = offer
            mode = .edit(offerId: offer.id)
            saveState = .loaded(offer)
            return offer
        } catch {
            saveState = .failed(AppError(error))
            return nil
        }
    }

    /// Construit le lot à enregistrer, ou lève `AppError.invalidInput` avec la première règle non respectée.
    func validatedOffer() throws(AppError) -> Offer {
        guard let productId else { throw .invalidInput(String(localized: "Choisis un produit pour ce lot.")) }
        guard totalShares > 0 else { throw .invalidInput(String(localized: "Le lot doit contenir au moins une part.")) }
        guard !shareUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalidInput(String(localized: "Indique ce que contient une part (par exemple « sac de 10 kg »)."))
        }
        guard !tiers.isEmpty else { throw .invalidInput(String(localized: "Ajoute au moins un palier de prix.")) }
        for (index, tier) in tiers.enumerated() {
            let rank = index + 1
            guard tier.minShares >= 1 else {
                throw .invalidInput(String(localized: "Le seuil du palier \(rank) doit être d'au moins 1 part."))
            }
            guard tier.priceCents > 0 else {
                throw .invalidInput(String(localized: "Le prix du palier \(rank) doit être supérieur à 0 $."))
            }
            guard tier.minShares <= totalShares else {
                throw .invalidInput(
                    String(localized: "Le seuil du palier \(rank) (\(tier.minShares) parts) dépasse le total du lot (\(totalShares) parts).")
                )
            }
            if index > 0 {
                let previous = tiers[index - 1]
                guard tier.minShares > previous.minShares else {
                    throw .invalidInput(
                        String(localized: "Le seuil du palier \(rank) doit être plus grand que celui du palier \(rank - 1) (\(previous.minShares) parts).")
                    )
                }
                guard tier.priceCents < previous.priceCents else {
                    throw .invalidInput(
                        String(localized: "Le prix du palier \(rank) doit être plus bas que celui du palier \(rank - 1) (\(Money.format(previous.priceCents))).")
                    )
                }
            }
        }
        guard deadline > now() else { throw .invalidInput(String(localized: "La date limite doit être dans le futur.")) }

        let offerId: String = switch mode {
        case .create: "offer-\(UUID().uuidString.lowercased())"
        case .edit(let id): id
        }
        return Offer(
            id: offerId,
            vendorId: vendorId,
            productId: productId,
            totalShares: totalShares,
            shareUnit: shareUnit.trimmingCharacters(in: .whitespacesAndNewlines),
            tiers: tiers.map { PriceTier(minShares: $0.minShares, priceCents: $0.priceCents) },
            minimumSharesToLaunch: tiers[0].minShares,
            deadline: deadline,
            zones: zones,
            status: original?.status ?? .active
        )
    }

    private func apply(_ offer: Offer) {
        original = offer
        productId = offer.productId
        totalShares = offer.totalShares
        shareUnit = offer.shareUnit
        deadline = offer.deadline
        zones = offer.zones
        tiers = offer.sortedTiers.map { TierDraft(minShares: $0.minShares, priceCents: $0.priceCents) }
    }
}
