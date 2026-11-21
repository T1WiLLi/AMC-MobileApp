// GroupWish.swift
// Sous-collection `groups/{groupId}/wishes/{wishId}` : « Ce que les familles veulent » (S-07).
// Une envie = ce qu'un ménage aimerait acheter avec son groupe (catégorie, quantité, rythme).
// Les autres familles ne voient que l'agrégat anonyme (`GroupDemand`), jamais l'envie d'un ménage.

import Foundation

nonisolated struct GroupWish: Identifiable, Codable, Sendable, Hashable {
    /// Rythme d'achat souhaité. Informatif : la quantité est celle d'une livraison.
    enum Frequency: String, Codable, Sendable, CaseIterable {
        case once
        case weekly
        case biweekly
        case monthly

        /// Libellé affiché, en français.
        var title: String {
            switch self {
            case .once: String(localized: "Une fois")
            case .weekly: String(localized: "Chaque semaine")
            case .biweekly: String(localized: "Aux deux semaines")
            case .monthly: String(localized: "Chaque mois")
            }
        }
    }

    /// Id du document ; vide avant le premier enregistrement (le dépôt en attribue un).
    var id: String
    var groupId: String
    var householdId: String
    var category: Product.Category
    /// Produit précis souhaité ; nil = n'importe quel produit de la catégorie.
    var productId: String?
    /// Quantité par livraison, dans `unit`.
    var quantity: Double
    var unit: MeasureUnit
    var frequency: Frequency
    /// Période où le ménage en a besoin ; nil = sans borne de ce côté.
    var wantedFrom: Date?
    var wantedUntil: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "",
        groupId: String,
        householdId: String,
        category: Product.Category,
        productId: String? = nil,
        quantity: Double,
        unit: MeasureUnit,
        frequency: Frequency,
        wantedFrom: Date? = nil,
        wantedUntil: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.groupId = groupId
        self.householdId = householdId
        self.category = category
        self.productId = productId
        self.quantity = quantity
        self.unit = unit
        self.frequency = frequency
        self.wantedFrom = wantedFrom
        self.wantedUntil = wantedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Mêmes contrôles que `firestore.rules`, pour échouer tôt avec un message clair.
    func validate() throws {
        guard !groupId.isEmpty, !householdId.isEmpty else {
            throw AppError.invalidInput(String(localized: "L'envie doit être rattachée à un groupe et à un ménage."))
        }
        guard quantity > 0, quantity <= 10_000 else {
            throw AppError.invalidInput(String(localized: "Indique une quantité entre 0 et 10 000."))
        }
        if let wantedFrom, let wantedUntil, wantedUntil < wantedFrom {
            throw AppError.invalidInput(String(localized: "La fin de la période doit suivre son début."))
        }
    }
}
