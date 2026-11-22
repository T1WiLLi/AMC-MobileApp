// GroupRatingsViewModel.swift
// Avis des familles sur un groupe (T-174, FB-20) : moyenne et répartition, avis récents, et « Noter ce groupe »
// pour un ménage membre (ou ancien membre, avec une part dans une commande terminée du groupe).
// Réutilisable par toute vue d'un groupe (fiche, vue publique T-172).
//
// Usage :
//   @State private var ratings = GroupRatingsViewModel(repositories: context.repositories, groupId: id,
//                                                      householdId: context.householdId, userId: context.userId)
//   .task { await ratings.load(isMember: content.isMember) }

import Foundation
import Observation

@Observable @MainActor
final class GroupRatingsViewModel {
    nonisolated struct Content: Hashable, Sendable {
        var summary: RatingRules.Summary
        /// Avis à afficher (commentés d'abord, puis les plus récents).
        var recent: [GroupRating]
        /// Avis du ménage lecteur, nil s'il n'a pas encore noté.
        var myRating: GroupRating?
        var eligibility: GroupRatingEligibility
    }

    /// Ne bloque jamais la fiche : en cas d'erreur, la section s'affiche avec « Réessayer ».
    private(set) var state: LoadState<Content> = .idle

    let groupId: String
    private let repositories: AppRepositories
    private let householdId: String
    private let userId: String?
    private let now: @Sendable () -> Date
    private var isMember = false

    init(repositories: AppRepositories, groupId: String, householdId: String, userId: String?,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.groupId = groupId
        self.householdId = householdId
        self.userId = userId
        self.now = now
    }

    func load(isMember: Bool) async {
        self.isMember = isMember
        if state.value == nil { state = .loading }
        let repositories = repositories, groupId = groupId, householdId = householdId
        state = await .run {
            let ratings = try await repositories.groups.ratings(ofGroup: groupId)
            let mine = householdId.isEmpty ? nil : ratings.first { $0.householdId == householdId }
            let proofs = (mine == nil && !isMember)
                ? await Self.ordersWithShare(of: householdId, inGroup: groupId, repositories: repositories)
                : []
            return Content(
                summary: RatingRules.summary(ofRatings: ratings.map(\.rating)),
                recent: GroupRatingRules.recent(ratings),
                myRating: mine,
                eligibility: GroupRatingRules.eligibility(householdId: householdId, isMember: isMember,
                                                          existing: mine, ordersWithMyShare: proofs)
            )
        }
    }

    /// Relit les avis (après une erreur, ou un changement d'adhésion connu de `load`).
    func reload() async { await load(isMember: isMember) }

    /// Enregistre (ou modifie) l'avis du ménage. Renvoie le groupe aux agrégats à jour, ou l'erreur à afficher.
    func save(rating: Int, comment: String) async -> Result<NeighborhoodGroup, AppError> {
        guard !householdId.isEmpty else { return .failure(.unauthenticated) }
        guard let current = state.value else { return .failure(.permissionDenied) }
        do {
            let displayName: String
            if let userId { displayName = (try? await repositories.users.user(id: userId).displayName) ?? "" } else { displayName = "" }
            let draft = try GroupRatingRules.makeRating(
                groupId: groupId, householdId: householdId,
                authorName: RatingRules.authorName(fromDisplayName: displayName),
                rating: rating, comment: comment, eligibility: current.eligibility,
                existing: current.myRating, now: now()
            )
            let group = try await repositories.groups.saveRating(draft)
            await load(isMember: isMember)
            return .success(group)
        } catch {
            return .failure(AppError(error))
        }
    }

    /// Commandes terminées du groupe où le ménage avait une part (preuve d'ancien membre), les plus récentes d'abord.
    /// Une part illisible ou une commande introuvable compte comme « pas de part ».
    nonisolated static func ordersWithShare(of householdId: String, inGroup groupId: String,
                                            repositories: AppRepositories) async -> [String] {
        guard !householdId.isEmpty,
              let orders = try? await repositories.groupOrders.groupOrders(ofGroup: groupId) else { return [] }
        var found: [String] = []
        for order in GroupRatingRules.finishedOrders(orders, ofGroup: groupId) {
            if (try? await repositories.groupOrders.share(ofHousehold: householdId, inGroupOrder: order.id)) != nil {
                found.append(order.id)
                break
            }
        }
        return found
    }
}
