// SolidarityLeaderboardViewModel.swift
// RQ-093 (T-114) : classement solidaire des arrondissements, pour la section de l'onglet Impact et l'écran détail.
// Lit `boroughStats` (agrégats) et le quartier du groupe du ménage ; le classement est calculé par
// `SolidarityLeaderboard`, à nouveau à chaque changement de mesure (aucun appel réseau).

import Foundation
import Observation

@Observable
@MainActor
final class SolidarityLeaderboardViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var stats: [BoroughStats]
        /// Quartier du groupe du ménage (« Saint-Michel »), nil sans groupe.
        var homeNeighborhood: String?
    }

    private(set) var state: LoadState<Content> = .idle
    /// Mesure choisie dans l'écran détail ; nil = score global.
    var metric: SolidarityLeaderboard.Metric?

    private let repositories: AppRepositories
    private let groupId: String?

    init(repositories: AppRepositories, groupId: String?) {
        self.repositories = repositories
        self.groupId = groupId
    }

    /// Classement pour la mesure choisie.
    var entries: [SolidarityLeaderboard.Entry] {
        guard let content = state.value else { return [] }
        return SolidarityLeaderboard.ranking(content.stats, metric: metric, homeNeighborhood: content.homeNeighborhood)
    }

    /// Arrondissement du ménage, s'il est classé.
    var home: SolidarityLeaderboard.Entry? { entries.first(where: \.isHome) }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, groupId = groupId
        let result: LoadState<Content> = await .run {
            let stats = try await repositories.boroughStats.boroughStats()
            // Le quartier n'est qu'un surlignage : son absence ne bloque pas le classement.
            var neighborhood: String?
            if let groupId {
                neighborhood = try? await repositories.groups.group(id: groupId).neighborhood
            }
            return Content(stats: stats, homeNeighborhood: neighborhood)
        }
        if case .loaded(let content) = result, content.stats.allSatisfy({ $0.households <= 0 }) {
            state = .empty
        } else {
            state = result
        }
    }
}
