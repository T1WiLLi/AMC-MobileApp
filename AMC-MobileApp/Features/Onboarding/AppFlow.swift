import Foundation
import Observation

/// Clés `@AppStorage` de l'accueil (présentation et choix du portail).
enum OnboardingKeys {
    /// Vrai une fois la présentation en 3 écrans vue ou passée (RQ-011).
    static let hasSeenIntro = "hasSeenIntro"
    /// Vrai une fois le portail choisi après la première connexion (RQ-014).
    static let hasChosenPortal = "hasChosenPortal"
    /// Choix fait à l'accueil : `PortalChoice.rawValue` (« family », « vendor,organization »…). Ancien format : « both ».
    static let portalChoice = "portalChoice"

    /// Argument de lancement : rejoue la présentation et le choix du portail (Familles par défaut).
    static let resetArgument = "-resetOnboarding"
    /// Argument de lancement : rouvre l'app côté Familles, quel que soit le dernier portail utilisé (démo du jury).
    static let familyArgument = "-demoFamilyPortal"
    /// Argument de lancement (mode `.fake` seulement) : montre l'onboarding d'après l'inscription (T-156) sur la démo.
    static let demoOnboardingArgument = "-demoOnboarding"
    /// Argument de lancement (mode `.fake` seulement) : la démo sans vendeur, pour montrer l'onboarding producteur (T-158).
    static let demoVendorOnboardingArgument = "-demoVendorOnboarding"

    /// Applique les arguments de démo (Scheme > Arguments). Sans argument, rien ne change.
    static func applyLaunchArguments(_ arguments: [String], to defaults: UserDefaults = .standard) {
        if arguments.contains(resetArgument) {
            for key in [hasSeenIntro, hasChosenPortal, portalChoice, Portal.storageKey] {
                defaults.removeObject(forKey: key)
            }
        }
        if arguments.contains(familyArgument) {
            defaults.set(Portal.family.rawValue, forKey: Portal.storageKey)
        }
        // Appelé à chaque lancement : réécrit l'ancien choix « both » au format multi-portails (T-116).
        PortalChoice.migrateStoredValue(in: defaults)
    }
}

/// Étapes du parcours d'arrivée : présentation → connexion → choix du portail → app.
enum AppFlowStep: Equatable, Sendable {
    case intro
    case signIn
    /// Compte courriel créé ou connecté, en attente du lien de vérification.
    case emailVerification
    case portalChoice
    case app

    /// Étape à afficher selon les drapeaux persistés et l'état de session.
    /// La présentation passe avant tout ; le choix du portail n'arrive qu'une fois connecté (et vérifié), et une seule fois.
    static func resolve(
        hasSeenIntro: Bool,
        isSignedIn: Bool,
        hasChosenPortal: Bool,
        needsEmailVerification: Bool = false
    ) -> AppFlowStep {
        guard hasSeenIntro else { return .intro }
        if needsEmailVerification { return .emailVerification }
        guard isSignedIn else { return .signIn }
        guard hasChosenPortal else { return .portalChoice }
        return .app
    }
}

/// Ce que la personne veut faire de Grenier : un ou plusieurs portails (T-116 : Familles, Vendeurs, Organismes).
///
/// Enregistré sous `OnboardingKeys.portalChoice` comme liste séparée par des virgules (« family,organization »).
/// Migration : les anciennes valeurs « family », « vendor » et « both » (avant le portail Organismes) se relisent.
struct PortalChoice: RawRepresentable, Hashable, Sendable {
    /// Portails choisis, jamais vide.
    let portals: Set<Portal>

    init?(selection: Set<Portal>) {
        guard !selection.isEmpty else { return nil }
        portals = selection
    }

    static let family = PortalChoice(uncheckedPortals: [.family])
    static let vendor = PortalChoice(uncheckedPortals: [.vendor])
    static let organization = PortalChoice(uncheckedPortals: [.organization])
    /// Familles et Vendeurs : l'ancien choix « Les deux ».
    static let both = PortalChoice(uncheckedPortals: [.family, .vendor])

    private init(uncheckedPortals: Set<Portal>) {
        portals = uncheckedPortals
    }

