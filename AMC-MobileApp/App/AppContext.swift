import Foundation
import SwiftUI

/// Ce dont les écrans ont besoin pour créer leurs ViewModels : les dépôts et l'identité de la personne connectée.
/// Chaque écran lit `@Environment(\.appContext)`.
///
/// S-03 / T-127 — à l'exécution, le contexte vient de la session : uid → `users/{uid}` → ménage, groupe principal,
/// vendeur (`AppContextResolver`, chargé par `SessionContextGate`). Les écrans ne sont montrés qu'une fois le contexte
/// résolu. Un contexte peut être résolu mais incomplet : `hasHousehold`, `hasGroup`, `hasVendor` disent quoi afficher
/// (voir `ContextRequirementView` pour les états « Rejoins un groupe », « Crée ton profil vendeur »).
struct AppContext: Sendable {
    /// Résolu depuis la session, ou pas encore (chargement, déconnecté).
    enum Status: Sendable, Equatable {
        case resolved
        case unresolved
    }

    var repositories: AppRepositories
    var userId: String
    /// Ménage de la personne ; vide si elle n'en a pas (vendeur seul).
    var householdId: String
    /// Groupe actif du ménage (nil : pas encore de groupe).
    var groupId: String?
    /// Vendeur rattaché au compte (`users/{uid}.vendorId`) ; vide si la personne n'est pas vendeur.
    var vendorId: String
    var status: Status = .resolved
    /// Organisme du portail Organismes (T-116) ; vide tant que le compte n'est rattaché à aucun organisme.
    var organizationId: String = ""
    /// Compte qui vient de s'inscrire et n'a pas fini l'onboarding (T-156) : `SessionContextGate` montre
    /// `OnboardingFlowScreen` avant l'app. Faux pour les comptes d'avant T-156 et en démo.
    var needsOnboarding: Bool = false

    /// true une fois le contexte chargé depuis la session (ou fixé pour un test / une preview).
    var isResolved: Bool { status == .resolved && !userId.isEmpty }
    var hasHousehold: Bool { !householdId.isEmpty }
    var hasGroup: Bool { groupId?.isEmpty == false }
    var hasVendor: Bool { !vendorId.isEmpty }
    var hasOrganization: Bool { !organizationId.isEmpty }

    /// Valeur par défaut hors session : aucun id, dépôts vides. Un écran qui le reçoit doit afficher un chargement,
    /// jamais des données de démo.
    static let unresolved = AppContext(
        repositories: .empty(),
        userId: "",
        householdId: "",
        groupId: nil,
        vendorId: "",
        status: .unresolved
    )

    /// PREVIEWS, TESTS ET MODE `.fake` SEULEMENT (`-useFakeData`, CI) — jamais avec Firebase.
    /// Personas de `FakeData` (Amina, Parc-Extension, Ferme Lafleur), latence réaliste, derrière le cache mémoire (T-112).
    static let demo = AppContext(
        repositories: .fake(data: .demo).cached(),
        userId: FakeData.ID.amina,
        householdId: FakeData.ID.aminaHousehold,
        groupId: FakeData.ID.parcExtension,
        vendorId: FakeData.ID.fermeLafleur,
        organizationId: FakeData.ID.laRuche
    )

    /// PREVIEWS ET TESTS SEULEMENT : comme `.demo`, sans latence.
    static let instant = AppContext(
        repositories: .fake(behavior: .instant),
        userId: FakeData.ID.amina,
        householdId: FakeData.ID.aminaHousehold,
        groupId: FakeData.ID.parcExtension,
        vendorId: FakeData.ID.fermeLafleur,
        organizationId: FakeData.ID.laRuche
    )

    /// Contexte de base injecté au lancement, avant la session :
    /// - `.fake` (explicite : `-useFakeData`, CI, pas de plist) → la démo en mémoire, déjà résolue ;
    /// - Firebase → dépôts live NON résolus : `SessionContextGate` les résout avec le compte connecté.
    static func launch(mode: BackendMode) -> AppContext {
        switch mode {
        case .fake:
            return .demo
        case .emulator, .demoProject:
            var context = AppContext.unresolved
            context.repositories = .live(mode: mode)
            return context
        }
    }

    /// Défaut de l'environnement : `.unresolved` à l'exécution ; la démo dans le canevas des previews Xcode,
    /// pour qu'une preview sans `.environment(\.appContext, …)` reste remplie.
    static var environmentDefault: AppContext {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? .demo : .unresolved
    }
}

extension EnvironmentValues {
    @Entry var appContext: AppContext = .environmentDefault
}
