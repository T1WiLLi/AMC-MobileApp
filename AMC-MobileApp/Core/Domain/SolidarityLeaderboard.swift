// SolidarityLeaderboard.swift
// RQ-093 (T-114) : classement solidaire et bienveillant des arrondissements de Montréal.
//
// Règles :
// - Quatre mesures, toutes RAPPORTÉES AU MÉNAGE pour qu'un petit arrondissement puisse gagner :
//   paniers suspendus offerts, familles aidées, économies, taux de participation.
// - Lissage (moyenne bayésienne) : chaque arrondissement reçoit `priorHouseholds` ménages fictifs
//   à la moyenne de la ville. Un arrondissement de 3 ménages très généreux n'écrase donc pas tout le monde,
//   mais un petit arrondissement constant finit devant un grand.
// - Chaque mesure est ramenée entre 0 et 1 (divisée par le meilleur), puis pondérée : score sur 100.
// - Égalité de score (au dixième) = même rang. Un arrondissement sans ménage n'est pas classé.
// - Ton positif : on dit à chacun sa force et combien de points le séparent du rang suivant, jamais « dernier ».
// Pur : aucune dépendance à Firebase ni à SwiftUI.

import Foundation

nonisolated enum SolidarityLeaderboard {
    /// Mesure du classement.
    enum Metric: String, CaseIterable, Sendable, Hashable, Identifiable {
        case baskets
        case familiesHelped
        case savings
        case participation

        var id: String { rawValue }

        /// Poids dans le score global (somme = 1). La solidarité pèse plus que les économies.
        var weight: Double {
            switch self {
            case .baskets: 0.35
            case .familiesHelped: 0.25
            case .savings: 0.20
            case .participation: 0.20
            }
        }

        var title: String {
            switch self {
            case .baskets: "Paniers offerts"
            case .familiesHelped: "Familles aidées"
            case .savings: "Économies"
            case .participation: "Participation"
            }
        }

        /// Titre bienveillant donné au meilleur arrondissement de la mesure.
        var championTitle: String {
            switch self {
            case .baskets: "Le plus généreux"
            case .familiesHelped: "Le plus entraidant"
            case .savings: "Le plus économe"
            case .participation: "Le plus mobilisé"
            }
        }

        var systemImage: String {
            switch self {
            case .baskets: "basket.fill"
            case .familiesHelped: "figure.2.and.child.holdinghands"
            case .savings: "dollarsign.arrow.circlepath"
            case .participation: "person.3.fill"
            }
        }
    }

    /// Un arrondissement classé.
    struct Entry: Identifiable, Sendable, Hashable {
        var stats: BoroughStats
        /// Rang (1 = en tête) ; deux scores égaux partagent le rang.
        var rank: Int
        /// Score global sur 100 (ou valeur normalisée × 100 de la mesure choisie).
        var score: Double
        /// Valeur lissée par ménage de chaque mesure (paniers par ménage, cents par ménage, taux 0…1).
        var perHousehold: [Metric: Double]
        /// Valeur ramenée entre 0 et 1 (1 = le meilleur de la ville).
        var normalized: [Metric: Double]
        /// Mesure où l'arrondissement brille le plus (sa « force »).
        var strength: Metric
        /// Mesures où il est premier de la ville.
        var championOf: [Metric]
        /// Arrondissement du ménage connecté.
        var isHome: Bool
        /// Points à gagner pour rejoindre le rang au-dessus ; nil en tête.
        var pointsToNextRank: Double?

        var id: String { stats.id }
        var isPodium: Bool { rank <= 3 }
    }

    /// Ménages fictifs ajoutés à la moyenne de la ville (lissage).
    static let priorHouseholds = 20.0

    /// Classement des arrondissements. `metric == nil` : score global pondéré ; sinon, la mesure seule.
    /// `homeNeighborhood` : quartier du groupe du ménage (`NeighborhoodGroup.neighborhood`) ou nom d'arrondissement.
    static func ranking(_ stats: [BoroughStats], metric: Metric? = nil, homeNeighborhood: String? = nil) -> [Entry] {
        let ranked = stats.filter { $0.households > 0 }
        guard !ranked.isEmpty else { return [] }

        let totalHouseholds = Double(ranked.reduce(0) { $0 + $1.households })
        let cityRates: [Metric: Double] = Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
            (metric, ranked.reduce(0.0) { $0 + rawValue(metric, of: $1) } / totalHouseholds)
        })

        let smoothed: [[Metric: Double]] = ranked.map { borough in
            let households = Double(borough.households)
            return Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
                let value = (rawValue(metric, of: borough) + priorHouseholds * (cityRates[metric] ?? 0))
                    / (households + priorHouseholds)
                return (metric, value)
            })
        }
        let best: [Metric: Double] = Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
            (metric, smoothed.map { $0[metric] ?? 0 }.max() ?? 0)
        })
        let normalized: [[Metric: Double]] = smoothed.map { values in
            Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
                let top = best[metric] ?? 0
                return (metric, top > 0 ? min(1, (values[metric] ?? 0) / top) : 0)
            })
        }

        var entries: [Entry] = ranked.indices.map { index in
            let values = normalized[index]
            let score: Double = if let metric {
                (values[metric] ?? 0) * 100
            } else {
                Metric.allCases.reduce(0.0) { $0 + $1.weight * (values[$1] ?? 0) } * 100
            }
            let strength = Metric.allCases.max { (values[$0] ?? 0) < (values[$1] ?? 0) } ?? .baskets
            let champion = Metric.allCases.filter { (best[$0] ?? 0) > 0 && (values[$0] ?? 0) >= 1 - 1e-9 }
            return Entry(stats: ranked[index], rank: 0, score: rounded(score), perHousehold: smoothed[index],
                         normalized: values, strength: strength, championOf: champion,
                         isHome: isHome(ranked[index], homeNeighborhood: homeNeighborhood), pointsToNextRank: nil)
        }

        entries.sort { $0.score != $1.score ? $0.score > $1.score : $0.stats.name < $1.stats.name }
        var previousScore: Double?
        var previousRank = 0
        for index in entries.indices {
            let rank = entries[index].score == previousScore ? previousRank : index + 1
            entries[index].rank = rank
            previousScore = entries[index].score
            previousRank = rank
            // Premier score strictement au-dessus : la marche suivante.
            if let above = entries[..<index].last(where: { $0.score > entries[index].score }) {
                entries[index].pointsToNextRank = rounded(above.score - entries[index].score)
            }
        }
        return entries
    }

    /// Phrase d'encouragement : toujours positive.
    static func cheer(for entry: Entry) -> String {
        if entry.rank == 1 { return "En tête de Montréal : bravo !" }
        if let first = entry.championOf.first { return "\(first.championTitle) de la ville" }
        if let points = entry.pointsToNextRank {
            let formatted = points.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))
            return entry.rank <= 3
                ? "Plus que \(formatted) pts pour monter sur la marche au-dessus"
                : "Plus que \(formatted) pts pour gagner une place"
        }
        return "Belle force : \(entry.strength.title.lowercased())"
    }

    /// Valeur brute d'une mesure (total de l'arrondissement ; ménages actifs pour la participation).
    static func rawValue(_ metric: Metric, of stats: BoroughStats) -> Double {
        switch metric {
        case .baskets: Double(max(stats.basketsOffered, 0))
        case .familiesHelped: Double(max(stats.familiesHelped, 0))
        case .savings: Double(max(stats.savingsCents, 0))
        case .participation: Double(min(max(stats.activeHouseholds, 0), stats.households))
        }
    }

    /// Le quartier du ménage appartient-il à cet arrondissement ? (casse et accents ignorés)
    static func isHome(_ stats: BoroughStats, homeNeighborhood: String?) -> Bool {
        guard let home = homeNeighborhood.map(normalizedName), !home.isEmpty else { return false }
        return ([stats.name, stats.shortName, stats.id] + stats.neighborhoods).contains { normalizedName($0) == home }
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
