// OfferFeedViewModel.swift
// Fil des lots (T-063, RQ-040) : lots actifs qui desservent la zone du groupe du ménage,
// filtrables par catégorie (RQ-039) et par étiquette, du plus urgent au moins urgent.
//
// Usage dans une vue :
//   @State private var model = OfferFeedViewModel(repositories: repos, householdId: id, groupId: groupId)
//   .task { await model.load() }
//   Puces liées à `model.availableCategories` / `model.availableTags`, sélection dans
//   `$model.selectedCategory` et `model.toggle(tag)` : `state` se recalcule seul.
//   switch model.state { case .loaded(let summaries): OfferCard(summary) ; case .empty: message
//     (« Aucun lot pour ces filtres » si `model.hasActiveFilters`, avec `clearFilters()`) }
//
// Un lot dessert le groupe si une de ses zones est un préfixe du geohash du groupe
// (`OfferSummaryLoader.offer(_:serves:)`). Chaque lot est relié à la commande ouverte du groupe, s'il y en a une.

import Foundation
import Observation

@Observable
@MainActor
final class OfferFeedViewModel {
    // MARK: Filtres (le résultat se recalcule à chaque changement)

    /// Catégorie à garder ; nil = toutes.
    var selectedCategory: Product.Category?
    /// Étiquettes exigées : le produit doit toutes les avoir. Vide = aucune contrainte.
    var selectedTags: Set<DietaryTag> = []

    // MARK: État

    /// Lots chargés, par date limite croissante (avant les filtres).
    private(set) var summaries: LoadState<[OfferSummary]> = .idle

    let householdId: String
    let groupId: String
    private let repositories: AppRepositories

    init(repositories: AppRepositories, householdId: String, groupId: String) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
    }

    /// Lots filtrés, par date limite croissante ; `.empty` si aucun lot ne correspond.
    var state: LoadState<[OfferSummary]> {
        switch summaries {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed(let error): .failed(error)
        case .loaded(let summaries):
            .from(Self.filter(summaries, category: selectedCategory, tags: selectedTags))
        }
    }

    var offers: [OfferSummary] { state.value ?? [] }

    var hasActiveFilters: Bool { selectedCategory != nil || !selectedTags.isEmpty }

    /// Catégories présentes dans les lots chargés, dans l'ordre de RQ-039.
    var availableCategories: [Product.Category] {
        let present = Set((summaries.value ?? []).map(\.product.category))
        return Product.Category.allCases.filter(present.contains)
    }

    /// Étiquettes présentes dans les lots chargés, dans l'ordre de `DietaryTag`.
    var availableTags: [DietaryTag] {
        let present = Set((summaries.value ?? []).flatMap(\.product.tags))
        return DietaryTag.allCases.filter(present.contains)
    }

    // MARK: Actions

    /// Charge (ou recharge) le fil. Garde les lots affichés pendant un rechargement (pull-to-refresh).
    func load() async {
        if summaries.value == nil { summaries = .loading }
        let repositories = repositories, householdId = householdId, groupId = groupId
        let result = await LoadState<[OfferSummary]>.run {
            let group = try await repositories.groups.group(id: groupId)
            let activeOrders = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
                .filter(OfferSummaryLoader.isActive)
            // Les zones des lots sont des préfixes de geohash plus courts que celui du groupe :
            // on prend tout le fil et on garde les lots qui desservent le groupe. Le faux dépôt sait filtrer
            // par préfixe (T-087), mais pas encore Firestore (`arrayContains` = égalité exacte) : on garde ce filtre.
            let now = Date.now
            let offers = try await repositories.offers.activeOffers(inZone: nil)
                .filter { OfferSummaryLoader.offer($0, serves: group) && $0.deadline > now }
            let summaries = try await OfferSummaryLoader.summaries(
                for: offers, groupOrders: activeOrders, householdId: householdId, repositories: repositories
            )
            return Self.sortedByDeadline(summaries)
        }
        if let summaries = result.value { self.summaries = .from(summaries) } else { summaries = result }
    }

    /// Ajoute ou retire une étiquette des filtres.
    func toggle(_ tag: DietaryTag) {
        if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
    }

    func clearFilters() {
        selectedCategory = nil
        selectedTags = []
    }

    // MARK: Calculs (purs, testables)

    nonisolated static func filter(
        _ summaries: [OfferSummary], category: Product.Category?, tags: Set<DietaryTag>
    ) -> [OfferSummary] {
        summaries.filter { summary in
            (category == nil || summary.product.category == category)
                && tags.isSubset(of: Set(summary.product.tags))
        }
    }

    /// Date limite la plus proche d'abord, puis par nom de produit.
    nonisolated static func sortedByDeadline(_ summaries: [OfferSummary]) -> [OfferSummary] {
        summaries.sorted {
            ($0.offer.deadline, $0.product.name, $0.id) < ($1.offer.deadline, $1.product.name, $1.id)
        }
    }

    /// Libellé français d'une étiquette (pour les puces de filtre).
    nonisolated static func title(of tag: DietaryTag) -> String {
        switch tag {
        case .organic: "Bio"
        case .halal: "Halal"
        case .kosher: "Casher"
        case .vegetarian: "Végétarien"
        case .vegan: "Végane"
        case .glutenFree: "Sans gluten"
        case .local: "Local"
        }
    }
}
