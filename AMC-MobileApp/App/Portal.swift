import Foundation

/// Les portails de Grenier. Un compte peut en avoir plusieurs ; le portail actif choisit la navigation.
///
/// Tout ce qui liste les portails (choix initial, bascule du profil, menu du bouton Profil, écran de
/// bascule) part de `allCases` et des propriétés ci-dessous : ajouter un portail = ajouter un `case`
/// et compléter ces `switch`.
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

    /// Sous-titre de l'écran de bascule (T-123), sous le nom du portail.
    var splashTagline: String {
        switch self {
        case .family: "Côté familles"
        case .vendor: "Côté producteurs"
        }
    }

    /// Phrase lue par VoiceOver quand ce portail devient actif.
    var switchAnnouncement: String { "Portail \(title), \(splashTagline.lowercased())" }

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
