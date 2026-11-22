import SwiftUI

/// Les portails de Grenier. Un compte peut en avoir plusieurs ; le portail actif choisit la navigation.
///
/// Tout ce qui liste les portails (choix initial, bascule du profil, menu du bouton Profil, écran de
/// bascule) part de `allCases` et des propriétés ci-dessous : ajouter un portail = ajouter un `case`
/// et compléter ces `switch`.
enum Portal: String, CaseIterable, Identifiable, Sendable {
    case family
    case vendor
    /// Organismes communautaires et partenaires (T-116, RQ-081) : financent des paniers, parrainent des groupes.
    case organization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family: String(localized: "Familles")
        case .vendor: String(localized: "Vendeurs")
        case .organization: String(localized: "Organismes")
        }
    }

    var systemImage: String {
        switch self {
        case .family: "house.fill"
        case .vendor: "storefront.fill"
        case .organization: "building.2.fill"
        }
    }

    /// Phrase courte sous le titre d'une `PortalCard` (RQ-014).
    var tagline: String {
        switch self {
        case .family: String(localized: "J'achète avec mon quartier")
        case .vendor: String(localized: "Je vends aux quartiers")
        case .organization: String(localized: "Je soutiens les quartiers")
        }
    }

    /// Sous-titre de l'écran de bascule (T-123), sous le nom du portail.
    var splashTagline: String {
        switch self {
        case .family: String(localized: "Côté familles")
        case .vendor: String(localized: "Côté producteurs")
        case .organization: String(localized: "Côté organismes")
        }
    }

    /// Phrase lue par VoiceOver quand ce portail devient actif.
    var switchAnnouncement: String { String(localized: "Portail \(title), \(splashTagline.lowercased())") }

    /// Détail affiché dans la grande carte du choix du portail.
    var detail: String {
        switch self {
        case .family: String(localized: "Rejoins un groupe, réserve ta part et paie moins cher à chaque palier.")
        case .vendor: String(localized: "Publie tes lots, fixe tes paliers et vois la demande quartier par quartier.")
        case .organization: String(localized: "Finance des paniers suspendus, parraine des groupes et suis ton impact dans les quartiers.")
        }
    }

    /// Teinte du portail (satellites du profil, pastilles) : Solidarite, Economie, Grenier.
    var tint: Color {
        switch self {
        case .family: .solidarite
        case .vendor: .economie
        case .organization: .grenier
        }
    }

    /// Peut-on choisir ce portail à l'accueil ? Un compte ne devient pas organisme de lui-même : l'équipe
    /// Grenier relie le compte à l'organisme (`users/{uid}.organizationId`), voir `OrganizationAccessRequestView`.
    var isSelectableAtOnboarding: Bool { self != .organization }

    /// Explication affichée sous une carte non sélectionnable.
    var unavailableReason: String? {
        isSelectableAtOnboarding ? nil : String(localized: "Les organismes sont ajoutés par l'équipe Grenier. Écris-nous pour inscrire le tien.")
    }

    /// Clé `@AppStorage` du portail actif.
    static let storageKey = "activePortal"
}
