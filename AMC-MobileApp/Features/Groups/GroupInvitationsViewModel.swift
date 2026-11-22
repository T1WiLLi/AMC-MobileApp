// GroupInvitationsViewModel.swift
// B-056 : ce que voit le créateur d'un groupe sur sa fiche — la visibilité (public ou privé) et,
// pour un groupe privé, ses invitations à usage unique (créer, partager, voir l'état, révoquer).
//
// Usage dans la fiche (créateur seulement, `GroupRules.isCreator`) :
//   @State private var invitations = GroupInvitationsViewModel(repositories:, group:, userId:)
//   .task { await invitations.load() }
//   Toggle lié à `invitations.isPrivate` → `setPrivate(_:)` ; liste `invitations.items`.

import Foundation
import Observation

@Observable
@MainActor
final class GroupInvitationsViewModel {
    private(set) var group: NeighborhoodGroup
    /// Invitations du groupe, actives d'abord ; `.empty` s'il n'y en a pas encore.
    private(set) var state: LoadState<[GroupInvitation]> = .idle
    /// Changement de visibilité, création ou révocation en cours.
    private(set) var isWorking = false
    /// Invitation qui vient d'être créée (à partager tout de suite).
    private(set) var lastCreated: GroupInvitation?
    /// Dernière erreur d'une action, à montrer en alerte ; remise à nil par la vue.
    var actionError: AppError?

    private let repositories: AppRepositories
    private let userId: String

    init(repositories: AppRepositories, group: NeighborhoodGroup, userId: String) {
        self.repositories = repositories
        self.group = group
        self.userId = userId
    }

    var isPrivate: Bool { !group.isPublic }
    var items: [GroupInvitation] { state.value ?? [] }
    var activeCount: Int { items.filter { $0.status == .active }.count }

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, groupId = group.id, userId = userId
        let result = await LoadState<[GroupInvitation]>.run {
            try await repositories.groups.invitations(ofGroup: groupId, byUserId: userId)
        }
        if let items = result.value { state = .from(items) } else { state = result }
    }

    /// Rend le groupe privé (sur invitation) ou public (listé). Renvoie le groupe à jour, nil en cas d'erreur.
    @discardableResult
    func setPrivate(_ isPrivate: Bool) async -> NeighborhoodGroup? {
        guard !isWorking, isPrivate != self.isPrivate else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            group = try await repositories.groups.setVisibility(isPublic: !isPrivate, ofGroup: group.id, byUserId: userId)
            return group
        } catch {
            actionError = AppError(error)
            return nil
        }
    }

    /// Crée une invitation à usage unique et la met en tête de liste.
    @discardableResult
    func create() async -> GroupInvitation? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let invitation = try await repositories.groups.createInvitation(forGroup: group.id, byUserId: userId)
            lastCreated = invitation
            state = .loaded(GroupRules.sortedForDisplay([invitation] + items.filter { $0.code != invitation.code }))
            return invitation
        } catch {
            actionError = AppError(error)
            return nil
        }
    }

    /// Révoque une invitation pas encore utilisée.
    func revoke(_ invitation: GroupInvitation) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let revoked = try await repositories.groups.revokeInvitation(code: invitation.code, ofGroup: group.id, byUserId: userId)
            if lastCreated?.code == revoked.code { lastCreated = nil }
            state = .loaded(GroupRules.sortedForDisplay(items.map { $0.code == revoked.code ? revoked : $0 }))
        } catch {
            actionError = AppError(error)
        }
    }

    /// Message prêt à envoyer avec le lien d'invitation.
    nonisolated static func shareMessage(groupName: String, invitation: GroupInvitation) -> String {
        let link = invitation.shareURL?.absoluteString ?? invitation.code
        return String(localized: "Je t'invite dans « \(groupName) » sur LeGrenier, un groupe privé. Cette invitation sert une seule fois : \(link) (code \(invitation.code))")
    }
}
