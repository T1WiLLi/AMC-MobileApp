// Product.swift
// Collection `products`.

import Foundation

nonisolated struct Product: Identifiable, Codable, Sendable, Hashable {
    /// Catégories de RQ-039.
    enum Category: String, Codable, Sendable, CaseIterable {
        case grains
        case legumes
        case oils
        case flour
        case canned
        case eggs
        case meat
        case produce
        case household

        /// Libellé affiché, en français.
        var title: String {
            switch self {
            case .grains: String(localized: "Céréales")
            case .legumes: String(localized: "Légumineuses")
            case .oils: String(localized: "Huiles")
            case .flour: String(localized: "Farine")
            case .canned: String(localized: "Conserves")
            case .eggs: String(localized: "Œufs")
            case .meat: String(localized: "Viande")
            case .produce: String(localized: "Fruits et légumes")
            case .household: String(localized: "Produits ménagers")
            }
        }
    }

    var id: String
    var vendorId: String
    var name: String
    var category: Category
    /// Unité de vente : « kg », « sac de 10 kg », « douzaine »…
    var unit: String
    var origin: String
    var tags: [DietaryTag]
    var photoURL: URL?
    /// Prix d'épicerie de référence pour une unité, pour calculer l'économie.
    var referenceGroceryPriceCents: Cents
}

nonisolated extension Product {
    /// `unit` dans la langue de l'app (« sac de 5 kg » / "bag of 5 kg"), pour l'affichage seulement.
    /// Une unité libre que `ShareSpec` ne relit pas fidèlement (« douzaine ») reste telle quelle.
    var displayUnit: String {
        let spec = ShareSpec(parsing: unit)
        return spec.label == unit ? spec.displayLabel : unit
    }
}
