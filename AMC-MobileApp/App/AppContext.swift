import SwiftUI

/// Ce dont les écrans ont besoin pour créer leurs ViewModels : les dépôts et l'identité de démo.
/// Injecté une fois dans l'environnement ; chaque écran lit `@Environment(\.appContext)`.
/// Tant que la connexion n'alimente pas les IDs réels, on utilise les personas de `FakeData` (Amina, Saint-Michel).
struct AppContext: Sendable {
    var repositories: AppRepositories
    var userId: String
    var householdId: String
    /// Groupe actif du ménage (nil : pas encore de groupe).
    var groupId: String?
    /// Vendeur du portail Vendeurs.
    var vendorId: String

    /// Données fake réalistes (latence 300–800 ms) : previews, CI, démo sans réseau.
    /// Derrière le cache mémoire (T-112), comme en Firebase : un écran déjà vu se rouvre sans attendre.
    static let demo = AppContext(
        repositories: .fake().cached(),
        userId: FakeData.ID.amina,
        householdId: FakeData.ID.aminaHousehold,
        groupId: FakeData.ID.saintMichel,
        vendorId: FakeData.ID.moulinsDuNord
    )

    /// Même chose sans latence : tests et previews instantanées.
    static let instant = AppContext(
        repositories: .fake(behavior: .instant),
        userId: FakeData.ID.amina,
        householdId: FakeData.ID.aminaHousehold,
        groupId: FakeData.ID.saintMichel,
        vendorId: FakeData.ID.moulinsDuNord
    )
}

extension EnvironmentValues {
    @Entry var appContext: AppContext = .demo
}
