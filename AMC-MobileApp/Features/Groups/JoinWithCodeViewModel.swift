// JoinWithCodeViewModel.swift
// B-056 : rejoindre un groupe avec un code ou un lien d'invitation (`grenier.app/join/<code>`).
// Invitation à usage unique d'un groupe privé, ou code fixe d'un groupe public. Une invitation déjà
// utilisée ou révoquée donne un message clair (`GroupRules.usedInvitationError` / `revokedInvitationError`).

import Foundation
import Observation

@Observable
@MainActor
final class JoinWithCodeViewModel {
    /// Ce que la personne tape ou colle : un code (« VIL4K7 ») ou un lien.
    var input: String
    private(set) var isJoining = false
    /// Message d'erreur à montrer sous le champ ; nil quand tout va bien.
    private(set) var errorMessage: String?
    /// Groupe rejoint (la feuille se ferme et ouvre sa fiche).
    private(set) var joinedGroup: NeighborhoodGroup?

    private let repositories: AppRepositories
    private let householdId: String

    init(repositories: AppRepositories, householdId: String, input: String = "") {
        self.repositories = repositories
        self.householdId = householdId
        self.input = input
    }

    /// Code lu dans la saisie, nil s'il n'y en a pas encore de valide.
    var code: String? { GroupRules.inviteCode(fromUserInput: input) }
    var canJoin: Bool { code != nil && !isJoining }

    func inputChanged() { errorMessage = nil }

    func join() async {
        guard !isJoining else { return }
        guard let code else {
            errorMessage = String(localized: "Un code d'invitation compte \(GroupRules.inviteCodeLength) lettres ou chiffres. Vérifie celui qu'on t'a envoyé.")
            return
        }
        isJoining = true
        defer { isJoining = false }
        do {
            joinedGroup = try await repositories.groups.join(withCode: code, householdId: householdId)
            errorMessage = nil
        } catch {
            errorMessage = AppError(error).message
        }
    }
}
