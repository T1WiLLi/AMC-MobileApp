// FakeData+Matching.swift
// Envies des familles (S-07) et disponibilités des vendeurs (S-08) de démo, cohérentes avec `FakeData.montreal` :
// Saint-Michel (f25dv, Amina + 11 ménages voisins) et Hochelaga (f25ej) veulent du riz, des œufs, des légumes ;
// Ferme Bio-Rive (f25d, f25e) et Les Moulins du Nord (f25d) ont des stocks sur les prochaines semaines.
// Le `Matcher` y trouve : Saint-Michel ↔ Moulins du Nord (céréales, légumineuses, farine partielle),
// Saint-Michel ↔ Bio-Rive (légumes, œufs), Hochelaga ↔ Bio-Rive (légumes, œufs).
// Hochelaga ↔ Moulins du Nord : hors zone. Les huiles de Saint-Michel : aucun vendeur.

import Foundation

nonisolated extension FakeData {
    /// Envies de démo, toutes catégories confondues.
    static let demoWishes: [GroupWish] = {
        typealias ID = FakeData.ID
        let now = Date.now
        let day: TimeInterval = 86_400
        let created = now.addingTimeInterval(-5 * day)
        var index = 0

        func wish(
            _ groupId: String, _ householdId: String, _ category: Product.Category, _ quantity: Double,
            _ unit: MeasureUnit, _ frequency: GroupWish.Frequency, productId: String? = nil, untilDays: Double? = nil
        ) -> GroupWish {
            index += 1
            return GroupWish(
                id: "wish-demo-\(index)", groupId: groupId, householdId: householdId, category: category,
                productId: productId, quantity: quantity, unit: unit, frequency: frequency,
                wantedFrom: nil, wantedUntil: untilDays.map { now.addingTimeInterval($0 * day) },
                createdAt: created.addingTimeInterval(Double(index) * 600),
                updatedAt: created.addingTimeInterval(Double(index) * 600)
            )
        }

        let saintMichel = ID.saintMichel
        let hochelaga = ID.hochelaga
        return [
            // Saint-Michel : la famille Benali et ses voisins.
            wish(saintMichel, ID.aminaHousehold, .grains, 10, .kilogram, .monthly, productId: ID.rice),
            wish(saintMichel, ID.aminaHousehold, .eggs, 2, .dozen, .weekly),
            wish(saintMichel, ID.aminaHousehold, .oils, 3, .liter, .monthly),
            wish(saintMichel, "household-voisin-1", .grains, 10, .kilogram, .monthly),
            wish(saintMichel, "household-voisin-2", .legumes, 5, .kilogram, .monthly),
            wish(saintMichel, "household-voisin-3", .flour, 10, .kilogram, .monthly),
            wish(saintMichel, "household-voisin-4", .eggs, 3, .dozen, .weekly),
            wish(saintMichel, "household-voisin-5", .grains, 20, .kilogram, .monthly, productId: ID.rice),
            wish(saintMichel, "household-voisin-6", .produce, 10, .kilogram, .biweekly),
            wish(saintMichel, "household-voisin-7", .oils, 2, .liter, .monthly),
            wish(saintMichel, "household-voisin-8", .produce, 20, .kilogram, .biweekly, untilDays: 30),
            wish(saintMichel, "household-voisin-9", .legumes, 4, .kilogram, .once, untilDays: 21),
            // Hochelaga : ménages de démo sans fiche (le groupe n'a pas de membres dans `montreal`).
            wish(hochelaga, "household-hochelaga-1", .produce, 15, .kilogram, .weekly),
            wish(hochelaga, "household-hochelaga-2", .produce, 20, .kilogram, .weekly),
            wish(hochelaga, "household-hochelaga-3", .produce, 25, .kilogram, .biweekly),
            wish(hochelaga, "household-hochelaga-3", .eggs, 2, .dozen, .weekly),
            wish(hochelaga, "household-hochelaga-4", .grains, 10, .kilogram, .monthly),
        ]
    }()

    /// Disponibilités de démo des deux vendeurs de `montreal`.
    static let demoSupplies: [VendorSupply] = {
        typealias ID = FakeData.ID
        let now = Date.now
        let day: TimeInterval = 86_400
        let created = now.addingTimeInterval(-3 * day)

        func supply(
            _ id: String, _ vendorId: String, _ category: Product.Category, _ quantity: Double, _ unit: MeasureUnit,
            fromDays: Double, toDays: Double, zones: [String], productId: String? = nil
        ) -> VendorSupply {
            VendorSupply(
                id: id, vendorId: vendorId, category: category, productId: productId, quantity: quantity, unit: unit,
                availableFrom: now.addingTimeInterval(fromDays * day), availableTo: now.addingTimeInterval(toDays * day),
                servedZones: zones, createdAt: created, updatedAt: created
            )
        }

        return [
            // Ferme Bio-Rive : Mirabel, livre Saint-Michel et Hochelaga.
            supply("supply-bio-rive-pommes-de-terre", ID.fermeRive, .produce, 40, .kilogram,
                   fromDays: 1, toDays: 21, zones: ["f25d", "f25e"], productId: ID.potatoes),
            supply("supply-bio-rive-pommes", ID.fermeRive, .produce, 25, .kilogram,
                   fromDays: 3, toDays: 28, zones: ["f25e"], productId: ID.apples),
            supply("supply-bio-rive-oeufs", ID.fermeRive, .eggs, 30, .dozen,
                   fromDays: 0, toDays: 14, zones: ["f25d", "f25e"]),
            // Les Moulins du Nord : Laval, ne livre que Saint-Michel (f25d).
            supply("supply-moulins-riz", ID.moulinsDuNord, .grains, 200, .kilogram,
                   fromDays: 2, toDays: 45, zones: ["f25d"], productId: ID.rice),
            supply("supply-moulins-lentilles", ID.moulinsDuNord, .legumes, 60, .kilogram,
                   fromDays: 2, toDays: 45, zones: ["f25d"]),
            supply("supply-moulins-farine", ID.moulinsDuNord, .flour, 5, .kilogram,
                   fromDays: 7, toDays: 30, zones: ["f25d"]),
        ]
    }()
}
