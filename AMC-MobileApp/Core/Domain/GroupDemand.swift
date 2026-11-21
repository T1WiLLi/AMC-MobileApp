// GroupDemand.swift
// « Ce que le groupe veut » (S-07) : agrégat anonyme des envies d'un groupe.
// Swift pur, sans Firebase : les dépôts (fake et Firestore) et les ViewModels l'appellent.
//
// Règles :
// - Une ligne par couple (catégorie, unité) : on n'additionne pas des kg et des douzaines.
// - Total = somme des quantités ; ménages = nombre de ménages distincts (un ménage avec deux envies compte une fois).
// - Aucun id de ménage ne sort de l'agrégat : les familles voient « 7 familles veulent 64 kg de riz », pas qui.
// - Tri : plus de ménages d'abord, puis plus gros volume, puis ordre des catégories (stable).

import Foundation

nonisolated struct GroupDemand: Identifiable, Sendable, Hashable {
    var category: Product.Category
    var unit: MeasureUnit
    var totalQuantity: Double
    var householdCount: Int

    var id: String { "\(category.rawValue)-\(unit.rawValue)" }

    /// Agrège les envies données (normalement celles d'un seul groupe).
    static func aggregate(_ wishes: [GroupWish]) -> [GroupDemand] {
        struct Key: Hashable {
            var category: Product.Category
            var unit: MeasureUnit
        }
        var totals: [Key: Double] = [:]
        var households: [Key: Set<String>] = [:]
        for wish in wishes where wish.quantity > 0 {
            let key = Key(category: wish.category, unit: wish.unit)
            totals[key, default: 0] += wish.quantity
            households[key, default: []].insert(wish.householdId)
        }
        let categoryOrder = Product.Category.allCases
        let unitOrder = MeasureUnit.allCases
        return totals
            .map { key, total in
                GroupDemand(category: key.category, unit: key.unit, totalQuantity: total,
                            householdCount: households[key, default: []].count)
            }
            .sorted { lhs, rhs in
                if lhs.householdCount != rhs.householdCount { return lhs.householdCount > rhs.householdCount }
                if lhs.totalQuantity != rhs.totalQuantity { return lhs.totalQuantity > rhs.totalQuantity }
                let lhsCategory = categoryOrder.firstIndex(of: lhs.category) ?? 0
                let rhsCategory = categoryOrder.firstIndex(of: rhs.category) ?? 0
                if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
                return (unitOrder.firstIndex(of: lhs.unit) ?? 0) < (unitOrder.firstIndex(of: rhs.unit) ?? 0)
            }
    }
}
