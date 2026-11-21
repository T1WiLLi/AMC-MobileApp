// HomeOfferFilter.swift
// Filtre de la section « Nouveaux lots près de toi » de l'Accueil : puces par type de produit et liste courte.

import Foundation

nonisolated enum HomeOfferFilter {
    /// Nombre de lots affichés avant « Voir les autres lots ».
    static let collapsedLimit = 5

    /// Catégories présentes, dans l'ordre de `Product.Category.allCases`, avec leur nombre de lots.
    static func categoryCounts(_ categories: [Product.Category]) -> [(category: Product.Category, count: Int)] {
        let counts = Dictionary(categories.map { ($0, 1) }, uniquingKeysWith: +)
        return Product.Category.allCases.compactMap { category in
            counts[category].map { (category, $0) }
        }
    }

    /// Les puces n'apparaissent que s'il y a au moins deux types de produits à départager.
    static func showsChips(_ categories: [Product.Category]) -> Bool {
        Set(categories).count > 1
    }

    /// Nombre de lots à afficher : tous une fois dépliée, sinon `collapsedLimit` au plus.
    static func visibleCount(total: Int, isExpanded: Bool) -> Int {
        isExpanded ? total : min(total, collapsedLimit)
    }

    /// Lots du type choisi (tous si `category` est nil).
    static func filter(_ summaries: [OfferSummary], category: Product.Category?) -> [OfferSummary] {
        guard let category else { return summaries }
        return summaries.filter { $0.product.category == category }
    }
}
