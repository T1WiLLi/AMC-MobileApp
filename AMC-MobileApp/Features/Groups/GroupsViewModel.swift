// GroupsViewModel.swift
// Onglet Groupes (T-019) : groupes de quartier publics, avec rejoindre / quitter.
// B-056 : « Tes groupes » contient aussi tes groupes privés ; les autres sont les groupes publics,
// du plus proche au plus loin du ménage. Un groupe privé n'est jamais listé : on y entre avec un code.
// FB-22 : un membre du ménage qui rejoint ou quitte un groupe apparaît chez les autres en direct.

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
        /// Distance du ménage au centre du groupe, en mètres ; nil si la position est inconnue.
        var distanceMeters: Double? = nil

        var id: String { group.id }
        /// « à 650 m », « à 1,4 km ».
        var distanceText: String? { distanceMeters.map(NearbyGroupsViewModel.distanceText(meters:)) }
    }

    /// Groupes publics ; les groupes du ménage d'abord. `.empty` s'il n'y en a aucun.
    private(set) var state: LoadState<[Item]> = .idle {
        didSet { shownIdsContinuation?.yield(shownIds) }
    }
    /// Groupes dont l'adhésion est en cours de changement (pour désactiver le bouton / montrer un `ProgressView`).
    private(set) var pendingGroupIds: Set<String> = []
    /// Dernière erreur d'une action (rejoindre / quitter), à montrer en alerte ; remise à nil par la vue.
    var actionError: AppError?
    /// FB-22 : incrémenté quand un autre membre du ménage rejoint ou quitte un groupe (la session doit suivre).
    private(set) var householdMembershipChangeCount = 0

    /// Prévenu quand l'ensemble des groupes affichés change (`observeGroups()` relance ses écoutes).
    @ObservationIgnored private var shownIdsContinuation: AsyncStream<Set<String>>.Continuation?

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
            async let publicGroups = repositories.groups.groups(inNeighborhood: neighborhood)
            async let householdGroups = repositories.groups.groups(ofHousehold: householdId)
            // Position approximative du ménage ; inconnue → liste par nom.
            async let household = try? repositories.users.household(id: householdId)
            let (all, mine) = try await (publicGroups, householdGroups)
            let origin = await household.flatMap { Geohash.center(of: $0.geohash) }
            return Self.items(publicGroups: all, householdGroups: mine, neighborhood: neighborhood, origin: origin)
        }
        if let items = result.value { state = .from(items) } else { state = result }
    }

    /// Les groupes du ménage (publics et privés) d'abord, par nom ; puis les groupes publics dont il n'est pas
    /// membre, du plus proche au plus loin (par nom si la distance est inconnue).
    nonisolated static func items(
        publicGroups: [NeighborhoodGroup], householdGroups: [NeighborhoodGroup],
        neighborhood: String?, origin: Geohash.Coordinate?
    ) -> [Item] {
        func distance(_ group: NeighborhoodGroup) -> Double? {
            origin.flatMap { Geohash.distanceMeters(from: $0, to: group.centerGeohash) }
        }
        let memberIds = Set(householdGroups.map(\.id))
        let mine = householdGroups
            .filter { neighborhood == nil || $0.neighborhood == neighborhood }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Item(group: $0, isMember: true, distanceMeters: distance($0)) }
        let others = publicGroups
            .filter { $0.isPublic && !memberIds.contains($0.id) }
            .map { Item(group: $0, isMember: false, distanceMeters: distance($0)) }
            .sorted { lhs, rhs in
                switch (lhs.distanceMeters, rhs.distanceMeters) {
                case let (left?, right?) where left != right: left < right
                case (.some, nil): true
                case (nil, .some): false
                default: lhs.group.name.localizedStandardCompare(rhs.group.name) == .orderedAscending
                }
            }
        return mine + others
    }

    /// FB-22 : suit les groupes du ménage jusqu'à l'annulation de la tâche (`.task` de l'écran). Quand un autre
    /// membre du ménage rejoint ou quitte un groupe sur son téléphone, la liste est relue.
    func observeHouseholdGroups(onChange: () async -> Void = {}) async {
        let stream = await repositories.groups.observeGroupIds(ofHousehold: householdId)
        do {
            for try await ids in stream {
                guard let items = state.value else { continue }
                let shown = Set(items.filter(\.isMember).map(\.id))
                guard ids != shown, pendingGroupIds.isEmpty else { continue }
                await load()
                householdMembershipChangeCount += 1
                await onChange()
            }
        } catch {
            // Réseau ou accès : la liste reste telle quelle ; `.refreshable` relit.
        }
    }

    /// Ids des groupes affichés.
    private var shownIds: Set<String> { Set(state.value?.map(\.id) ?? []) }

    /// Suit en direct chaque groupe affiché (nom, photo, bannière, nombre de ménages, visibilité…) jusqu'à
    /// l'annulation de la tâche (`.task` de l'écran) : la ligne change sans recharger ni tirer pour rafraîchir.
    /// Les écoutes suivent la liste : un groupe ajouté est écouté, un groupe retiré ne l'est plus.
    func observeGroups() async {
        let (changes, continuation) = AsyncStream.makeStream(of: Set<String>.self, bufferingPolicy: .bufferingNewest(1))
        shownIdsContinuation?.finish()
        shownIdsContinuation = continuation
        continuation.yield(shownIds)
        var following: Set<String> = []
        var listeners: Task<Void, Never>?
        for await ids in changes where ids != following {
            following = ids
            listeners?.cancel()
            listeners = Task { [weak self] in await self?.follow(ids) }
        }
        listeners?.cancel()
    }

    private func follow(_ ids: Set<String>) async {
        let repositories = repositories
        await withTaskGroup(of: Void.self) { tasks in
            for id in ids {
                tasks.addTask { [weak self] in
                    let updates = await repositories.groups.observeGroup(id: id)
                    do {
                        for try await group in updates { await self?.groupChanged(group) }
                    } catch AppError.notFound {
                        await self?.groupRemoved(id: id)
                    } catch {
                        // Réseau ou accès : la ligne garde sa dernière valeur.
                    }
                }
            }
        }
    }

    private func groupChanged(_ group: NeighborhoodGroup) {
        guard var items = state.value, let index = items.firstIndex(where: { $0.id == group.id }) else { return }
        // Un groupe devenu privé disparaît pour les ménages qui n'en sont pas membres (B-056).
        if !group.isPublic && !items[index].isMember { return groupRemoved(id: group.id) }
        guard items[index].group != group else { return }
        items[index].group = group
        state = .loaded(items)
    }

    private func groupRemoved(id: String) {
        guard var items = state.value, items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        state = .from(items)
    }

    /// B-056 : après une entrée avec un code (feuille « Rejoindre avec un code »), le groupe passe dans « Tes groupes ».
    func didJoin(_ group: NeighborhoodGroup) async {
        await load()
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
                items[index].group = group
                items[index].isMember = join
                state = .loaded(items)
            }
        } catch {
            actionError = AppError(error)
        }
    }
}
