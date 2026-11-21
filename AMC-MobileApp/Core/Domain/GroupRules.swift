// GroupRules.swift
// Règles des groupes de voisinage (E03 : RQ-025, RQ-026, RQ-028, RQ-030).
// Swift pur, sans Firebase ni UI : les dépôts (Firebase ou fake) et les ViewModels l'appellent.

import Foundation

nonisolated enum GroupRules {
    // MARK: - RQ-025 Création d'un groupe

    static let nameLengthRange = 3...40
    static let radiusRangeMeters = 1_000...2_000

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
            throw AppError.invalidInput("Donne un nom d'au moins \(nameLengthRange.lowerBound) caractères à ton groupe.")
        }
        if clean.name.count > nameLengthRange.upperBound {
            throw AppError.invalidInput("Le nom de ton groupe doit faire \(nameLengthRange.upperBound) caractères au maximum.")
        }
        if clean.neighborhood.isEmpty {
            throw AppError.invalidInput("Choisis le quartier de ton groupe.")
        }
        if clean.centerGeohash.isEmpty {
            throw AppError.invalidInput("Indique le centre de ton groupe sur la carte.")
        }
        if !radiusRangeMeters.contains(clean.radiusMeters) {
            throw AppError.invalidInput("Choisis un rayon entre 1 et 2 km.")
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
            inviteCode: makeInviteCode()
        )
        let member = GroupMember(householdId: creatorHouseholdId, role: .coordinator, joinedAt: now)
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
            throw AppError.invalidInput("Un code d'invitation compte \(inviteCodeLength) lettres ou chiffres. Vérifie celui qu'on t'a envoyé.")
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

    /// Extrait le code d'un lien d'invitation. Accepte seulement `grenier://join/<code>`
    /// et `https://grenier.app/join/<code>` ; tout autre schéma, hôte ou chemin renvoie nil.
    static func inviteCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let host = components.host?.lowercased()
        let candidate: String?
        switch scheme {
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

    /// Ce que la personne colle dans le champ « Rejoindre » : un code seul ou un lien d'invitation.
    static func inviteCode(fromUserInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://"), let url = URL(string: trimmed) {
            return inviteCode(from: url)
        }
        return isValidInviteCode(trimmed) ? normalizedInviteCode(trimmed) : nil
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
            throw AppError.invalidInput("Ton ménage fait déjà partie de \(maxGroupsPerHousehold) groupes. Quittes-en un pour rejoindre celui-ci.")
        }
        return householdGroupIds + [groupId]
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
        "Ton groupe doit garder au moins un coordonnateur. Nomme quelqu'un d'autre avant de laisser ce rôle."
    )

    private static func requireCoordinator(_ actorId: String, in members: [GroupMember]) throws {
        guard isCoordinator(actorId, in: members) else { throw AppError.permissionDenied }
    }

    private static func requireAnotherCoordinator(besides id: String, in members: [GroupMember]) throws {
        guard members.contains(where: { $0.householdId != id && $0.role == .coordinator }) else { throw lastCoordinatorError }
    }
}
