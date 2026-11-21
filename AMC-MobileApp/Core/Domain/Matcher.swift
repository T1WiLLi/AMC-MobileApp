// Matcher.swift
// Rapprochement « ce que les familles veulent » ↔ « ce que le vendeur a » (S-09).
// Swift pur, sans Firebase : prend des envies (`GroupWish`), la zone de chaque groupe et des
// disponibilités (`VendorSupply`), et renvoie les paires groupe ↔ vendeur classées par volume.
//
// Règles :
// - Une envie et une disponibilité se rencontrent si :
//     · même catégorie et même unité (pas de conversion) ;
//     · si les deux visent un produit précis, c'est le même produit ;
//     · la zone du groupe (son `centerGeohash`) commence par une des zones desservies (préfixe geohash) ;
//     · leurs périodes se chevauchent (bornes incluses ; une borne nil de l'envie = sans limite).
// - Pour une paire (groupe, vendeur), une ligne par (catégorie, unité) :
//     · voulu = somme des envies du groupe qui rencontrent au moins une disponibilité du vendeur ;
//     · disponible = somme des disponibilités du vendeur qui rencontrent au moins une de ces envies ;
//     · servi = min(voulu, disponible) ; la ligne est partielle si disponible < voulu.
// - Chaque paire est évaluée seule : une même disponibilité peut apparaître pour plusieurs groupes
//   (le vendeur choisit ensuite à qui proposer un lot).
// - Classement : volume servi décroissant, puis taux de couverture, puis nombre de ménages, puis ids.
// - Une envie d'un groupe dont la zone est inconnue est ignorée.

import Foundation

