// FakeBoroughStatsRepository.swift
// Agrégats des arrondissements en mémoire (RQ-093, T-114), pour les previews, les tests et le mode fake.

import Foundation

actor FakeBoroughStatsRepository: BoroughStatsRepository {
    private let behavior: FakeBehavior
    private let stats: [BoroughStats]

    init(behavior: FakeBehavior = .instant, stats: [BoroughStats] = []) {
        self.behavior = behavior
        self.stats = stats
    }

    func boroughStats() async throws -> [BoroughStats] {
        try await behavior.simulate()
        return stats.sorted { $0.id < $1.id }
    }
}

nonisolated extension FakeData {
    /// Douze arrondissements de Montréal, chiffres du mois (fictifs mais plausibles).
    /// Lachine (64 ménages) est petit mais très actif : il doit pouvoir monter sur le podium.
    static let montrealBoroughs: [BoroughStats] = [
        borough("villeray-saint-michel-parc-extension", "Villeray–Saint-Michel–Parc-Extension", "Saint-Michel",
                ["Villeray", "Saint-Michel", "Parc-Extension"], "f25eht",
                households: 412, active: 268, groups: 6, baskets: 184, helped: 97, savings: 3_708_000),
        borough("mercier-hochelaga-maisonneuve", "Mercier–Hochelaga-Maisonneuve", "Hochelaga",
                ["Hochelaga", "Maisonneuve", "Mercier"], "f25eq8",
                households: 356, active: 201, groups: 5, baskets: 171, helped: 88, savings: 2_960_000),
        borough("rosemont-la-petite-patrie", "Rosemont–La Petite-Patrie", "Rosemont",
                ["Rosemont", "La Petite-Patrie"], "f25ejs",
                households: 498, active: 287, groups: 7, baskets: 152, helped: 70, savings: 4_410_000),
        borough("le-plateau-mont-royal", "Le Plateau-Mont-Royal", "Plateau",
                ["Plateau", "Mile End"], "f25dvx",
                households: 301, active: 162, groups: 4, baskets: 98, helped: 41, savings: 2_540_000),
        borough("le-sud-ouest", "Le Sud-Ouest", "Sud-Ouest",
                ["Saint-Henri", "Pointe-Saint-Charles", "Petite-Bourgogne"], "f25dtw",
                households: 214, active: 139, groups: 3, baskets: 121, helped: 66, savings: 1_880_000),
        borough("verdun", "Verdun", "Verdun",
                ["Verdun", "Île-des-Sœurs"], "f25dtf",
                households: 187, active: 104, groups: 3, baskets: 74, helped: 39, savings: 1_610_000),
        borough("cote-des-neiges-notre-dame-de-grace", "Côte-des-Neiges–Notre-Dame-de-Grâce", "CDN–NDG",
                ["Côte-des-Neiges", "Notre-Dame-de-Grâce"], "f25dsx",
                households: 389, active: 198, groups: 5, baskets: 117, helped: 58, savings: 3_120_000),
        borough("ahuntsic-cartierville", "Ahuntsic-Cartierville", "Ahuntsic",
                ["Ahuntsic", "Cartierville"], "f25e5t",
                households: 262, active: 141, groups: 4, baskets: 83, helped: 44, savings: 2_150_000),
        borough("montreal-nord", "Montréal-Nord", "Montréal-Nord",
                ["Montréal-Nord"], "f25ekk",
                households: 143, active: 101, groups: 2, baskets: 96, helped: 71, savings: 1_390_000),
        borough("ville-marie", "Ville-Marie", "Ville-Marie",
                ["Centre-Sud", "Centre-ville", "Vieux-Montréal"], "f25dvg",
                households: 120, active: 58, groups: 2, baskets: 41, helped: 22, savings: 860_000),
        borough("lachine", "Lachine", "Lachine",
                ["Lachine"], "f25de2",
                households: 64, active: 49, groups: 1, baskets: 52, helped: 31, savings: 690_000),
        borough("saint-laurent", "Saint-Laurent", "Saint-Laurent",
                ["Saint-Laurent"], "f25dgj",
                households: 176, active: 82, groups: 2, baskets: 49, helped: 25, savings: 1_350_000),
    ]

    // swiftlint:disable:next function_parameter_count
    private static func borough(
        _ id: String, _ name: String, _ shortName: String, _ neighborhoods: [String], _ geohash: String,
        households: Int, active: Int, groups: Int, baskets: Int, helped: Int, savings: Cents
    ) -> BoroughStats {
        BoroughStats(id: id, name: name, shortName: shortName, neighborhoods: neighborhoods, centerGeohash: geohash,
                     households: households, activeHouseholds: active, groupCount: groups, basketsOffered: baskets,
                     familiesHelped: helped, savingsCents: savings, updatedAt: nil)
    }
}
