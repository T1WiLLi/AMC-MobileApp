// SavingsCalculator.swift
// E12 Économies (RQ-089, RQ-090, RQ-092) : économies par part, par mois et au total pour un ménage,
// un groupe et un quartier, kilos achetés en vrac et emballages évités.
// Swift pur : aucune dépendance à Firebase ni à l'UI, les entrées sont passées en paramètres.

import Foundation

// MARK: - Mesure d'une part (RQ-092)

/// Ce que contient une part, lu dans `Offer.shareUnit` (« 10 kg », « sac de 2,5 kg », « 5 L », « 12 unités »…).
nonisolated enum ShareMeasure: Sendable, Equatable, Hashable {
    /// Masse, en kilogrammes.
    case mass(kilograms: Double)
    /// Volume, en litres.
    case volume(liters: Double)
    /// Nombre d'unités (« 12 unités », « 1 douzaine », « 1 caisse »).
    case count(units: Int)
    /// Rien d'exploitable (texte vide, « caisse » sans nombre…).
    case unknown

    /// Format d'épicerie de référence : une part en vrac remplace des formats de 1 kg (ou 1 L).
    /// Heuristique documentée : c'est le format le plus courant en épicerie pour le riz, les légumineuses,
    /// la farine, l'huile et le lait.
    static let retailPackageKilograms = 1.0

    /// Masse d'un emballage d'épicerie (sac, boîte ou bouteille de 1 kg) : environ 30 g.
    static let packagingKilogramsPerRetailPackage = 0.03

    /// Kilos équivalents d'une part.
    /// - masse : telle quelle ;
    /// - volume : 1 L ≈ 1 kg (densité de l'eau, assez proche pour l'huile, le lait ou le sirop) ;
    /// - unités ou inconnu : 0 (on ne devine pas le poids d'une caisse).
    var kilograms: Double {
        switch self {
        case .mass(let kilograms): kilograms
        case .volume(let liters): liters
        case .count, .unknown: 0
        }
    }

    /// Emballages d'épicerie évités par une part : `max(0, ⌈kg ÷ 1 kg⌉ − 1)`.
    /// Une part de 10 kg remplace 10 formats de 1 kg mais arrive elle-même dans 1 emballage : 9 évités.
    /// Les parts en unités ne comptent pas (une douzaine d'œufs reste une boîte).
    var retailPackagesAvoided: Int {
        let kilograms = kilograms
        guard kilograms > 0 else { return 0 }
        let packages = Int((kilograms / Self.retailPackageKilograms - 1e-9).rounded(.up))
        return max(0, packages - 1)
    }

    /// Lit une unité de part écrite à la main. Robuste aux formes courantes :
    /// « 10 kg », « 10kg », « sac de 2,5 kg », « 500 g », « 2 x 5 kg », « 2 sacs de 5 kg », « 6 × 500 ml »,
    /// « 5 L », « 4 litres », « 75 cl », « 10 lb », « 12 unités », « 1 douzaine », « demi-douzaine », « kg ».
    /// La première masse ou le premier volume trouvé l'emporte ; sinon un nombre donne des unités.
    static func parse(_ text: String) -> ShareMeasure {
        let tokens = tokenize(text)
        func number(at index: Int) -> Double? {
            tokens.indices.contains(index) ? Double(tokens[index]) : nil
        }

        // 1. Masse ou volume : un nombre suivi d'une unité connue, avec un multiplicateur éventuel.
        for index in tokens.indices {
            guard let amount = number(at: index), tokens.indices.contains(index + 1),
                  let unit = measureUnits[tokens[index + 1]] else { continue }
            var multiplier = 1.0
            if index >= 2, tokens[index - 1] == "x", let factor = number(at: index - 2) {
                multiplier = factor // « 2 x 5 kg »
            } else if index >= 3, tokens[index - 1] == "de", let factor = number(at: index - 3) {
                multiplier = factor // « 2 sacs de 5 kg »
            }
            let total = amount * multiplier * unit.factor
            guard total > 0 else { continue }
            return unit.isVolume ? .volume(liters: total) : .mass(kilograms: total)
        }

        // 2. Douzaines : « 1 douzaine », « 2 douzaines », « demi-douzaine ».
        if let index = tokens.firstIndex(where: { $0 == "douzaine" || $0 == "douzaines" }) {
            let factor = index > 0 ? (tokens[index - 1] == "demi" ? 0.5 : number(at: index - 1) ?? 1) : 1
            let units = Int((12 * factor).rounded())
            return units > 0 ? .count(units: units) : .unknown
        }

        // 3. Un nombre seul ou suivi d'un autre mot : des unités (« 12 unités », « 1 caisse »).
        if let first = tokens.compactMap(Double.init).first {
            let units = Int(first.rounded(.down))
            return units > 0 ? .count(units: units) : .unknown
        }

        // 4. Une unité sans nombre : « kg » vaut 1 kg, « litre » vaut 1 L.
        if let unit = tokens.lazy.compactMap({ measureUnits[$0] }).first {
            return unit.isVolume ? .volume(liters: unit.factor) : .mass(kilograms: unit.factor)
        }
        return .unknown
    }

    /// Unités reconnues, ramenées en kg (masse) ou en L (volume). Les accents sont retirés avant la recherche.
    private static let measureUnits: [String: (factor: Double, isVolume: Bool)] = [
        "kg": (1, false), "kgs": (1, false), "kilo": (1, false), "kilos": (1, false),
        "kilogramme": (1, false), "kilogrammes": (1, false),
        "g": (0.001, false), "gr": (0.001, false), "gramme": (0.001, false), "grammes": (0.001, false),
        "lb": (0.453_592, false), "lbs": (0.453_592, false), "livre": (0.453_592, false), "livres": (0.453_592, false),
        "l": (1, true), "litre": (1, true), "litres": (1, true),
        "ml": (0.001, true), "cl": (0.01, true),
    ]

    /// Découpe en nombres (virgule ou point décimal) et en mots, en minuscules et sans accents.
    /// « 2,5kg » → ["2.5", "kg"], « 6×500 ml » → ["6", "x", "500", "ml"], « demi-douzaine » → ["demi", "douzaine"].
    private static func tokenize(_ text: String) -> [String] {
        let folded = text
            .replacingOccurrences(of: "×", with: " x ")
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
        var tokens: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        let characters = Array(folded)
        for (index, character) in characters.enumerated() {
            if character.isNumber {
                if !currentIsNumber { flush() }
                currentIsNumber = true
                current.append(character)
            } else if (character == "," || character == "."), currentIsNumber,
                      index + 1 < characters.count, characters[index + 1].isNumber {
                current.append(".")
            } else if character.isLetter {
                if currentIsNumber { flush() }
                currentIsNumber = false
                current.append(character)
            } else {
                flush()
                currentIsNumber = false
            }
        }
        flush()
        return tokens
    }
}

