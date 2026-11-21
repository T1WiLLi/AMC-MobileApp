// ImpactMetrics.swift
// E12 « Impact sur Montréal » (RQ-128) : un indicateur par sphère pour un quartier et pour toute la ville.
// Calculé à partir des agrégats de SavingsCalculator (RQ-089, RQ-090, RQ-092) et de quelques entrées
// que les parts ne portent pas (paniers subventionnés, achats chez des producteurs locaux, cueillettes).
// Swift pur : aucune dépendance à Firebase ni à l'UI.

import Foundation

/// Les sept sphères de l'impact, dans l'ordre d'affichage.
nonisolated enum ImpactSphere: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case foodSecurity
    case localEconomy
    case neighborhoodLife
    case environment
    case mobility
    case inclusion
    case health

    var id: String { rawValue }

    /// Nom de la sphère, en français.
    var title: String {
        switch self {
        case .foodSecurity: String(localized: "Sécurité alimentaire")
        case .localEconomy: String(localized: "Économie locale")
        case .neighborhoodLife: String(localized: "Vie de quartier")
        case .environment: String(localized: "Environnement")
        case .mobility: String(localized: "Mobilité")
        case .inclusion: String(localized: "Inclusion")
        case .health: String(localized: "Santé")
        }
    }
}

/// Un indicateur d'impact : un chiffre, son unité et une phrase qui l'explique.
nonisolated struct ImpactIndicator: Sendable, Equatable, Hashable, Identifiable {
    var sphere: ImpactSphere
    /// Titre de l'indicateur, en français (« Emballages évités »).
    var title: String
    var value: Double
    /// Unité affichée après la valeur (« $ », « kg », « ménages »…).
    var unit: String
    /// Courte explication, au tutoiement.
    var explanation: String

    var id: ImpactSphere { sphere }

    /// Valeur arrondie au format québécois (« 1 234 », « 12,5 »), sans l'unité.
    var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_CA")))
    }
}

/// Ce que les parts ne disent pas, pour un quartier (ou la ville, en additionnant les quartiers).
nonisolated struct ImpactContext: Sendable, Equatable, Hashable {
    /// Paniers payés par le fonds de solidarité ou offerts par des voisins (paniers suspendus).
    var subsidizedBaskets: Int = 0
    /// Ménages au statut subventionné servis au moins une fois.
    var subsidizedHouseholds: Int = 0
    /// Part des achats payée à des producteurs et commerces québécois.
    var localVendorSpendCents: Cents = 0
    /// Déplacements réels vers un point de cueillette (un ménage qui récupère trois commandes d'un coup = 1).
    var pickupTrips: Int = 0

    static let empty = ImpactContext()

    /// Somme de plusieurs contextes (les quartiers d'une ville).
    static func combined(_ contexts: some Sequence<ImpactContext>) -> ImpactContext {
        contexts.reduce(into: ImpactContext()) { total, context in
            total.subsidizedBaskets += context.subsidizedBaskets
            total.subsidizedHouseholds += context.subsidizedHouseholds
            total.localVendorSpendCents += context.localVendorSpendCents
            total.pickupTrips += context.pickupTrips
        }
    }
}

/// Portée d'un rapport d'impact.
nonisolated enum ImpactScope: Sendable, Equatable, Hashable {
    case neighborhood(String)
    case city

    /// Titre de la section (« Impact sur Montréal », « Impact sur Rosemont »).
    var title: String {
        switch self {
        case .neighborhood(let name): String(localized: "Impact sur \(name)")
        case .city: String(localized: "Impact sur Montréal")
        }
    }
}

/// Un rapport complet : la portée, les agrégats et un indicateur par sphère.
nonisolated struct ImpactReport: Sendable, Equatable, Hashable {
    var scope: ImpactScope
    var savings: SavingsSummary
    var context: ImpactContext
    /// Sept indicateurs, dans l'ordre de `ImpactSphere.allCases`.
    var indicators: [ImpactIndicator]

    var title: String { scope.title }

    func indicator(_ sphere: ImpactSphere) -> ImpactIndicator? {
        indicators.first { $0.sphere == sphere }
    }
}

