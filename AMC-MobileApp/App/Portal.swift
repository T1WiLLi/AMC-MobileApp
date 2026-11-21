import Foundation

/// Les deux portails de Grenier. Un compte peut avoir les deux ; le portail actif choisit la navigation.
enum Portal: String, CaseIterable, Identifiable, Sendable {
    case family
    case vendor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family: "Familles"
        case .vendor: "Vendeurs"
        }
    }

    var systemImage: String {
        switch self {
        case .family: "house.fill"
        case .vendor: "storefront.fill"
        }
    }

    /// Phrase courte sous le titre d'une `PortalCard` (RQ-014).
    var tagline: String {
        switch self {
        case .family: "J'achète avec mon quartier"
        case .vendor: "Je vends aux quartiers"
        }
    }

    /// Détail affiché dans la grande carte du choix du portail.
    var detail: String {
        switch self {
        case .family: "Rejoins un groupe, réserve ta part et paie moins cher à chaque palier."
        case .vendor: "Publie tes lots, fixe tes paliers et vois la demande quartier par quartier."
        }
    }

    /// Clé `@AppStorage` du portail actif.
    static let storageKey = "activePortal"
}