    /// Valeur enregistrée : portails dans l'ordre de `Portal.allCases`, séparés par des virgules.
    var rawValue: String {
        Portal.allCases.filter(portals.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Relit la valeur enregistrée, y compris l'ancien « both ». Une valeur inconnue ou vide donne nil.
    init?(rawValue: String) {
        if rawValue == Self.legacyBoth {
            self = .both
            return
        }
        let parts = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let portals = parts.compactMap(Portal.init(rawValue:))
        guard !portals.isEmpty, portals.count == parts.count else { return nil }
        self.init(uncheckedPortals: Set(portals))
    }

    /// Ancienne valeur « Les deux » (Familles + Vendeurs), avant T-116.
    static let legacyBoth = "both"

    /// Plus d'un portail : la bascule du profil servira tout de suite.
    var isMultiple: Bool { portals.count > 1 }

    /// Portail ouvert après le choix : le premier dans l'ordre Familles, Vendeurs, Organismes.
    var initialPortal: Portal {
        Portal.allCases.first(where: portals.contains) ?? .family
    }

    /// Lit le choix enregistré (avec migration) ; nil s'il n'y en a pas.
    static func stored(in defaults: UserDefaults = .standard) -> PortalChoice? {
        defaults.string(forKey: OnboardingKeys.portalChoice).flatMap(PortalChoice.init(rawValue:))
    }

    /// Réécrit un ancien choix (« both ») au nouveau format. Sans effet si rien n'est enregistré.
    static func migrateStoredValue(in defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: OnboardingKeys.portalChoice),
              let choice = PortalChoice(rawValue: raw),
              choice.rawValue != raw else { return }
        defaults.set(choice.rawValue, forKey: OnboardingKeys.portalChoice)
    }
}

/// Logique de l'écran « Comment veux-tu utiliser Grenier ? » : sélection multiple et enregistrement.
@MainActor
@Observable
final class PortalChoiceViewModel {
    private(set) var selection: Set<Portal>

    /// Une sélection de départ (valeur restaurée, aperçu) ne peut contenir que des portails sélectionnables.
    init(selection: Set<Portal> = []) {
        self.selection = selection.filter(\.isSelectableAtOnboarding)
    }

    var choice: PortalChoice? { PortalChoice(selection: selection) }
    var canContinue: Bool { choice != nil }

    func isSelected(_ portal: Portal) -> Bool { selection.contains(portal) }

    /// Ignoré pour un portail non sélectionnable (Organismes).
    func toggle(_ portal: Portal) {
        guard portal.isSelectableAtOnboarding else { return }
        if selection.contains(portal) {
            selection.remove(portal)
        } else {
            selection.insert(portal)
        }
    }

    /// Phrase sous les cartes, qui suit la sélection.
    var hint: String {
        guard let choice else { return String(localized: "Choisis une carte, ou plusieurs.") }
        switch choice {
        case .family: return String(localized: "Tu pourras aussi vendre plus tard, depuis ton profil.")
        case .vendor: return String(localized: "Tu pourras aussi acheter avec ton quartier, depuis ton profil.")
        case .organization: return String(localized: "Tu pourras aussi acheter ou vendre plus tard, depuis ton profil.")
        case .both: return String(localized: "Les deux : tu passeras de l'un à l'autre dans ton profil.")
        default:
            return String(localized: "\(FrenchPlural.count(choice.portals.count, "portail")) : tu passeras de l'un à l'autre dans ton profil.")
        }
    }

    /// Enregistre le choix (portail actif + drapeau) ; renvoie faux s'il n'y a rien de choisi.
    @discardableResult
    func confirm(in defaults: UserDefaults = .standard) -> Bool {
        guard let choice, choice.portals.allSatisfy(\.isSelectableAtOnboarding) else { return false }
        defaults.set(choice.initialPortal.rawValue, forKey: Portal.storageKey)
        defaults.set(choice.rawValue, forKey: OnboardingKeys.portalChoice)
        defaults.set(true, forKey: OnboardingKeys.hasChosenPortal)
        return true
    }
}
