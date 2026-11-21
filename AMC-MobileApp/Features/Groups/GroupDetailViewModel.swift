// GroupDetailViewModel.swift
// F2 Fiche d'un groupe de quartier (T-019) : membres, lieu et horaire de cueillette, lots ouverts, rejoindre / quitter.

import Foundation
import Observation

@Observable
@MainActor
final class GroupDetailViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var group: NeighborhoodGroup
        var members: [GroupMember]
        /// Le ménage fait partie du groupe (bouton « Rejoindre le groupe » ou « Quitter »).
        var isMember: Bool
        /// Point de cueillette de la prochaine commande, nil si le groupe n'en a pas encore.
        var pickupPoint: PickupPoint?
        /// Prochain créneau de cueillette (à venir), nil s'il n'y en a pas.
        var nextSlot: PickupSlot?
        /// Commandes ouvertes du groupe (« Lots ouverts »).
        var openOrders: [OfferSummary]
    }

    private(set) var state: LoadState<Content> = .idle
    /// Adhésion en cours de changement.
    private(set) var isUpdatingMembership = false
    /// Dernière erreur d'une action (rejoindre / quitter) ; remise à nil par la vue.
    var actionError: AppError?

    private let repositories: AppRepositories
    private let householdId: String
    private let groupId: String

    init(repositories: AppRepositories, householdId: String, groupId: String) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
    }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, householdId = householdId, groupId = groupId
        state = await .run {
            let group = try await repositories.groups.group(id: groupId)
            let members = try await repositories.groups.members(ofGroup: groupId)
            let orders = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
                .filter(OfferSummaryLoader.isActive)
            var offers: [Offer] = []
            for order in orders {
                offers.append(try await repositories.offers.offer(id: order.offerId))
            }
            let summaries = try await OfferSummaryLoader.summaries(
                for: offers, groupOrders: orders, householdId: householdId, repositories: repositories
            )
            var pickupPoint: PickupPoint?
            if let pointId = orders.lazy.compactMap(\.pickupPointId).first {
                pickupPoint = try await repositories.pickupPoints.pickupPoint(id: pointId)
            }
            let now = Date.now
            let nextSlot = orders.flatMap(\.pickupSlots).filter { $0.end > now }.min { $0.start < $1.start }
            return Content(group: group, members: members,
                           isMember: members.contains { $0.householdId == householdId },
                           pickupPoint: pickupPoint, nextSlot: nextSlot, openOrders: summaries)
        }
    }

    func join() async { await changeMembership(join: true) }
    func leave() async { await changeMembership(join: false) }

    private func changeMembership(join: Bool) async {
        guard !isUpdatingMembership else { return }
        isUpdatingMembership = true
        defer { isUpdatingMembership = false }
        do {
            if join {
                try await repositories.groups.join(groupId: groupId, householdId: householdId)
            } else {
                try await repositories.groups.leave(groupId: groupId, householdId: householdId)
            }
            let group = try await repositories.groups.group(id: groupId)
            let members = try await repositories.groups.members(ofGroup: groupId)
            if var content = state.value {
                content.group = group
                content.members = members
                content.isMember = members.contains { $0.householdId == householdId }
                state = .loaded(content)
            }
        } catch {
            actionError = AppError(error)
        }
    }
}
