// GroupRules.swift
// Règles des groupes de voisinage (E03 : RQ-025, RQ-026, RQ-028, RQ-030).
// Swift pur, sans Firebase ni UI : les dépôts (Firebase ou fake) et les ViewModels l'appellent.

import Foundation

nonisolated enum GroupRules {
    // MARK: - RQ-025 Création d'un groupe

    static let nameLengthRange = 3...40
    static let radiusRangeMeters = 1_000...2_000
    /// Longueur maximale du slug de quartier (même limite que `firestore.rules`, V5).
    static let neighborhoodMaxLength = 80

    /// Ce que la personne saisit pour créer un groupe.
    struct Draft: Sendable, Equatable {
        var name: String
        /// Slug du quartier (ex. « parc-extension »).
        var neighborhood: String
        /// Geohash du centre du groupe (approximatif, jamais une adresse exacte).
        var centerGeohash: String
        var radiusMeters: Int
        var isPublic: Bool

        init(name: String, neighborhood: String, centerGeohash: String, radiusMeters: Int = 1_500, isPublic: Bool = true) {
            self.name = name
            self.neighborhood = neighborhood
            self.centerGeohash = centerGeohash
            self.radiusMeters = radiusMeters
            self.isPublic = isPublic
        }
    }

    /// Résultat d'une création : le groupe et le premier membre (le ménage créateur, coordonnateur).
    struct Creation: Sendable, Equatable {
        var group: NeighborhoodGroup
        var creatorMember: GroupMember
    }

    /// Valide le brouillon et renvoie le nom nettoyé (espaces en trop retirés).
    /// Lève `AppError.invalidInput` avec un message en français qui dit quoi corriger.
    @discardableResult
    static func validate(_ draft: Draft) throws -> Draft {
        var clean = draft
        clean.name = draft.name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        clean.neighborhood = draft.neighborhood.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        clean.centerGeohash = draft.centerGeohash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if clean.name.count < nameLengthRange.lowerBound {
            throw AppError.invalidInput(String(localized: "Donne un nom d'au moins \(nameLengthRange.lowerBound) caractères à ton groupe."))
        }
        if clean.name.count > nameLengthRange.upperBound {
            throw AppError.invalidInput(String(localized: "Le nom de ton groupe doit faire \(nameLengthRange.upperBound) caractères au maximum."))
        }
        if clean.neighborhood.isEmpty {
            throw AppError.invalidInput(String(localized: "Choisis le quartier de ton groupe."))
        }
        if clean.neighborhood.count > neighborhoodMaxLength {
            throw AppError.invalidInput(String(localized: "Le quartier de ton groupe doit faire \(neighborhoodMaxLength) caractères au maximum."))
        }
        if clean.centerGeohash.isEmpty {
            throw AppError.invalidInput(String(localized: "Indique le centre de ton groupe sur la carte."))
        }
        if !radiusRangeMeters.contains(clean.radiusMeters) {
            throw AppError.invalidInput(String(localized: "Choisis un rayon entre 1 et 2 km."))
        }
        return clean
    }

    /// Construit un nouveau groupe à partir d'un brouillon valide. Le créateur en devient le premier coordonnateur.
    /// - Parameters:
    ///   - creatorUserId: utilisateur ajouté à `coordinatorIds`.
    ///   - creatorHouseholdId: ménage ajouté comme premier membre (rôle `.coordinator`).
    ///   - makeId: générateur d'identifiant de document (injecté pour les tests).
    ///   - makeInviteCode: générateur de code d'invitation (par défaut `generateInviteCode()`).
    static func makeGroup(
        from draft: Draft,
        creatorUserId: String,
        creatorHouseholdId: String,
        now: Date = .now,
        makeId: () -> String = { UUID().uuidString },
        makeInviteCode: () -> String = { GroupRules.generateInviteCode() }
    ) throws -> Creation {
        let clean = try validate(draft)
        let group = NeighborhoodGroup(
            id: makeId(),
            name: clean.name,
            neighborhood: clean.neighborhood,
            centerGeohash: clean.centerGeohash,
            radiusMeters: clean.radiusMeters,
            coordinatorIds: [creatorUserId],
            householdCount: 1,
            isPublic: clean.isPublic,
            inviteCode: makeInviteCode(),
            createdBy: creatorUserId
        )
        let member = GroupMember(householdId: creatorHouseholdId, role: .coordinator, joinedAt: now, userId: creatorUserId)
        return Creation(group: group, creatorMember: member)
    }

    // MARK: - RQ-026 Invitation

    /// Alphabet des codes générés : sans 0/O ni 1/I (illisibles à l'oral ou sur un papier).
    static let inviteAlphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let inviteCodeLength = 6

    /// Schéma de l'app : `grenier://join/<code>`.
    static let appScheme = "grenier"
    /// Lien universel partageable (Messages, courriel) : `https://grenier.app/join/<code>`.
    static let universalLinkHost = "grenier.app"
    static let joinPath = "join"
    /// Hôte des premiers QR d'invitation, encore accepté à la lecture.
    static let legacyJoinHost = "rejoindre"

    /// Génère un code de `inviteCodeLength` caractères pris dans `inviteAlphabet`.
    static func generateInviteCode<G: RandomNumberGenerator>(using rng: inout G) -> String {
        String((0..<inviteCodeLength).map { _ in inviteAlphabet.randomElement(using: &rng)! })
    }

    static func generateInviteCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return generateInviteCode(using: &rng)
    }

    /// Génère un code absent de `existing` (comparaison sur la forme normalisée).
    static func generateInviteCode<G: RandomNumberGenerator>(avoiding existing: Set<String>, using rng: inout G) -> String {
        let taken = Set(existing.map(normalizedInviteCode))
        var code = generateInviteCode(using: &rng)
        while taken.contains(code) { code = generateInviteCode(using: &rng) }
        return code
    }

    /// Met la saisie en forme : majuscules, sans espaces, tirets ni points (« pa-rex 1 » → « PAREX1 »).
    static func normalizedInviteCode(_ input: String) -> String {
        String(input.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Un code est valide s'il fait `inviteCodeLength` caractères A–Z ou 0–9 une fois normalisé.
    /// On accepte tous les chiffres et lettres (et pas seulement `inviteAlphabet`) pour rester compatible
    /// avec les codes déjà distribués, comme ceux des fixtures (« PAREX1 »).
    static func isValidInviteCode(_ input: String) -> Bool {
        let code = normalizedInviteCode(input)
        return code.count == inviteCodeLength && code.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    /// Normalise et valide un code saisi ; lève `AppError.invalidInput` sinon.
    static func validatedInviteCode(_ input: String) throws -> String {
        guard isValidInviteCode(input) else {
            throw AppError.invalidInput(String(localized: "Un code d'invitation compte \(inviteCodeLength) lettres ou chiffres. Vérifie celui qu'on t'a envoyé."))
        }
        return normalizedInviteCode(input)
    }

    /// Lien vers l'app : `grenier://join/<code>`.
    static func appInviteLink(for code: String) -> URL? {
        guard isValidInviteCode(code) else { return nil }
        return URL(string: "\(appScheme)://\(joinPath)/\(normalizedInviteCode(code))")
    }

    /// Lien universel à partager : `https://grenier.app/join/<code>`.
    static func shareableInviteLink(for code: String) -> URL? {
        guard isValidInviteCode(code) else { return nil }
        return URL(string: "https://\(universalLinkHost)/\(joinPath)/\(normalizedInviteCode(code))")
    }

    /// Extrait le code d'un lien d'invitation. Accepte seulement `grenier://join/<code>`,
    /// `https://grenier.app/join/<code>` et l'ancien `grenier://rejoindre?code=<code>` ;
    /// tout autre schéma, hôte ou chemin renvoie nil.
    static func inviteCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let host = components.host?.lowercased()
        let candidate: String?
        switch scheme {
        case appScheme where host == legacyJoinHost:
            // Ancien QR de la carte d'invitation (avant B-058) : `grenier://rejoindre?code=<code>`.
            candidate = segments.isEmpty ? components.queryItems?.first(where: { $0.name == "code" })?.value : nil
        case appScheme:
            candidate = (host == joinPath && segments.count == 1) ? segments[0] : nil
        case "https":
            candidate = (host == universalLinkHost && segments.count == 2 && segments[0] == joinPath) ? segments[1] : nil
        default:
            candidate = nil
        }
        guard let candidate, isValidInviteCode(candidate),
              candidate == candidate.filter({ $0.isLetter || $0.isNumber }) else { return nil }
        return normalizedInviteCode(candidate)
    }

    /// Ce que la personne colle dans le champ « Rejoindre » : un code seul, un lien d'invitation, ou tout le
    /// message de partage de l'app (`InviteCard.shareMessage`, `GroupInvitationsViewModel.shareMessage`).
    static func inviteCode(fromUserInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidInviteCode(trimmed), !trimmed.contains("://") { return normalizedInviteCode(trimmed) }
        if trimmed.contains("://"), let url = URL(string: trimmed), let code = inviteCode(from: url) {
            return code
        }
        return inviteCode(inMessage: trimmed)
    }

    /// Cherche l'invitation dans un texte plus long : d'abord un lien reconnu (« … : https://grenier.app/join/ABC123
    /// (code ABC123) »), sinon le code qui suit le dernier mot « code » (« Code d'invitation : PARCEX »,
    /// « Invite code: PARCEX »). Sans l'un ni l'autre, nil : on ne devine jamais un code au hasard du texte.
    static func inviteCode(inMessage text: String) -> String? {
        let edges = CharacterSet.punctuationCharacters.union(.symbols)
        for token in text.split(whereSeparator: \.isWhitespace) where token.contains("://") {
            let candidate = String(token).trimmingCharacters(in: edges)
            if let url = URL(string: candidate), let code = inviteCode(from: url) { return code }
        }
        let words = text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        guard let marker = words.lastIndex(where: { $0.lowercased() == "code" }) else { return nil }
        return words[(marker + 1)...].first(where: isValidInviteCode).map(normalizedInviteCode)
    }

    // MARK: - B-056 Groupes publics ou privés, invitations à usage unique

    /// Seul le créateur du groupe change sa visibilité et gère ses invitations.
    static func isCreator(_ userId: String?, of group: NeighborhoodGroup) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return group.creatorId == userId
    }

    /// T-191 : le créateur seul retire une famille du groupe, jamais la sienne (ni un autre coordonnateur, ni un membre).
    static func canRemoveHousehold(_ householdId: String, byUserId userId: String?,
                                   creatorHouseholdId: String?, from group: NeighborhoodGroup) -> Bool {
        isCreator(userId, of: group) && householdId != creatorHouseholdId
    }

    static func requireCanRemoveHousehold(_ householdId: String, byUserId userId: String?,
                                          creatorHouseholdId: String?, from group: NeighborhoodGroup) throws {
        guard canRemoveHousehold(householdId, byUserId: userId, creatorHouseholdId: creatorHouseholdId, from: group)
        else { throw AppError.permissionDenied }
    }

    // MARK: - T-193 Le créateur quitte son groupe

    /// La famille à qui le groupe est confié : son ménage et un compte de ce ménage (le futur `createdBy`).
    struct Handover: Sendable, Equatable, Hashable {
        var householdId: String
        var userId: String
    }

    /// T-193 : ménage héritier quand le créateur (ménage `leavingHouseholdId`) part. Le coordonnateur le plus ancien
    /// (plus petit `joinedAt` parmi `role == .coordinator`), sinon le membre le plus ancien, sinon nil (plus personne).
    /// À date égale, l'identifiant de ménage tranche : le résultat ne dépend pas de l'ordre de la liste.
    static func heir(among members: [GroupMember], leaving leavingHouseholdId: String) -> GroupMember? {
        let remaining = members.filter { $0.householdId != leavingHouseholdId }
        func oldest(_ candidates: [GroupMember]) -> GroupMember? {
            candidates.min { lhs, rhs in
                lhs.joinedAt != rhs.joinedAt ? lhs.joinedAt < rhs.joinedAt : lhs.householdId < rhs.householdId
            }
        }
        return oldest(remaining.filter { $0.role == .coordinator }) ?? oldest(remaining)
    }

    /// Le groupe après la passation : `createdBy` = l'héritier, il rejoint `coordinatorIds` (sans doublon) et
    /// l'ancien créateur en sort. Même résultat que l'écriture Firestore et que `firestore.rules` (isCreatorHandover).
    static func handingOver(_ group: NeighborhoodGroup, from leavingUserId: String, to heirUserId: String) -> NeighborhoodGroup {
        var updated = group
        updated.createdBy = heirUserId
        var coordinators = group.coordinatorIds.filter { $0 != leavingUserId && $0 != heirUserId }
        coordinators.append(heirUserId)
        updated.coordinatorIds = coordinators
        return updated
    }

    /// Lève `.permissionDenied` si `userId` n'a pas créé le groupe.
    static func requireCreator(_ userId: String?, of group: NeighborhoodGroup) throws {
        guard isCreator(userId, of: group) else { throw AppError.permissionDenied }
    }

    /// Nouvelle invitation à usage unique, avec un code absent de `existingCodes`.
    static func makeInvitation<G: RandomNumberGenerator>(
        for group: NeighborhoodGroup, byUserId userId: String, existingCodes: Set<String>,
        now: Date = .now, using rng: inout G
    ) throws -> GroupInvitation {
        try requireCreator(userId, of: group)
        let code = generateInviteCode(avoiding: existingCodes, using: &rng)
        return GroupInvitation(code: code, groupId: group.id, createdBy: userId, createdAt: now)
    }

    static func makeInvitation(for group: NeighborhoodGroup, byUserId userId: String,
                               existingCodes: Set<String> = [], now: Date = .now) throws -> GroupInvitation {
        var rng = SystemRandomNumberGenerator()
        return try makeInvitation(for: group, byUserId: userId, existingCodes: existingCodes, now: now, using: &rng)
    }

    /// Invitation déjà utilisée : message clair pour la personne qui essaie d'entrer.
    static let usedInvitationError = AppError.invalidInput(
        String(localized: "Cette invitation a déjà servi. Demande une nouvelle invitation à la personne qui a créé le groupe.")
    )
    /// Invitation révoquée par le créateur.
    static let revokedInvitationError = AppError.invalidInput(
        String(localized: "Cette invitation a été annulée par la personne qui a créé le groupe. Demande-lui-en une nouvelle.")
    )
    /// Code inconnu (ni invitation ni code d'un groupe public).
    static let unknownInviteCodeError = AppError.invalidInput(
        String(localized: "Ce code d'invitation ne correspond à aucun groupe. Vérifie-le ou demande un nouveau lien.")
    )

    /// Lève une erreur claire si l'invitation ne peut plus servir.
    static func validateForJoining(_ invitation: GroupInvitation) throws {
        switch invitation.status {
        case .active: return
        case .used: throw usedInvitationError
        case .revoked: throw revokedInvitationError
        }
    }

    /// Invitation consommée par `householdId`.
    static func consuming(_ invitation: GroupInvitation, byHousehold householdId: String, now: Date = .now) throws -> GroupInvitation {
        try validateForJoining(invitation)
        var used = invitation
        used.usedBy = householdId
        used.usedAt = now
        return used
    }

    /// Invitation révoquée par le créateur. Une invitation déjà utilisée ne se révoque plus.
    static func revoking(_ invitation: GroupInvitation, in group: NeighborhoodGroup, byUserId userId: String,
                         now: Date = .now) throws -> GroupInvitation {
        try requireCreator(userId, of: group)
        guard invitation.groupId == group.id else { throw AppError.notFound }
        switch invitation.status {
        case .revoked: return invitation
        case .used:
            throw AppError.invalidInput(String(localized: "Cette invitation a déjà servi : il n'y a plus rien à annuler."))
        case .active:
            var revoked = invitation
            revoked.revokedAt = now
            return revoked
        }
    }

    /// Le code fixe d'un groupe ne fait entrer que dans un groupe public.
    static func acceptsFixedCode(_ group: NeighborhoodGroup, code: String) -> Bool {
        group.isPublic && !group.inviteCode.isEmpty && normalizedInviteCode(group.inviteCode) == normalizedInviteCode(code)
    }

    /// Invitations à montrer au créateur : actives d'abord, puis les plus récentes.
    static func sortedForDisplay(_ invitations: [GroupInvitation]) -> [GroupInvitation] {
        invitations.sorted { lhs, rhs in
            let lhsActive = lhs.status == .active, rhsActive = rhs.status == .active
            if lhsActive != rhsActive { return lhsActive }
            return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: - RQ-030 Au plus 3 groupes par ménage

    static let maxGroupsPerHousehold = 3

    /// Vrai si le ménage peut rejoindre `groupId` (déjà membre compris : rien à faire).
    static func canJoin(householdGroupIds: [String], groupId: String) -> Bool {
        householdGroupIds.contains(groupId) || Set(householdGroupIds).count < maxGroupsPerHousehold
    }

    /// Renvoie la liste des groupes du ménage après l'adhésion. Déjà membre : liste inchangée, sans erreur.
    /// Lève `AppError.invalidInput` si le ménage a déjà atteint la limite.
    static func joining(householdGroupIds: [String], groupId: String) throws -> [String] {
        if householdGroupIds.contains(groupId) { return householdGroupIds }
        guard canJoin(householdGroupIds: householdGroupIds, groupId: groupId) else {
            throw AppError.invalidInput(String(localized: "Ton ménage fait déjà partie de \(maxGroupsPerHousehold) groupes. Quittes-en un pour rejoindre celui-ci."))
        }
        return householdGroupIds + [groupId]
    }

    /// B-059 : créer un groupe y fait entrer le ménage ; refusé s'il fait déjà partie de 3 groupes.
    static func canCreateGroup(householdGroupIds: [String]) -> Bool {
        Set(householdGroupIds).count < maxGroupsPerHousehold
    }

    static func requireRoomToCreate(householdGroupIds: [String]) throws {
        guard canCreateGroup(householdGroupIds: householdGroupIds) else {
            throw AppError.invalidInput(String(localized: "Ton ménage fait déjà partie de \(maxGroupsPerHousehold) groupes. Quittes-en un pour en créer un nouveau."))
        }
    }

    // MARK: - RQ-028 Rôle de coordonnateur

    static func isCoordinator(_ id: String, in members: [GroupMember]) -> Bool {
        members.contains { $0.householdId == id && $0.role == .coordinator }
    }

    /// `actorId` nomme `targetId` coordonnateur. Seul un coordonnateur peut le faire ; déjà coordonnateur : inchangé.
    static func appointingCoordinator(_ targetId: String, by actorId: String, in members: [GroupMember]) throws -> [GroupMember] {
        try requireCoordinator(actorId, in: members)
        guard let index = members.firstIndex(where: { $0.householdId == targetId }) else { throw AppError.notFound }
        var updated = members
        updated[index].role = .coordinator
        return updated
    }

    /// `actorId` retire le rôle de coordonnateur à `targetId` (qui reste membre). Le groupe garde au moins un coordonnateur.
    static func removingCoordinator(_ targetId: String, by actorId: String, in members: [GroupMember]) throws -> [GroupMember] {
        try requireCoordinator(actorId, in: members)
        guard let index = members.firstIndex(where: { $0.householdId == targetId }) else { throw AppError.notFound }
        guard members[index].role == .coordinator else { return members }
        try requireAnotherCoordinator(besides: targetId, in: members)
        var updated = members
        updated[index].role = .member
        return updated
    }

    /// Retire `targetId` du groupe. Un coordonnateur peut retirer n'importe qui ; un membre peut seulement partir lui-même.
    /// Le dernier coordonnateur ne peut pas partir : il doit d'abord nommer quelqu'un d'autre.
    static func removingMember(_ targetId: String, by actorId: String, in members: [GroupMember]) throws -> [GroupMember] {
        if actorId != targetId { try requireCoordinator(actorId, in: members) }
        guard let target = members.first(where: { $0.householdId == targetId }) else { throw AppError.notFound }
        if target.role == .coordinator { try requireAnotherCoordinator(besides: targetId, in: members) }
        return members.filter { $0.householdId != targetId }
    }

    /// Même règle sur `NeighborhoodGroup.coordinatorIds` (identifiants d'utilisateurs).
    static func appointingCoordinator(_ targetUserId: String, by actorUserId: String, in group: NeighborhoodGroup) throws -> NeighborhoodGroup {
        guard group.coordinatorIds.contains(actorUserId) else { throw AppError.permissionDenied }
        guard !group.coordinatorIds.contains(targetUserId) else { return group }
        var updated = group
        updated.coordinatorIds.append(targetUserId)
        return updated
    }

    static func removingCoordinator(_ targetUserId: String, by actorUserId: String, in group: NeighborhoodGroup) throws -> NeighborhoodGroup {
        guard group.coordinatorIds.contains(actorUserId) else { throw AppError.permissionDenied }
        guard group.coordinatorIds.contains(targetUserId) else { return group }
        guard group.coordinatorIds.contains(where: { $0 != targetUserId }) else { throw lastCoordinatorError }
        var updated = group
        updated.coordinatorIds.removeAll { $0 == targetUserId }
        return updated
    }

    private static let lastCoordinatorError = AppError.invalidInput(
        String(localized: "Ton groupe doit garder au moins un coordonnateur. Nomme quelqu'un d'autre avant de laisser ce rôle.")
    )

    private static func requireCoordinator(_ actorId: String, in members: [GroupMember]) throws {
        guard isCoordinator(actorId, in: members) else { throw AppError.permissionDenied }
    }

    private static func requireAnotherCoordinator(besides id: String, in members: [GroupMember]) throws {
        guard members.contains(where: { $0.householdId != id && $0.role == .coordinator }) else { throw lastCoordinatorError }
    }
}
