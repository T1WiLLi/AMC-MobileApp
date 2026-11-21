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
        case .family: String(localized: "Familles")
        case .vendor: String(localized: "Vendeurs")
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
        case .family: String(localized: "J'achète avec mon quartier")
        case .vendor: String(localized: "Je vends aux quartiers")
        }
    }

    /// Sous-titre de l'écran de bascule (T-123), sous le nom du portail.
    var splashTagline: String {
        switch self {
        case .family: String(localized: "Côté familles")
        case .vendor: String(localized: "Côté producteurs")
        }
    }

    /// Phrase lue par VoiceOver quand ce portail devient actif.
    var switchAnnouncement: String { String(localized: "Portail \(title), \(splashTagline.lowercased())") }

    /// Détail affiché dans la grande carte du choix du portail.
    var detail: String {
        switch self {
        case .family: String(localized: "Rejoins un groupe, réserve ta part et paie moins cher à chaque palier.")
        case .vendor: String(localized: "Publie tes lots, fixe tes paliers et vois la demande quartier par quartier.")
        }
    }

    /// Clé `@AppStorage` du portail actif.
    static let storageKey = "activePortal"
}
