// GroupDetailViewModel.swift
// F2 Fiche d'un groupe de quartier (T-019) : membres, lieu et horaire de cueillette, lots ouverts, rejoindre / quitter.
//
// Temps réel (T-096, S-05) : dans l'écran,
//     .task { await viewModel.load(); await viewModel.observe() }
// `observe()` suit le groupe (un ménage rejoint ou quitte → membres rechargés) et chaque lot ouvert
// (parts, palier, prix). S'arrête avec la tâche ; une écoute coupée garde les données et met `isLive` à false.

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
    /// L'écoute en direct tourne (`observe()`). Repasse à false quand elle s'arrête ou échoue.
    private(set) var isLive = false

    private let repositories: AppRepositories
    private let householdId: String
    private let groupId: String
    /// T-122 : utilisateur connecté, pour savoir s'il coordonne le groupe (photo et bannière).
    private let userId: String?

    init(repositories: AppRepositories, householdId: String, groupId: String, userId: String? = nil) {
        self.repositories = repositories
        self.householdId = householdId
        self.groupId = groupId
        self.userId = userId
    }

    /// T-122 : l'utilisateur coordonne ce groupe (il peut changer sa photo et sa bannière).
    var isCoordinator: Bool {
        guard let userId, let group = state.value?.group else { return false }
        return group.coordinatorIds.contains(userId)
    }

    /// T-122 : remplace le groupe affiché (après un changement de photo ou de bannière).
    func replaceGroup(_ group: NeighborhoodGroup) {
        guard var content = state.value, group.id == content.group.id else { return }
        content.group = group
        state = .loaded(content)
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

    /// Suit le groupe et ses lots ouverts en temps réel. À lancer dans `.task` après `load()` ; s'arrête avec la tâche.
    func observe() async {
        guard let content = state.value else { return }
        // Abonnements ouverts avant de rendre la main : aucun changement n'est perdu une fois `isLive` vrai.
        let groupUpdates = await repositories.groups.observeGroup(id: groupId)
        var orderUpdates: [AsyncThrowingStream<GroupOrder, any Error>] = []
        for orderId in content.openOrders.compactMap(\.groupOrder?.id) {
            orderUpdates.append(await repositories.groupOrders.observeGroupOrder(id: orderId))
        }
        isLive = true
        defer { isLive = false }
        await withTaskGroup(of: Void.self) { tasks in
            tasks.addTask { [weak self] in
                var isFirst = true
                do {
                    for try await group in groupUpdates {
                        // La première émission est l'état déjà chargé.
                        if !isFirst { await self?.groupChanged(group) }
                        isFirst = false
                    }
                } catch {}
            }
            for updates in orderUpdates {
                tasks.addTask { [weak self] in
                    do {
                        for try await order in updates {
                            await self?.orderChanged(order)
                        }
                    } catch {}
                }
            }
        }
    }

    private func groupChanged(_ group: NeighborhoodGroup) async {
        guard state.value != nil else { return }
        let members = try? await repositories.groups.members(ofGroup: groupId)
        guard var content = state.value else { return }
        content.group = group
        if let members {
            content.members = members
            content.isMember = members.contains { $0.householdId == householdId }
        }
        state = .loaded(content)
    }

    private func orderChanged(_ order: GroupOrder) {
        guard var content = state.value,
              let index = content.openOrders.firstIndex(where: { $0.groupOrder?.id == order.id }) else { return }
        content.openOrders[index].groupOrder = order
        state = .loaded(content)
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