nonisolated enum Matcher {
    /// Une catégorie servie par un vendeur pour un groupe.
    nonisolated struct Line: Sendable, Hashable {
        var category: Product.Category
        var unit: MeasureUnit
        var wantedQuantity: Double
        var availableQuantity: Double
        /// Ménages distincts derrière `wantedQuantity` (jamais leurs ids : l'agrégat reste anonyme).
        var householdCount: Int
        var supplyIds: [String]

        var matchedQuantity: Double { min(wantedQuantity, availableQuantity) }
        /// Le vendeur n'a pas tout ce que le groupe veut.
        var isPartial: Bool { availableQuantity < wantedQuantity }
        /// Part de la demande couverte, entre 0 et 1.
        var coverage: Double { wantedQuantity > 0 ? matchedQuantity / wantedQuantity : 0 }
    }

    /// Paire groupe ↔ vendeur.
    nonisolated struct Match: Identifiable, Sendable, Hashable {
        var groupId: String
        var vendorId: String
        /// Lignes, de la plus grosse à la plus petite.
        var lines: [Line]
        /// Ménages distincts du groupe servis par au moins une ligne.
        var householdCount: Int

        var id: String { "\(groupId)|\(vendorId)" }
        var matchedQuantity: Double { lines.reduce(0) { $0 + $1.matchedQuantity } }
        var wantedQuantity: Double { lines.reduce(0) { $0 + $1.wantedQuantity } }
        var isPartial: Bool { lines.contains(where: \.isPartial) }
        var coverage: Double { wantedQuantity > 0 ? matchedQuantity / wantedQuantity : 0 }
    }

    /// Paires classées par volume. `groupGeohashes` : zone de chaque groupe (id → `centerGeohash`).
    static func matches(
        wishes: [GroupWish],
        groupGeohashes: [String: String],
        supplies: [VendorSupply]
    ) -> [Match] {
        let wishesByGroup = Dictionary(grouping: wishes.filter { $0.quantity > 0 }, by: \.groupId)
        let suppliesByVendor = Dictionary(grouping: supplies.filter { $0.quantity > 0 }, by: \.vendorId)

        var result: [Match] = []
        for (groupId, groupWishes) in wishesByGroup {
            guard let geohash = groupGeohashes[groupId]?.lowercased(), !geohash.isEmpty else { continue }
            for (vendorId, vendorSupplies) in suppliesByVendor {
                let reachable = vendorSupplies.filter { serves($0, geohash: geohash) }
                guard !reachable.isEmpty,
                      let match = match(groupId: groupId, vendorId: vendorId, wishes: groupWishes, supplies: reachable)
                else { continue }
                result.append(match)
            }
        }
        return result.sorted(by: ranksBefore)
    }

    /// Même chose, avec les groupes eux-mêmes.
    static func matches(wishes: [GroupWish], groups: [NeighborhoodGroup], supplies: [VendorSupply]) -> [Match] {
        let geohashes = Dictionary(groups.map { ($0.id, $0.centerGeohash) }, uniquingKeysWith: { first, _ in first })
        return matches(wishes: wishes, groupGeohashes: geohashes, supplies: supplies)
    }

    // MARK: - Critères

    /// La zone du groupe commence par une des zones desservies.
    static func serves(_ supply: VendorSupply, geohash: String) -> Bool {
        let geohash = geohash.lowercased()
        return supply.servedZones.contains { zone in
            !zone.isEmpty && geohash.hasPrefix(zone.lowercased())
        }
    }

    /// Les périodes se chevauchent (bornes incluses).
    static func periodsOverlap(_ wish: GroupWish, _ supply: VendorSupply) -> Bool {
        let wishStart = wish.wantedFrom ?? .distantPast
        let wishEnd = wish.wantedUntil ?? .distantFuture
        return wishStart <= supply.availableTo && supply.availableFrom <= wishEnd
    }

    /// Catégorie, unité, produit et période compatibles (la zone est vérifiée à part).
    static func isCompatible(_ wish: GroupWish, _ supply: VendorSupply) -> Bool {
        guard wish.category == supply.category, wish.unit == supply.unit else { return false }
        if let wanted = wish.productId, let offered = supply.productId, wanted != offered { return false }
        return periodsOverlap(wish, supply)
    }

    // MARK: - Calcul d'une paire

    private static func match(
        groupId: String,
        vendorId: String,
        wishes: [GroupWish],
        supplies: [VendorSupply]
    ) -> Match? {
        struct Key: Hashable {
            var category: Product.Category
            var unit: MeasureUnit
        }
        var lines: [Line] = []
        var servedHouseholds: Set<String> = []
        let wishesByKey = Dictionary(grouping: wishes) { Key(category: $0.category, unit: $0.unit) }
        for (key, keyWishes) in wishesByKey {
            let keySupplies = supplies.filter { $0.category == key.category && $0.unit == key.unit }
            let metWishes = keyWishes.filter { wish in keySupplies.contains { isCompatible(wish, $0) } }
            let usedSupplies = keySupplies.filter { supply in metWishes.contains { isCompatible($0, supply) } }
            guard !metWishes.isEmpty, !usedSupplies.isEmpty else { continue }
            let households = Set(metWishes.map(\.householdId))
            servedHouseholds.formUnion(households)
            lines.append(Line(
                category: key.category,
                unit: key.unit,
                wantedQuantity: metWishes.reduce(0) { $0 + $1.quantity },
                availableQuantity: usedSupplies.reduce(0) { $0 + $1.quantity },
                householdCount: households.count,
                supplyIds: usedSupplies.map(\.id).sorted()
            ))
        }
        guard !lines.isEmpty else { return nil }
        lines.sort { lhs, rhs in
            if lhs.matchedQuantity != rhs.matchedQuantity { return lhs.matchedQuantity > rhs.matchedQuantity }
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            return lhs.unit.rawValue < rhs.unit.rawValue
        }
        return Match(groupId: groupId, vendorId: vendorId, lines: lines, householdCount: servedHouseholds.count)
    }

    private static func ranksBefore(_ lhs: Match, _ rhs: Match) -> Bool {
        if lhs.matchedQuantity != rhs.matchedQuantity { return lhs.matchedQuantity > rhs.matchedQuantity }
        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        if lhs.householdCount != rhs.householdCount { return lhs.householdCount > rhs.householdCount }
        if lhs.groupId != rhs.groupId { return lhs.groupId < rhs.groupId }
        return lhs.vendorId < rhs.vendorId
    }
}