// MARK: - Entrée de calcul

/// Une part d'un ménage dans une commande groupée, avec tout ce qu'il faut pour calculer son économie.
/// Les prix et la date sont passés explicitement : `Share` ne porte pas toujours de date
/// et son `finalPriceCents` n'est rempli qu'à la clôture.
nonisolated struct SavingsEntry: Sendable, Equatable, Hashable {
    var householdId: String
    var groupOrderId: String
    var groupId: String
    /// Quartier du groupe (`NeighborhoodGroup.neighborhood`), pour les agrégats par quartier.
    var neighborhood: String
    var productId: String
    /// Catégorie du produit, pour l'indicateur santé ; nil si inconnue.
    var category: Product.Category?
    /// Date retenue pour le classement par mois (réservation, clôture ou cueillette, au choix de l'appelant).
    var date: Date
    /// Nombre de parts.
    var quantity: Int
    /// Prix d'épicerie de référence pour une part (`Product.referenceGroceryPriceCents`).
    var referenceUnitPriceCents: Cents
    /// Prix final payé pour une part (palier atteint, ou palier courant tant que la commande est ouverte).
    var finalUnitPriceCents: Cents
    /// Contenu d'une part (`ShareMeasure.parse(offer.shareUnit)`).
    var measure: ShareMeasure

    init(
        householdId: String,
        groupOrderId: String,
        groupId: String,
        neighborhood: String,
        productId: String,
        category: Product.Category? = nil,
        date: Date,
        quantity: Int,
        referenceUnitPriceCents: Cents,
        finalUnitPriceCents: Cents,
        measure: ShareMeasure = .unknown
    ) {
        self.householdId = householdId
        self.groupOrderId = groupOrderId
        self.groupId = groupId
        self.neighborhood = neighborhood
        self.productId = productId
        self.category = category
        self.date = date
        self.quantity = quantity
        self.referenceUnitPriceCents = referenceUnitPriceCents
        self.finalUnitPriceCents = finalUnitPriceCents
        self.measure = measure
    }

    /// Construit l'entrée à partir des modèles. Le prix unitaire et la date restent explicites
    /// (`Share.finalPriceCents` est un total figé à la clôture, et la date dépend de l'écran).
    init(
        share: Share,
        order: GroupOrder,
        offer: Offer,
        product: Product,
        neighborhood: String,
        date: Date,
        finalUnitPriceCents: Cents
    ) {
        self.init(
            householdId: share.householdId,
            groupOrderId: order.id,
            groupId: order.groupId,
            neighborhood: neighborhood,
            productId: product.id,
            category: product.category,
            date: date,
            quantity: share.quantity,
            referenceUnitPriceCents: product.referenceGroceryPriceCents,
            finalUnitPriceCents: finalUnitPriceCents,
            measure: ShareMeasure.parse(offer.shareUnit)
        )
    }

    /// Parts comptées : une quantité négative est traitée comme 0.
    var countedQuantity: Int { max(0, quantity) }

    /// RQ-089 : économie = (prix de référence − prix final) × quantité.
    /// Ramenée à 0 si le lot coûte plus cher que l'épicerie : on n'affiche jamais une « économie » négative.
    var savingsCents: Cents { max(0, referenceUnitPriceCents - finalUnitPriceCents) * countedQuantity }

    /// Ce que le ménage paie : prix final × quantité.
    var spentCents: Cents { finalUnitPriceCents * countedQuantity }

    /// Ce que les mêmes produits auraient coûté à l'épicerie : prix de référence × quantité.
    var groceryCents: Cents { referenceUnitPriceCents * countedQuantity }

    /// RQ-092 : kilos achetés en vrac = kg par part × quantité.
    var kilograms: Double { measure.kilograms * Double(countedQuantity) }

    /// RQ-092 : emballages évités = emballages évités par part × quantité.
    var packagesAvoided: Int { measure.retailPackagesAvoided * countedQuantity }
}

