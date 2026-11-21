// InterestedGroupsViewModel.swift
// S-09 côté vendeur (T-110) : « Groupes intéressés » par ses disponibilités, via `Matcher` (T-088).
// L'agrégat reste anonyme : nombre de ménages et quantités par catégorie, jamais qui.
//
// Usage : `.task { await model.load() }` · `.refreshable { await model.load() }`
//         « Créer un lot ciblé » : `model.targetedSupply(for: interest)` → `TierEditorScreen(…, supply:)`.

import Foundation
import Observation

@Observable @MainActor
final class InterestedGroupsViewModel {
    nonisolated struct Interest: Identifiable, Sendable, Hashable {
        var group: NeighborhoodGroup
        var match: Matcher.Match

        var id: String { match.id }
        /// Plus grosse ligne (la première, `Matcher` les trie par volume).
        var topLine: Matcher.Line? { match.lines.first }
    }

    /// Groupes intéressés, du plus gros volume servi au plus petit ; `.empty` si aucun.
    private(set) var state: LoadState<[Interest]> = .idle

    let vendorId: String
    private let repositories: AppRepositories
    /// Disponibilités du vendeur chargées, pour préremplir un lot.
    private var supplies: [String: VendorSupply] = [:]

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            let mine = try await repositories.supplies.supplies(ofVendor: vendorId)
            supplies = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard !mine.isEmpty else {
                state = .empty
                return
            }
            let wishes = try await repositories.wishes.allWishes()
            let groups = try await repositories.groups.groups(inNeighborhood: nil)
            let groupsById = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let interests = Matcher.matches(wishes: wishes, groups: groups, supplies: mine)
                .filter { $0.vendorId == vendorId }
                .compactMap { match in groupsById[match.groupId].map { Interest(group: $0, match: match) } }
            state = .from(interests)
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Disponibilité de la plus grosse ligne, ciblée sur la zone du groupe : préremplit un lot pour ce groupe.
    func targetedSupply(for interest: Interest) -> VendorSupply? {
        guard let line = interest.topLine,
              let supply = line.supplyIds.lazy.compactMap({ self.supplies[$0] }).first else { return nil }
        var targeted = supply
        targeted.servedZones = [interest.group.centerGeohash.lowercased()]
        return targeted
    }
}
