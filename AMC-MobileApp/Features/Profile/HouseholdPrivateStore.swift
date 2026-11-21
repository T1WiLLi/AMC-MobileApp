// HouseholdPrivateStore.swift
// RQ-020 : le document privé `households/{id}/private/profile` (statut subventionné).
// Pas encore de dépôt dans `AppRepositories` : ce protocole local suffit à la démo et aux tests.
// Quand un dépôt Firestore existera, il implémentera ce protocole (à annoncer dans le board avant
// d'ajouter des méthodes à `UserRepository`).

import SwiftUI

nonisolated protocol HouseholdPrivateStore: Sendable {
    /// Profil privé du ménage ; `nil` s'il n'a jamais rien demandé.
    func privateProfile(householdId: String) async throws -> HouseholdPrivate?
    func savePrivateProfile(_ profile: HouseholdPrivate, householdId: String) async throws
}

/// En mémoire. `shared` garde le statut entre deux ouvertures de l'écran pendant la démo.
actor FakeHouseholdPrivateStore: HouseholdPrivateStore {
    static let shared = FakeHouseholdPrivateStore(behavior: .realistic)

    private let behavior: FakeBehavior
    private var profiles: [String: HouseholdPrivate]

    init(behavior: FakeBehavior = .instant, profiles: [String: HouseholdPrivate] = [:]) {
        self.behavior = behavior
        self.profiles = profiles
    }

    func privateProfile(householdId: String) async throws -> HouseholdPrivate? {
        try await behavior.simulate()
        return profiles[householdId]
    }

    func savePrivateProfile(_ profile: HouseholdPrivate, householdId: String) async throws {
        try await behavior.simulate()
        profiles[householdId] = profile
    }
}

extension EnvironmentValues {
    @Entry var householdPrivateStore: any HouseholdPrivateStore = FakeHouseholdPrivateStore.shared
}
