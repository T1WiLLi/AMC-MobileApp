// Product.swift
// Collection `products`.

import Foundation

nonisolated struct Product: Identifiable, Codable, Sendable, Hashable {
    enum Category: String, Codable, Sendable, CaseIterable {
        case produce
        case grains
        case dairy
        case meat
        case pantry
        case bakery
        case other
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
