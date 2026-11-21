// SessionContextStore.swift
// Contexte de la session en cours (S-03, T-127) : chargé une fois la personne connectée, vidé à la déconnexion.

import Foundation
import Observation

/// Tient l'`AppContext` de la personne connectée. Créé par `AMCMobileApp`, injecté dans l'environnement ;
/// `SessionContextGate` le charge et ne montre l'app qu'une fois le contexte résolu.
@MainActor
@Observable
final class SessionContextStore {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(AppError)
    }

    private(set) var phase: Phase = .idle
    /// `.unresolved` tant que rien n'est chargé : jamais d'id de démo par défaut.
    private(set) var context: AppContext = .unresolved
    private(set) var isCreatingHousehold = false
    /// Erreur de la dernière création de ménage (CTA « Créer mon ménage »).
    private(set) var householdCreationError: AppError?

    private var user: AuthUser?
    private var base: AppContext = .unresolved
    private let defaults: UserDefaults
    /// Démo (`-demoOnboarding`, mode `.fake` seulement) : rejoue l'onboarding sur le contexte de démo déjà résolu.
    private let forcesOnboarding: Bool

    /// Groupe choisi en dernier (mémorisé par appareil) ; repris s'il fait encore partie des groupes du ménage.
    static let preferredGroupKey = "preferredGroupId"

    init(defaults: UserDefaults = .standard, forcesOnboarding: Bool = false) {
        self.defaults = defaults
        self.forcesOnboarding = forcesOnboarding
    }

    /// Ménage actif de la session, `nil` sans contexte résolu ou sans ménage (rafraîchissement en arrière-plan).
    var householdId: String? {
        context.isResolved && context.hasHousehold ? context.householdId : nil
    }

    /// Charge le contexte de `user`.
    /// - `base` déjà résolu (mode `.fake` : `-useFakeData`, CI) : utilisé tel quel ;
    /// - sinon résolu depuis `base.repositories` (Firestore). Sans effet si ce compte est déjà chargé.
    func load(for user: AuthUser, base: AppContext) async {
        if base.isResolved {
            self.user = user
            self.base = base
            context = base
            if forcesOnboarding { context.needsOnboarding = true }
            phase = .ready
            return
        }
        if self.user?.id == user.id, phase == .ready || phase == .loading { return }
        self.user = user
        self.base = base
        await resolve()
    }

    /// Relance la résolution (bouton Réessayer, retour en ligne, après avoir rejoint un groupe).
    func reload() async {
        guard user != nil else { return }
        if base.isResolved { return }
        await resolve()
    }

    /// Change le groupe actif (mémorisé) ; sans effet si le ménage n'en fait pas partie.
    func selectGroup(_ groupId: String?) {
        defaults.set(groupId, forKey: Self.preferredGroupKey)
        guard context.isResolved else { return }
        context.groupId = groupId
    }

    /// CTA « Créer mon ménage » (compte sans ménage, p. ex. un vendeur qui ouvre le portail Familles).
    func createHousehold() async {
        guard let user, !base.isResolved, !isCreatingHousehold else { return }
        isCreatingHousehold = true
        householdCreationError = nil
        defer { isCreatingHousehold = false }
        do {
            context = try await AppContextResolver(repositories: base.repositories)
                .createHousehold(for: user, preferredGroupId: preferredGroupId)
            phase = .ready
        } catch {
            householdCreationError = AppError(error)
        }
    }

    /// Onboarding fini (T-156) : préférences et ménage enregistrés par `OnboardingViewModel`.
    /// Ouvre l'app avec le ménage choisi (créé si le compte n'en avait pas).
    func completeOnboarding(householdId: String) {
        guard context.isResolved else { return }
        context.needsOnboarding = false
        if !householdId.isEmpty, householdId != context.householdId {
            context.householdId = householdId
            context.groupId = nil
        }
    }

    /// Déconnexion : on oublie le contexte (le prochain compte repart de zéro).
    func clear() {
        user = nil
        context = .unresolved
        phase = .idle
        householdCreationError = nil
    }

    private var preferredGroupId: String? { defaults.string(forKey: Self.preferredGroupKey) }

    private func resolve() async {
        guard let user else { return }
        let resolver = AppContextResolver(repositories: base.repositories)
        // Un rechargement garde l'app affichée ; seul le premier chargement montre le squelette.
        if phase != .ready { phase = .loading }
        do {
            let resolved = try await resolver.resolve(user: user, preferredGroupId: preferredGroupId)
            // La personne a pu se déconnecter (ou changer de compte) pendant la lecture.
            guard self.user?.id == user.id else { return }
            context = resolved
            phase = .ready
        } catch {
            guard self.user?.id == user.id else { return }
            if phase != .ready { phase = .failed(AppError(error)) }
        }
    }
}
