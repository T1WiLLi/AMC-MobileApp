// HouseholdProfileViewModel.swift
// RQ-015 (ménage : nom, taille, quartier) et RQ-020 (statut subventionné par code d'organisme, privé).
// T-159 : membres du ménage, demandes pour le rejoindre (le propriétaire accepte ou refuse), retrait d'un membre.
// FB-22 : le propriétaire cède son rôle avant de partir ; membres, propriétaire et demandes se mettent à jour en direct.

import Foundation
import Observation

@Observable @MainActor
final class HouseholdProfileViewModel {
    /// Taille d'un ménage acceptée.
    static let sizeRange = 1...12

    private let repositories: AppRepositories
    private let privateStore: any HouseholdPrivateStore
    private let userId: String
    private let householdId: String
    /// Codes remis par les organismes ; vide = tout code bien formé est accepté (démo).
    private let issuedCodes: Set<String>

    private(set) var state: LoadState<Household> = .idle
    private var user: AppUser?

    // Champs éditables.
    var name = ""
    var size = 1
    var postalCode = "" {
        didSet {
            if let found = MontrealNeighborhood.lookup(postalCode: postalCode).neighborhood {
                neighborhood = found
            }
        }
    }
    /// Quartier choisi : trouvé par le code postal ou choisi dans la liste.
    var neighborhood: MontrealNeighborhood?

    private(set) var isSaving = false
    private(set) var saveError: AppError?
    /// Incrémenté à chaque enregistrement réussi (déclencheur d'haptique et de confirmation).
    private(set) var saveCount = 0

    // Statut subventionné (RQ-020).
    private(set) var privateProfile: HouseholdPrivate?
    var codeInput = "" { didSet { codeError = nil } }
    private(set) var codeError: String?
    private(set) var isRedeeming = false
    private(set) var redeemCount = 0

    // Membres et demandes (T-159).
    nonisolated struct Member: Identifiable, Sendable, Hashable {
        var id: String
        var name: String
        var isOwner: Bool
        var isMe: Bool
    }

    /// Demandes en attente (le propriétaire seulement ; vide pour les autres membres).
    private(set) var joinRequests: [HouseholdJoinRequest] = []
    /// Demande ou membre en cours de traitement (bouton désactivé, indicateur).
    private(set) var busyUserId: String?
    private(set) var membershipError: AppError?
    /// Incrémenté à chaque acceptation (haptique, animation du compteur).
    private(set) var acceptCount = 0
    /// La personne a quitté le ménage : la session doit être rechargée.
    private(set) var didLeave = false
    /// La personne a été retirée du ménage par le propriétaire (vu en direct) : la session doit être rechargée.
    private(set) var wasRemoved = false
    /// Incrémenté quand le rôle de propriétaire change de main (haptique, animation de la couronne).
    private(set) var ownershipChangeCount = 0

    init(repositories: AppRepositories, privateStore: any HouseholdPrivateStore,
         userId: String, householdId: String, issuedCodes: Set<String> = []) {
        self.repositories = repositories
        self.privateStore = privateStore
        self.userId = userId
        self.householdId = householdId
        self.issuedCodes = issuedCodes
    }

    convenience init(context: AppContext, privateStore: any HouseholdPrivateStore) {
        self.init(repositories: context.repositories, privateStore: privateStore,
                  userId: context.userId, householdId: context.householdId)
    }

    // MARK: Lecture