nonisolated enum ImpactMetrics {
    /// Distance moyenne d'un aller-retour à l'épicerie évité à Montréal, en km.
    /// Heuristique documentée : environ 3 km aller-retour en voiture ou en transport, hors centre-ville.
    static let averageGroceryTripKilometers = 3.0

    /// Catégories comptées pour la santé : aliments peu transformés, riches en fibres.
    static let healthyCategories: Set<Product.Category> = [.produce, .legumes, .grains]

    /// Rapport d'un quartier : filtre les entrées sur `neighborhood`.
    static func report(neighborhood: String, entries: [SavingsEntry], context: ImpactContext) -> ImpactReport {
        let savings = SavingsCalculator.neighborhood(neighborhood, in: entries)
        return ImpactReport(
            scope: .neighborhood(neighborhood), savings: savings, context: context,
            indicators: indicators(savings: savings, context: context)
        )
    }

    /// Rapport « Impact sur Montréal » : toutes les entrées, contextes des quartiers additionnés.
    /// - Parameter contexts: un contexte par quartier (clé = nom du quartier).
    static func cityReport(entries: [SavingsEntry], contexts: [String: ImpactContext]) -> ImpactReport {
        let savings = SavingsCalculator.summary(of: entries)
        let context = ImpactContext.combined(contexts.values)
        return ImpactReport(
            scope: .city, savings: savings, context: context,
            indicators: indicators(savings: savings, context: context)
        )
    }

    /// Un indicateur par sphère, dans l'ordre de `ImpactSphere.allCases`.
    static func indicators(savings: SavingsSummary, context: ImpactContext) -> [ImpactIndicator] {
        ImpactSphere.allCases.map { indicator($0, savings: savings, context: context) }
    }

    /// Formules, une par sphère :
    /// - Sécurité alimentaire : paniers solidaires = `context.subsidizedBaskets`.
    /// - Économie locale : $ chez des producteurs d'ici = `context.localVendorSpendCents ÷ 100`
    ///   (plafonné à `savings.spentCents`), avec la part en % dans l'explication.
    /// - Vie de quartier : ménages qui achètent ensemble = `savings.householdCount`.
    /// - Environnement : emballages évités = `savings.packagesAvoided` (RQ-092), masse en kg dans l'explication.
    /// - Mobilité : trajets évités = `max(0, savings.participations − context.pickupTrips)`
    ///   (chaque participation aurait été un aller-retour à l'épicerie), × 3 km dans l'explication.
    /// - Inclusion : ménages subventionnés servis = `context.subsidizedHouseholds`, en % des ménages actifs.
    /// - Santé : kg de fruits, légumes, légumineuses et céréales = Σ `savings.kilogramsByCategory` des `healthyCategories`.
    static func indicator(_ sphere: ImpactSphere, savings: SavingsSummary, context: ImpactContext) -> ImpactIndicator {
        switch sphere {
        case .foodSecurity:
            let baskets = max(0, context.subsidizedBaskets)
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Paniers solidaires"), value: Double(baskets),
                unit: baskets > 1 ? "paniers" : "panier",
                explanation: String(localized: "Paniers payés par le fonds de solidarité ou offerts par tes voisins.")
            )
        case .localEconomy:
            let local = min(max(0, context.localVendorSpendCents), savings.spentCents)
            let percent = percentage(local, of: savings.spentCents)
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Achats chez des producteurs d'ici"), value: Double(local) / 100, unit: "$",
                explanation: String(localized: "\(percent) % des achats vont à des fermes et commerces du Québec.")
            )
        case .neighborhoodLife:
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Ménages qui achètent ensemble"), value: Double(savings.householdCount),
                unit: savings.householdCount > 1 ? String(localized: "ménages") : String(localized: "ménage"),
                explanation: String(localized: "Familles qui ont réservé au moins une part avec leurs voisins.")
            )
        case .environment:
            let packaging = savings.packagingKilogramsAvoided
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Emballages évités"), value: Double(savings.packagesAvoided),
                unit: savings.packagesAvoided > 1 ? "emballages" : "emballage",
                explanation: String(localized: "Acheter en vrac remplace les formats de 1 kg : environ \(decimal(packaging)) kg d'emballage en moins.")
            )
        case .mobility:
            let trips = max(0, savings.participations - max(0, context.pickupTrips))
            let kilometers = Double(trips) * averageGroceryTripKilometers
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Trajets d'épicerie évités"), value: Double(trips),
                unit: trips > 1 ? "trajets" : "trajet",
                explanation: String(localized: "Une cueillette groupée près de chez toi remplace des allers-retours : environ \(decimal(kilometers)) km en moins.")
            )
        case .inclusion:
            let households = max(0, context.subsidizedHouseholds)
            let percent = percentage(households, of: savings.householdCount)
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Ménages subventionnés servis"), value: Double(households),
                unit: households > 1 ? String(localized: "ménages") : String(localized: "ménage"),
                explanation: String(localized: "\(percent) % des ménages actifs ont eu accès aux mêmes prix grâce à la solidarité.")
            )
        case .health:
            let kilograms = healthyCategories.reduce(0) { $0 + (savings.kilogramsByCategory[$1] ?? 0) }
            return ImpactIndicator(
                sphere: sphere, title: String(localized: "Aliments frais et légumineuses"), value: kilograms, unit: "kg",
                explanation: String(localized: "Fruits, légumes, légumineuses et céréales achetés en vrac par le quartier.")
            )
        }
    }

    /// Pourcentage entier arrondi, 0 si le total est nul.
    private static func percentage(_ part: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(part) / Double(total) * 100).rounded())
    }

    /// Nombre décimal au format québécois (« 2,7 »).
    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_CA")))
    }
}