// MARK: - Agrégats

/// Totaux d'un ensemble de parts (un ménage, un mois, un groupe, un quartier ou la ville).
nonisolated struct SavingsSummary: Sendable, Equatable, Hashable {
    /// Σ économies des parts (RQ-089, RQ-090).
    var savingsCents: Cents = 0
    /// Σ prix final × quantité.
    var spentCents: Cents = 0
    /// Σ prix de référence × quantité.
    var groceryCents: Cents = 0
    /// Σ quantités.
    var shares: Int = 0
    /// Ménages distincts avec au moins une part.
    var householdCount: Int = 0
    /// Couples (ménage, commande) distincts : chaque participation aurait été un achat séparé à l'épicerie.
    var participations: Int = 0
    /// Commandes groupées distinctes.
    var orderCount: Int = 0
    /// Σ kilos achetés en vrac (RQ-092).
    var kilograms: Double = 0
    /// Kilos par catégorie de produit (catégorie inconnue exclue).
    var kilogramsByCategory: [Product.Category: Double] = [:]
    /// Σ emballages d'épicerie évités (RQ-092).
    var packagesAvoided: Int = 0

    static let empty = SavingsSummary()

    /// Masse d'emballage évitée : emballages évités × 30 g (`ShareMeasure.packagingKilogramsPerRetailPackage`).
    var packagingKilogramsAvoided: Double {
        Double(packagesAvoided) * ShareMeasure.packagingKilogramsPerRetailPackage
    }

    /// Économie relative : économies ÷ prix d'épicerie (0 si rien n'a été acheté).
    var savingsRate: Double { groceryCents > 0 ? Double(savingsCents) / Double(groceryCents) : 0 }
}