    func load() async {
        if state.value == nil { state = .loading }
        do {
            async let user = repositories.users.user(id: userId)
            async let household = repositories.users.household(id: householdId)
            async let privateProfile = privateStore.privateProfile(householdId: householdId)
            let (loadedUser, loadedHousehold, loadedPrivate) = try await (user, household, privateProfile)
            self.user = loadedUser
            self.privateProfile = loadedPrivate
            name = loadedHousehold.name
            size = loadedHousehold.size
            neighborhood = MontrealNeighborhood.named(loadedUser.neighborhood)
            state = .loaded(loadedHousehold)
            await loadJoinRequests()
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Relit les demandes en attente (propriétaire seulement). Une erreur ici n'empêche pas d'éditer le ménage.
    func loadJoinRequests() async {
        guard isOwner else { joinRequests = []; return }
        joinRequests = (try? await repositories.users.joinRequests(ofHousehold: householdId, byUserId: userId)) ?? joinRequests
    }

    // MARK: Membres et demandes (T-159)

    var isOwner: Bool {
        guard let household = state.value else { return false }
        return HouseholdMembership.isOwner(userId, of: household)
    }

    /// Membres, propriétaire d'abord puis par nom ; « Toi » pour la personne connectée.
    var members: [Member] {
        guard let household = state.value else { return [] }
        let owner = HouseholdMembership.ownerId(of: household)
        return household.userIds.map { id in
            let fallback = id == userId ? (user?.displayName ?? String(localized: "Toi")) : String(localized: "Membre")
            return Member(id: id, name: household.memberNames?[id] ?? fallback, isOwner: id == owner, isMe: id == userId)
        }
        .sorted { lhs, rhs in
            if lhs.isOwner != rhs.isOwner { return lhs.isOwner }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var ownerName: String? { members.first(where: \.isOwner)?.name }

    func accept(_ request: HouseholdJoinRequest) async {
        await membershipChange(request.userId) {
            let household = try await self.repositories.users.acceptJoinRequest(
                householdId: self.householdId, userId: request.userId, byUserId: self.userId
            )
            self.state = .loaded(household)
            self.joinRequests.removeAll { $0.userId == request.userId }
            self.acceptCount += 1
        }
    }

    func decline(_ request: HouseholdJoinRequest) async {
        await membershipChange(request.userId) {
            try await self.repositories.users.deleteJoinRequest(householdId: self.householdId, userId: request.userId)
            self.joinRequests.removeAll { $0.userId == request.userId }
        }
    }

    /// Le propriétaire retire un autre membre.
    func remove(_ member: Member) async {
        guard isOwner, !member.isMe else { return }
        await membershipChange(member.id) {
            let household = try await self.repositories.users.removeMember(
                member.id, fromHousehold: self.householdId, byUserId: self.userId
            )
            self.state = .loaded(household)
        }
    }

    /// Le propriétaire cède son rôle à un autre membre (FB-22). Il pourra ensuite quitter le ménage.
    func transferOwnership(to member: Member) async {
        guard isOwner, !member.isMe else { return }
        await membershipChange(member.id) {
            let household = try await self.repositories.users.transferOwnership(
                ofHousehold: self.householdId, to: member.id, byUserId: self.userId
            )
            self.state = .loaded(household)
            self.joinRequests = []
            self.ownershipChangeCount += 1
        }
    }

    /// Le propriétaire ne peut pas partir tant qu'il reste d'autres membres : il doit d'abord céder son rôle.
    var mustTransferBeforeLeaving: Bool { isOwner && members.count > 1 }

    /// Un membre (pas le propriétaire) quitte le ménage ; il retrouve son propre ménage au rechargement de la session.
    func leave() async {
        guard !isOwner else {
            if mustTransferBeforeLeaving {
                membershipError = .invalidInput(String(localized: "Nomme d'abord un autre membre propriétaire, puis quitte le ménage."))
            }
            return
        }
        await membershipChange(userId) {
            _ = try await self.repositories.users.removeMember(self.userId, fromHousehold: self.householdId, byUserId: self.userId)
            self.didLeave = true
        }
    }

    // MARK: Temps réel (FB-22)

    /// Suit le ménage et, pour le propriétaire, ses demandes en attente, jusqu'à l'annulation de la tâche
    /// (`.task` de l'écran). Les champs en cours d'édition (nom, taille) ne sont jamais écrasés.
    func observe() async {
        let households = await repositories.users.observeHousehold(id: householdId)
        var requestsTask: Task<Void, Never>?
        defer { requestsTask?.cancel() }
        do {
            for try await household in households {
                guard household.userIds.contains(userId) else {
                    // Retiré par le propriétaire pendant qu'on regardait l'écran.
                    wasRemoved = true
                    return
                }
                let previousOwner = state.value.flatMap(HouseholdMembership.ownerId(of:))
                state = .loaded(household)
                let owner = HouseholdMembership.ownerId(of: household)
                if let previousOwner, previousOwner != owner { ownershipChangeCount += 1 }
                if isOwner {
                    if requestsTask == nil { requestsTask = Task { await self.observeJoinRequests() } }
                } else {
                    requestsTask?.cancel()
                    requestsTask = nil
                    joinRequests = []
                }
            }
        } catch AppError.permissionDenied {
            // Plus membre : les règles refusent la lecture du ménage.
            wasRemoved = true
        } catch {
            // Réseau, etc. : on garde le dernier état connu ; `.refreshable` relit.
        }
    }

    private func observeJoinRequests() async {
        let stream = await repositories.users.observeJoinRequests(ofHousehold: householdId, byUserId: userId)
        do {
            for try await requests in stream { joinRequests = requests }
        } catch {
            // Propriété cédée (accès refusé) ou réseau : la liste ne bouge plus, l'écran reste utilisable.
        }
    }

    private func membershipChange(_ targetId: String, _ change: () async throws -> Void) async {
        guard busyUserId == nil else { return }
        busyUserId = targetId
        membershipError = nil
        defer { busyUserId = nil }
        do {
            try await change()
        } catch {
            membershipError = AppError(error)
        }
    }

    // MARK: Validation

    var postalLookup: MontrealNeighborhood.Lookup { MontrealNeighborhood.lookup(postalCode: postalCode) }

    /// Message sous le champ code postal, ou `nil`.
    var postalMessage: String? {
        switch postalLookup {
        case .empty, .incomplete: nil
        case .invalid: String(localized: "Un code postal a la forme H2A 1B3.")
        case .notServed: String(localized: "LeGrenier n'est pas encore offert dans ce secteur. Choisis le quartier le plus proche.")
        case .found(let found): String(localized: "Quartier trouvé : \(found.name).")
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var nameError: String? {
        if trimmedName.isEmpty { return String(localized: "Donne un nom à ton ménage (ex. « Famille Benali »).") }
        if trimmedName.count > 40 { return String(localized: "40 caractères au plus.") }
        return nil
    }

    var hasChanges: Bool {
        guard let household = state.value else { return false }
        return trimmedName != household.name
            || size != household.size
            || neighborhood?.name != user?.neighborhood
    }

    var canSave: Bool {
        state.value != nil && nameError == nil && neighborhood != nil
            && Self.sizeRange.contains(size) && hasChanges && !isSaving
    }

    // MARK: Enregistrement

    func save() async {
        guard canSave, var household = state.value, var user, let neighborhood else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        household.name = trimmedName
        household.size = size
        household.geohash = neighborhood.geohash
        user.neighborhood = neighborhood.name
        do {
            try await repositories.users.saveHousehold(household)
            try await repositories.users.saveUser(user)
            self.user = user
            name = household.name
            state = .loaded(household)
            saveCount += 1
        } catch {
            saveError = AppError(error)
        }
    }

    // MARK: Statut subventionné

    var isSubsidized: Bool { privateProfile?.isSubsidized == true }

    var canRedeem: Bool {
        !codeInput.trimmingCharacters(in: .whitespaces).isEmpty && !isRedeeming && state.value != nil
    }

    func redeemCode() async {
        guard canRedeem else { return }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let profile = try ReferralCode.subsidizedProfile(redeeming: codeInput, issuedCodes: issuedCodes)
            try await privateStore.savePrivateProfile(profile, householdId: householdId)
            privateProfile = profile
            codeInput = ""
            redeemCount += 1
        } catch let AppError.invalidInput(message) {
            codeError = message
        } catch {
            codeError = AppError(error).message
        }
    }

    /// Retire le statut (le ménage n'en a plus besoin).
    func withdrawSubsidy() async {
        isRedeeming = true
        defer { isRedeeming = false }
        let profile = HouseholdPrivate(isSubsidized: false, referralCode: nil)
        do {
            try await privateStore.savePrivateProfile(profile, householdId: householdId)
            privateProfile = profile
        } catch {
            codeError = AppError(error).message
        }
    }
}
