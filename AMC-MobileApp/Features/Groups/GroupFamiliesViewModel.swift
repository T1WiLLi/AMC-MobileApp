// GroupFamiliesViewModel.swift
// T-191 : « Familles membres » d'un groupe, sur sa fiche. Le créateur du groupe, et lui seul, peut retirer une
// famille (jamais la sienne). Les noms viennent de `households/{id}` ; un ménage illisible garde sa ligne sans nom.
//
// Usage :
//   @State private var families = GroupFamiliesViewModel(repositories: context.repositories, groupId: id,
//                                                        householdId: context.householdId, userId: context.userId)
//   .task { await families.load() }

import Foundation
import Observation

@Observable @MainActor
final class GroupFamiliesViewModel {
    nonisolated struct Family: Identifiable, Sendable, Hashable {
        var householdId: String
        /// Nom du ménage (« Famille Benali »), nil s'il est illisible (règles, réseau).
        var name: String?
        var role: GroupMember.Role
        /// C'est la famille de la personne qui regarde.
        var isMine: Bool

        var id: String { householdId }
    }

    private(set) var state: LoadState<[Family]> = .idle
    /// Familles en cours de retrait (bouton désactivé, ligne grisée).
    private(set) var removingIds: Set<String> = []
    /// Dernière erreur d'un retrait ; remise à nil par la vue.
    var actionError: AppError?
    /// Nombre de retraits réussis (déclenche le retour haptique).
    private(set) var removalCount = 0

    private let repositories: AppRepositories
    private let groupId: String
    private let householdId: String
    private let userId: String?
    private var group: NeighborhoodGroup?

    init(repositories: AppRepositories, groupId: String, householdId: String, userId: String?) {
        self.repositories = repositories
        self.groupId = groupId
        self.householdId = householdId
        self.userId = userId
    }

    /// La personne a créé ce groupe : seule à voir « Retirer du groupe ».
    var isCreator: Bool {
        guard let group else { return false }
        return GroupRules.isCreator(userId, of: group)
    }

    /// « Retirer du groupe » : le créateur, sur une autre famille que la sienne, hors retrait en cours.
    func canRemove(_ family: Family) -> Bool {
        guard let group, !removingIds.contains(family.householdId) else { return false }
        return GroupRules.canRemoveHousehold(family.householdId, byUserId: userId,
                                             creatorHouseholdId: creatorHouseholdId, from: group)
    }

    private var creatorHouseholdId: String? { householdId.isEmpty ? nil : householdId }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, groupId = groupId, householdId = householdId
        do {
            async let groupLoad = repositories.groups.group(id: groupId)
            async let membersLoad = repositories.groups.members(ofGroup: groupId)
            let (group, members) = try await (groupLoad, membersLoad)
            let names = await Self.names(of: members.map(\.householdId), repositories: repositories)
            self.group = group
            let families = members.map {
                Family(householdId: $0.householdId, name: names[$0.householdId], role: $0.role,
                       isMine: $0.householdId == householdId)
            }
            // Ma famille d'abord, puis par nom ; sans nom en dernier.
            state = .from(families.sorted(by: Self.isOrderedBefore))
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Retire la famille du groupe. Vrai si c'est fait ; sinon `actionError` dit pourquoi.
    @discardableResult
    func remove(_ family: Family) async -> Bool {
        guard canRemove(family), let userId else { return false }
        removingIds.insert(family.householdId)
        defer { removingIds.remove(family.householdId) }
        do {
            try await repositories.groups.removeHousehold(family.householdId, fromGroup: groupId, byUserId: userId,
                                                          creatorHouseholdId: creatorHouseholdId)
            let remaining = (state.value ?? []).filter { $0.householdId != family.householdId }
            state = .from(remaining)
            removalCount += 1
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    private nonisolated static func isOrderedBefore(_ lhs: Family, _ rhs: Family) -> Bool {
        if lhs.isMine != rhs.isMine { return lhs.isMine }
        switch (lhs.name, rhs.name) {
        case let (left?, right?): return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return lhs.householdId < rhs.householdId
        }
    }

    private nonisolated static func names(of ids: [String], repositories: AppRepositories) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for id in ids {
                group.addTask { (id, try? await repositories.users.household(id: id).name) }
            }
            var names: [String: String] = [:]
            for await (id, name) in group { if let name { names[id] = name } }
            return names
        }
    }
}
