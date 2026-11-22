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
        /// Initiales des premiers ménages membres (« B » pour « Famille Benali »), tirées de leur nom réel.
        /// Un ménage illisible (règles, réseau) est simplement omis : jamais d'initiales inventées.
        var memberInitials: [String] = []
        /// T-172 : nom du ménage qui coordonne le groupe (« Famille Benali »), nil s'il est illisible
        /// (les règles ne laissent lire un ménage qu'à ses membres) ou si le groupe n'a pas de coordonnateur.
        var coordinatorName: String? = nil

        /// T-172 : qui regarde la fiche.
        var audience: Audience { Audience(isMember: isMember, isPublic: group.isPublic) }
    }

    /// T-172 (FB-13) : un membre voit la fiche complète ; un visiteur voit la fiche publique du groupe
    /// (« Rejoindre » pour un groupe public, « Demander une invitation » pour un groupe privé).
    nonisolated enum Audience: Sendable, Hashable {
        case member
        case publicVisitor
        case privateVisitor

        init(isMember: Bool, isPublic: Bool) {
            self = isMember ? .member : (isPublic ? .publicVisitor : .privateVisitor)
        }

        var isMember: Bool { self == .member }
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

    /// B-056 : l'utilisateur a créé ce groupe (visibilité et invitations à usage unique).
    var isCreator: Bool {
        guard let group = state.value?.group else { return false }
        return GroupRules.isCreator(userId, of: group)
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
            // Appels indépendants en parallèle.
            async let groupLoad = repositories.groups.group(id: groupId)
            async let membersLoad = repositories.groups.members(ofGroup: groupId)
            async let ordersLoad = repositories.groupOrders.groupOrders(ofGroup: groupId)
            let (group, members, allOrders) = try await (groupLoad, membersLoad, ordersLoad)
            let orders = allOrders.filter(OfferSummaryLoader.isActive)
            // T-172 (FB-13) : un visiteur ne lit pas les parts (réservées aux membres par les règles) :
            // c'est ce refus qui affichait « Action non permise » à la place de la fiche.
            let isMember = members.contains { $0.householdId == householdId }

            async let initials = Self.memberInitials(of: members, repositories: repositories)
            async let coordinator = Self.coordinatorName(of: members, repositories: repositories)
            async let pickupPointLoad: PickupPoint? = {
                guard let pointId = orders.lazy.compactMap(\.pickupPointId).first else { return nil }
                return try await repositories.pickupPoints.pickupPoint(id: pointId)
            }()
            let offers = try await FamilyHomeViewModel.offers(for: orders, repositories: repositories)
            let summaries = try await OfferSummaryLoader.summaries(
                for: offers, groupOrders: orders, householdId: householdId, repositories: repositories,
                includeMyShares: isMember
            )
            let pickupPoint = try await pickupPointLoad
            let now = Date.now
            let nextSlot = orders.flatMap(\.pickupSlots).filter { $0.end > now }.min { $0.start < $1.start }
            return Content(group: group, members: members, isMember: isMember,
                           pickupPoint: pickupPoint, nextSlot: nextSlot, openOrders: summaries,
                           memberInitials: await initials, coordinatorName: await coordinator)
        }
    }

    /// T-172 : nom du premier ménage coordonnateur, lu dans `households/{id}` ; nil s'il est illisible.
    nonisolated static func coordinatorName(of members: [GroupMember], repositories: AppRepositories) async -> String? {
        guard let id = members.first(where: { $0.role == .coordinator })?.householdId else { return nil }
        return try? await repositories.users.household(id: id).name
    }

    /// Initiales des trois premiers ménages membres, lues en parallèle depuis `households/{id}`.
    nonisolated static func memberInitials(of members: [GroupMember], repositories: AppRepositories) async -> [String] {
        let ids = Array(members.prefix(3).map(\.householdId))
        let names = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try? await repositories.users.household(id: id).name) }
            }
            var byIndex: [Int: String] = [:]
            for await (index, name) in group { if let name { byIndex[index] = name } }
            return ids.indices.compactMap { byIndex[$0] }
        }
        return names.compactMap(initials(ofHouseholdName:))
    }

    /// « Famille Benali » → « B », « Ménage Tremblay-Roy » → « TR », « Amina Benali » → « AB ».
    nonisolated static func initials(ofHouseholdName name: String) -> String? {
        let ignored: Set<String> = ["famille", "menage", "foyer", "maison", "les", "la", "le", "de", "des", "du"]
        let words = name
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { !ignored.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()) }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
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
        var initials: [String]?
        if let members { initials = await Self.memberInitials(of: members, repositories: repositories) }
        guard var content = state.value else { return }
        content.group = group
        if let members {
            content.members = members
            content.isMember = members.contains { $0.householdId == householdId }
        }
        if let initials { content.memberInitials = initials }
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

    // MARK: - T-193 Le créateur quitte son groupe

    /// À qui le groupe passe quand le créateur part.
    nonisolated enum Succession: Sendable, Equatable {
        /// Une famille hérite : `handover` porte son compte (futur `createdBy`) ; `familyName` est son nom, nil s'il est illisible.
        case heir(familyName: String?, handover: GroupRules.Handover)
        /// Des familles restent, mais aucun compte n'a pu être trouvé (ménage illisible) : sortie ordinaire.
        case unresolved
        /// Plus personne : le groupe se retrouve sans membre.
        case nobody
    }

    /// Succession calculée pour la confirmation « Quitter le groupe » ; nil tant que `prepareLeave()` n'a pas tourné
    /// et pour quelqu'un qui n'est pas le créateur.
    private(set) var succession: Succession?

    /// Calcule la succession avant d'afficher la confirmation (créateur seulement).
    func prepareLeave() async {
        guard isCreator else { succession = nil; return }
        succession = await resolveSuccession()
    }

    /// Phrase de la confirmation qui dit qui devient propriétaire (créateur seulement).
    var successionMessage: String? {
        switch succession {
        case nil: nil
        case .heir(let familyName?, _):
            String(localized: "Tu es le créateur du groupe : il sera confié à \(familyName), la famille la plus ancienne. Tes parts déjà réservées restent valides.")
        case .heir(nil, _):
            String(localized: "Tu es le créateur du groupe : il sera confié à la famille la plus ancienne du groupe. Tes parts déjà réservées restent valides.")
        case .unresolved:
            String(localized: "Tu es le créateur du groupe, mais nous n'avons pas pu trouver à qui le confier : il restera sans propriétaire. Tes parts déjà réservées restent valides.")
        case .nobody:
            String(localized: "Tu es la dernière famille du groupe : il n'aura plus aucun membre. Tes parts déjà réservées restent valides.")
        }
    }

    /// Héritier (`GroupRules.heir`) et un compte de son ménage : le propriétaire du ménage (`households/{id}`).
    private func resolveSuccession() async -> Succession {
        guard let members = try? await repositories.groups.members(ofGroup: groupId) else { return .unresolved }
        guard let heir = GroupRules.heir(among: members, leaving: householdId) else { return .nobody }
        guard let household = try? await repositories.users.household(id: heir.householdId),
              let ownerId = HouseholdMembership.ownerId(of: household) else { return .unresolved }
        return .heir(familyName: household.name, handover: GroupRules.Handover(householdId: heir.householdId, userId: ownerId))
    }

    private func changeMembership(join: Bool) async {
        guard !isUpdatingMembership else { return }
        isUpdatingMembership = true
        defer { isUpdatingMembership = false }
        do {
            if join {
                try await repositories.groups.join(groupId: groupId, householdId: householdId)
            } else if isCreator, let userId {
                // T-193 : le groupe est confié à l'héritier, recalculé à l'instant (il a pu partir depuis la confirmation).
                var handover: GroupRules.Handover?
                if case .heir(_, let resolved) = await resolveSuccession() { handover = resolved }
                try await repositories.groups.leave(groupId: groupId, householdId: householdId,
                                                    byUserId: userId, handingOverTo: handover)
            } else {
                try await repositories.groups.leave(groupId: groupId, householdId: householdId)
            }
            let group = try await repositories.groups.group(id: groupId)
            let members = try await repositories.groups.members(ofGroup: groupId)
            let initials = await Self.memberInitials(of: members, repositories: repositories)
            if var content = state.value {
                content.group = group
                content.members = members
                content.memberInitials = initials
                content.isMember = members.contains { $0.householdId == householdId }
                state = .loaded(content)
            }
        } catch {
            actionError = AppError(error)
        }
    }
}