/// Économies d'un mois civil, à Montréal.
nonisolated struct MonthlySavings: Sendable, Equatable, Hashable, Identifiable {
    var year: Int
    var month: Int
    /// Premier instant du mois dans le fuseau du calendrier utilisé.
    var monthStart: Date
    var summary: SavingsSummary

    var id: String { String(format: "%04d-%02d", year, month) }
}

// MARK: - Calculs

nonisolated enum SavingsCalculator {
    /// Calendrier grégorien à l'heure de Montréal : une part réservée le 31 à 22 h reste dans son mois.
    static var montrealCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        calendar.locale = Locale(identifier: "fr_CA")
        return calendar
    }

    /// Totaux de toutes les entrées (RQ-089 total, RQ-090, RQ-092).
    static func summary(of entries: some Sequence<SavingsEntry>) -> SavingsSummary {
        var summary = SavingsSummary()
        var households: Set<String> = []
        var participations: Set<[String]> = []
        var orders: Set<String> = []
        for entry in entries where entry.countedQuantity > 0 {
            summary.savingsCents += entry.savingsCents
            summary.spentCents += entry.spentCents
            summary.groceryCents += entry.groceryCents
            summary.shares += entry.countedQuantity
            summary.kilograms += entry.kilograms
            summary.packagesAvoided += entry.packagesAvoided
            if let category = entry.category, entry.kilograms > 0 {
                summary.kilogramsByCategory[category, default: 0] += entry.kilograms
            }
            households.insert(entry.householdId)
            participations.insert([entry.householdId, entry.groupOrderId])
            orders.insert(entry.groupOrderId)
        }
        summary.householdCount = households.count
        summary.participations = participations.count
        summary.orderCount = orders.count
        return summary
    }

    /// RQ-089 : total d'un ménage.
    static func household(_ householdId: String, in entries: [SavingsEntry]) -> SavingsSummary {
        summary(of: entries.lazy.filter { $0.householdId == householdId })
    }

    /// RQ-090 : total d'un groupe.
    static func group(_ groupId: String, in entries: [SavingsEntry]) -> SavingsSummary {
        summary(of: entries.lazy.filter { $0.groupId == groupId })
    }

    /// RQ-090 : total d'un quartier (tous ses groupes).
    static func neighborhood(_ neighborhood: String, in entries: [SavingsEntry]) -> SavingsSummary {
        summary(of: entries.lazy.filter { $0.neighborhood == neighborhood })
    }

    /// RQ-089 : économies mois par mois, du plus ancien au plus récent ; les mois sans part sont absents.
    /// - Parameter calendar: injecté pour des tests déterministes ; par défaut l'heure de Montréal.
    static func monthly(_ entries: [SavingsEntry], calendar: Calendar = montrealCalendar) -> [MonthlySavings] {
        let buckets = Dictionary(grouping: entries.filter { $0.countedQuantity > 0 }) { entry in
            calendar.dateComponents([.year, .month], from: entry.date)
        }
        return buckets.compactMap { components, entries -> MonthlySavings? in
            guard let year = components.year, let month = components.month,
                  let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return MonthlySavings(year: year, month: month, monthStart: start, summary: summary(of: entries))
        }
        .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    /// RQ-090 : totaux par groupe.
    static func byGroup(_ entries: [SavingsEntry]) -> [String: SavingsSummary] {
        Dictionary(grouping: entries, by: \.groupId).mapValues { summary(of: $0) }
    }

    /// RQ-090 : totaux par quartier.
    static func byNeighborhood(_ entries: [SavingsEntry]) -> [String: SavingsSummary] {
        Dictionary(grouping: entries, by: \.neighborhood).mapValues { summary(of: $0) }
    }
}
