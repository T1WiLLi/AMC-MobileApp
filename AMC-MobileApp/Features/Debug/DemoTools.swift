// DemoTools.swift
// Réinitialisation cachée de la démo (RQ-114, T-078).
// Fake : recharge les dépôts en mémoire depuis `FakeData` et rejoue l'accueil.
// Émulateur ou projet de démo : l'app ne vide jamais Firestore, elle affiche la commande du seed.

import Foundation
import Observation

/// Quand les outils de démo sont accessibles : toujours en Debug, en Release seulement avec `-demoTools`.
nonisolated enum DemoToolsGate {
    static let launchArgument = "-demoTools"

    static func isEnabled(isDebugBuild: Bool, arguments: [String]) -> Bool {
        isDebugBuild || arguments.contains(launchArgument)
    }

    /// Réglage de l'app en cours d'exécution.
    @MainActor static var current: Bool {
        isEnabled(isDebugBuild: FirebaseSetup.isDebugBuild, arguments: ProcessInfo.processInfo.arguments)
    }
}

/// Ce que « Réinitialiser la démo » fait selon le backend.
nonisolated enum DemoResetPlan: Equatable, Sendable {
    /// Données en mémoire : l'app recharge `FakeData` et remet l'accueil à zéro elle-même.
    case reloadFakeData
    /// Firebase : la personne lance le seed dans un terminal, depuis la racine du repo.
    case runSeed(command: String, explanation: String)

    static let emulatorSeedCommand = "npm --prefix scripts/seed run seedDemo"
    static let demoProjectSeedCommand = "npm --prefix scripts/seed run seed:firestore -- --target cloud --yes"

    static func plan(for mode: BackendMode) -> DemoResetPlan {
        switch mode {
        case .fake:
            .reloadFakeData
        case .emulator:
            .runSeed(
                command: emulatorSeedCommand,
                explanation: "Vide l'émulateur demo-grenier (Firestore et comptes Auth) puis recrée la démo."
            )
        case .demoProject:
            .runSeed(
                command: demoProjectSeedCommand,
                explanation: "Réécrit les fixtures du projet de démo à leurs ids stables, sans rien supprimer. Demande une session firebase login."
            )
        }
    }
}

/// Contexte de démo que la racine de l'app injecte, et qu'on peut recharger depuis l'écran caché.
@MainActor
@Observable
final class DemoEnvironment {
    private(set) var context: AppContext
    /// Change à chaque réinitialisation : la racine s'en sert comme `.id` pour recréer tous les écrans et leurs ViewModels.
    private(set) var generation = 0
    private(set) var lastResetAt: Date?

    let mode: BackendMode

    init(context: AppContext = .demo, mode: BackendMode = FirebaseSetup.mode) {
        self.context = context
        self.mode = mode
    }

    var plan: DemoResetPlan { .plan(for: mode) }

    /// Mode fake seulement : dépôts neufs remplis avec `FakeData`, accueil et portail remis à zéro.
    /// Ne fait rien en mode Firebase (l'app ne vide jamais Firestore).
    @discardableResult
    func resetFakeDemo(defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        guard plan == .reloadFakeData else { return false }
        context = .reloadedDemo()
        OnboardingKeys.applyLaunchArguments([OnboardingKeys.resetArgument], to: defaults)
        lastResetAt = now
        generation += 1
        return true
    }
}

extension AppContext {
    /// Mode `.fake` SEULEMENT (`resetFakeDemo`) : mêmes personas et même latence que `.demo`, avec des dépôts neufs
    /// (les commandes passées pendant la démo disparaissent).
    static func reloadedDemo(behavior: FakeBehavior = .realistic) -> AppContext {
        AppContext(
            repositories: .fake(behavior: behavior, data: .montreal).cached(),
            userId: FakeData.ID.amina,
            householdId: FakeData.ID.aminaHousehold,
            groupId: FakeData.ID.saintMichel,
            vendorId: FakeData.ID.moulinsDuNord
        )
    }
}
