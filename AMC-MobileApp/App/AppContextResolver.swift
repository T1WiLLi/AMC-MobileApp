// AppContextResolver.swift
// Contexte de la personne connectée (S-03, T-127) : uid → users/{uid} → ménage, groupe principal, vendeur.
// Plus aucun id de persona en dur : tout vient des dépôts (Firestore en vrai, fakes dans les tests).

import Foundation

/// Résout l'`AppContext` d'un utilisateur connecté à partir des dépôts.
///
/// Règles :
/// - `users/{uid}` absent (compte tout juste créé) : on crée son ménage puis son profil, pour que le portail
///   Familles marche tout de suite (rejoindre un groupe demande un ménage). Le profil créé ne pose jamais `vendorId` :
///   il se pose à la fin de l'onboarding producteur (`createVendor`, T-158), ou par le seed.
/// - `householdId` : celui du profil, ou vide si la personne n'a pas de ménage (vendeur seul) ;
/// - `groupId` : le groupe préféré s'il fait encore partie des groupes du ménage, sinon le premier par nom, sinon nil ;
/// - `vendorId` : celui du profil, ou vide ;
/// - `organizationId` (T-194) : celui du profil (posé par le seed), ou vide : sans lui, le portail Organisme reste fermé.
nonisolated struct AppContextResolver: Sendable {
    var repositories: AppRepositories

    init(repositories: AppRepositories) {
        self.repositories = repositories
    }

    /// Contexte résolu de `user`. Lève une `AppError` si une lecture échoue (hors ligne, règles).
    func resolve(user: AuthUser, preferredGroupId: String? = nil) async throws -> AppContext {
        var profile: AppUser
        do {
            profile = try await repositories.users.user(id: user.id)
        } catch AppError.notFound {
            profile = try await createProfile(for: user)
        }
        profile = try await finishJoinIfAccepted(profile)
        profile = try await leaveHouseholdIfRemoved(profile, user: user)
        return try await context(for: profile, preferredGroupId: preferredGroupId)
    }

    // MARK: - Ménage partagé (T-159)

    /// Demande pour rejoindre un ménage acceptée par son propriétaire : le profil pointe maintenant vers ce ménage
    /// (la règle vérifie que l'uid est dans `userIds`), et la demande, devenue inutile, est supprimée.
    /// Demande toujours en attente, ou supprimée (refusée) : le profil ne change pas.
    func finishJoinIfAccepted(_ profile: AppUser) async throws -> AppUser {
        guard let pendingId = profile.pendingHouseholdId, !pendingId.isEmpty else { return profile }
        guard let request = try await repositories.users.joinRequest(householdId: pendingId, userId: profile.id),
              request.status == .accepted else { return profile }
        var profile = profile
        profile.householdId = pendingId
        profile.pendingHouseholdId = nil
        if !profile.roles.contains(.family) { profile.roles.append(.family) }
        try await repositories.users.saveUser(profile)
        try? await repositories.users.deleteJoinRequest(householdId: pendingId, userId: profile.id)
        return profile
    }

    /// Le propriétaire a retiré la personne du ménage : elle retrouve son propre ménage (`household-{uid}`),
    /// recréé s'il le faut, pour que le portail Familles marche encore.
    private func leaveHouseholdIfRemoved(_ profile: AppUser, user: AuthUser) async throws -> AppUser {
        guard let householdId = profile.householdId, !householdId.isEmpty,
              householdId != Self.householdId(forUserId: profile.id) else { return profile }
        do {
            let household = try await repositories.users.household(id: householdId)
            if household.userIds.contains(profile.id) { return profile }
        } catch AppError.permissionDenied {
            // Plus membre : les règles refusent la lecture du ménage. On continue.
        } catch {
            // Hors ligne, document absent des fakes… : on ne touche pas au profil.
            return profile
        }
        let own: Household
        if let existing = try? await repositories.users.household(id: Self.householdId(forUserId: profile.id)),
           existing.userIds.contains(profile.id) {
            own = existing
        } else {
            own = Self.newHousehold(for: user)
            try await repositories.users.saveHousehold(own)
        }
        var profile = profile
        profile.householdId = own.id
        try await repositories.users.saveUser(profile)
        return profile
    }

    /// Crée un ménage pour un profil qui n'en a pas (CTA « Créer mon ménage ») et renvoie le contexte à jour.
    func createHousehold(for user: AuthUser, preferredGroupId: String? = nil) async throws -> AppContext {
        var profile = try await repositories.users.user(id: user.id)
        if profile.householdId == nil || profile.householdId?.isEmpty == true {
            let household = Self.newHousehold(for: user)
            try await repositories.users.saveHousehold(household)
            profile.householdId = household.id
            if !profile.roles.contains(.family) { profile.roles.append(.family) }
            try await repositories.users.saveUser(profile)
        }
        return try await context(for: profile, preferredGroupId: preferredGroupId)
    }

    /// Onboarding producteur (T-158) : crée le vendeur du compte puis le rattache au profil (`vendorId`, rôle vendeur).
    /// L'ordre compte (firestore.rules) : le profil ne pointe que vers un vendeur existant dont il est propriétaire.
    /// Le vendeur part non vérifié et sans note, quoi que contienne `draft`. Relancer après une coupure est sans danger.
    func createVendor(_ draft: Vendor, forUserId userId: String) async throws -> Vendor {
        var vendor = draft
        vendor.id = Vendor.ownedId(forUserId: userId)
        vendor.ownerId = userId
        vendor.isVerified = false
        vendor.averageRating = nil
        let created = try await repositories.vendors.createVendor(vendor)
        var profile = try await repositories.users.user(id: userId)
        if profile.vendorId != created.id {
            profile.vendorId = created.id
            if !profile.roles.contains(.vendor) { profile.roles.append(.vendor) }
            try await repositories.users.saveUser(profile)
        }
        return created
    }

    // MARK: - Étapes

    private func context(for profile: AppUser, preferredGroupId: String?) async throws -> AppContext {
        let householdId = profile.householdId ?? ""
        var groupId: String?
        if !householdId.isEmpty {
            let groups = try await repositories.groups.groups(ofHousehold: householdId)
            groupId = Self.primaryGroupId(among: groups.map(\.id), preferred: preferredGroupId)
        }
        return AppContext(
            repositories: repositories,
            userId: profile.id,
            householdId: householdId,
            groupId: groupId,
            vendorId: profile.vendorId ?? "",
            status: .resolved,
            organizationId: profile.organizationId ?? "",
            needsOnboarding: profile.needsOnboarding
        )
    }

    /// Ménage d'abord (la règle du profil vérifie que la personne en fait partie), profil ensuite.
    private func createProfile(for user: AuthUser) async throws -> AppUser {
        let household = Self.newHousehold(for: user)
        try await repositories.users.saveHousehold(household)
        let profile = AppUser(
            id: user.id,
            displayName: Self.displayName(for: user),
            photoURL: user.photoURL,
            language: .french,
            roles: [.family],
            neighborhood: "",
            dietaryPreferences: [],
            seniorMode: false,
            householdId: household.id,
            vendorId: nil,
            // Compte tout neuf : l'onboarding (préférences, ménage) s'affiche avant l'app (T-156).
            onboardingCompleted: false
        )
        try await repositories.users.saveUser(profile)
        return profile
    }

    // MARK: - Règles pures

    /// Groupe principal : le préféré s'il est encore dans la liste, sinon le premier (la liste est triée par nom).
    static func primaryGroupId(among groupIds: [String], preferred: String?) -> String? {
        if let preferred, groupIds.contains(preferred) { return preferred }
        return groupIds.first
    }

    /// Id stable du ménage créé pour un compte : relancer la création réécrit le même document.
    static func householdId(forUserId userId: String) -> String { "household-\(userId)" }

    static func newHousehold(for user: AuthUser) -> Household {
        Household(
            id: householdId(forUserId: user.id),
            name: String(localized: "Ménage de \(displayName(for: user))"),
            size: 1,
            geohash: "",
            userIds: [user.id],
            ownerId: user.id,
            memberNames: [user.id: displayName(for: user)]
        )
    }

    /// Nom affiché : celui du compte, sinon la partie avant @ du courriel, sinon « Voisin ».
    static func displayName(for user: AuthUser) -> String {
        let name = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return String(name.prefix(80)) }
        let local = user.email.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? String(localized: "Voisin") : String(local.prefix(80))
    }
}
