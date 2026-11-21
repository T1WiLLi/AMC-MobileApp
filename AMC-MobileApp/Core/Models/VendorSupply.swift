// VendorSupply.swift
// Sous-collection `vendors/{vendorId}/supplies/{supplyId}` : « Ce que le vendeur a » (S-08).
// Une disponibilité = une quantité d'une catégorie (ou d'un produit) que le vendeur peut livrer
// pendant une période, dans des zones (préfixes geohash).

import Foundation

nonisolated struct VendorSupply: Identifiable, Codable, Sendable, Hashable {
    /// Id du document ; vide avant le premier enregistrement (le dépôt en attribue un).
    var id: String
    var vendorId: String
    var category: Product.Category
    /// Produit du vendeur concerné ; nil = toute la catégorie.
    var productId: String?
    /// Quantité disponible sur la période, dans `unit`.
    var quantity: Double
    var unit: MeasureUnit
    var availableFrom: Date
    var availableTo: Date
    /// Zones desservies : préfixes geohash (« f25d » couvre « f25dv », « f25du »…).
    var servedZones: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "",
        vendorId: String,
        category: Product.Category,
        productId: String? = nil,
        quantity: Double,
        unit: MeasureUnit,
        availableFrom: Date,
        availableTo: Date,
        servedZones: [String],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.vendorId = vendorId
        self.category = category
        self.productId = productId
        self.quantity = quantity
        self.unit = unit
        self.availableFrom = availableFrom
        self.availableTo = availableTo
        self.servedZones = servedZones
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Mêmes contrôles que `firestore.rules`, pour échouer tôt avec un message clair.
    func validate() throws {
        guard !vendorId.isEmpty else { throw AppError.invalidInput("La disponibilité doit avoir un vendeur.") }
        guard quantity > 0, quantity <= 1_000_000 else {
            throw AppError.invalidInput("Indique une quantité entre 0 et 1 000 000.")
        }
        guard availableTo >= availableFrom else {
            throw AppError.invalidInput("La fin de la disponibilité doit suivre son début.")
        }
        guard !servedZones.isEmpty, servedZones.count <= 20, servedZones.allSatisfy({ !$0.isEmpty }) else {
            throw AppError.invalidInput("Choisis entre 1 et 20 zones desservies.")
        }
    }
}
