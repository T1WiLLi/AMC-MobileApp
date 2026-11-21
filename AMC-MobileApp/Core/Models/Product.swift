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
            case .grains: "Céréales"
            case .legumes: "Légumineuses"
            case .oils: "Huiles"
            case .flour: "Farine"
            case .canned: "Conserves"
            case .eggs: "Œufs"
            case .meat: "Viande"
            case .produce: "Fruits et légumes"
            case .household: "Produits ménagers"
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
