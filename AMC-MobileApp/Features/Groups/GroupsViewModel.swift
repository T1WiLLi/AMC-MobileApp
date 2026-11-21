// GroupsViewModel.swift
// Onglet Groupes (T-019) : groupes de quartier publics, avec rejoindre / quitter.

import Foundation
import Observation

@Observable
@MainActor
final class GroupsViewModel {
    /// Une ligne de la liste (pour un `GroupCard`).
    nonisolated struct Item: Identifiable, Sendable, Hashable {
        var group: NeighborhoodGroup
        /// Le ménage fait partie du groupe.
        var isMember: Bool

        var id: String { group.id }
    }

    /// Groupes publics ; les groupes du ménage d'abord. `.empty` s'il n'y en a aucun.
    private(set) var state: LoadState<[Item]> = .idle
    /// Groupes dont l'adhésion est en cours de changement (pour désactiver le bouton / montrer un `ProgressView`).
    private(set) var pendingGroupIds: Set<String> = []
    /// Dernière erreur d'une action (rejoindre / quitter), à montrer en alerte ; remise à nil par la vue.
    var actionError: AppError?

    private let repositories: AppRepositories
    private let householdId: String
    private let neighborhood: String?

    /// `neighborhood` : limite la liste à un quartier (`nil` = tous les quartiers).
    init(repositories: AppRepositories, householdId: String, neighborhood: String? = nil) {
        self.repositories = repositories
        self.householdId = householdId
        self.neighborhood = neighborhood
    }

    /// Groupes dont le ménage est membre (vide tant que rien n'est chargé).
    var myGroups: [NeighborhoodGroup] { state.value?.filter(\.isMember).map(\.group) ?? [] }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, householdId = householdId, neighborhood = neighborhood
        let result = await LoadState<[Item]>.run {
            var items: [Item] = []
            for group in try await repositories.groups.groups(inNeighborhood: neighborhood) {
                let members = try await repositories.groups.members(ofGroup: group.id)
                items.append(Item(group: group, isMember: members.contains { $0.householdId == householdId }))
            }
            return items.filter(\.isMember) + items.filter { !$0.isMember }
        }
        if let items = result.value { state = .from(items) } else { state = result }
    }

    /// Rejoint le groupe puis met la ligne à jour. En cas d'erreur : `actionError`.
    func join(groupId: String) async {
        await changeMembership(groupId: groupId, join: true)
    }

    /// Quitte le groupe puis met la ligne à jour. En cas d'erreur : `actionError`.
    func leave(groupId: String) async {
        await changeMembership(groupId: groupId, join: false)
    }

    private func changeMembership(groupId: String, join: Bool) async {
        guard !pendingGroupIds.contains(groupId) else { return }
        pendingGroupIds.insert(groupId)
        defer { pendingGroupIds.remove(groupId) }
        do {
            if join {
                try await repositories.groups.join(groupId: groupId, householdId: householdId)
            } else {
                try await repositories.groups.leave(groupId: groupId, householdId: householdId)
            }
            let group = try await repositories.groups.group(id: groupId)
            if var items = state.value, let index = items.firstIndex(where: { $0.id == groupId }) {
                items[index] = Item(group: group, isMember: join)
                state = .loaded(items)
            }
        } catch {
            actionError = AppError(error)
        }
    }
}
