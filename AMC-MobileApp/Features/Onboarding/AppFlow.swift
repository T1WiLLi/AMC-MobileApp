import Foundation
import Observation

/// Clés `@AppStorage` de l'accueil (présentation et choix du portail).
enum OnboardingKeys {
    /// Vrai une fois la présentation en 3 écrans vue ou passée (RQ-011).
    static let hasSeenIntro = "hasSeenIntro"
    /// Vrai une fois le portail choisi après la première connexion (RQ-014).
    static let hasChosenPortal = "hasChosenPortal"
    /// Choix fait à l'accueil : `PortalChoice.rawValue` (« family », « vendor », « both »).
    static let portalChoice = "portalChoice"

    /// Argument de lancement : rejoue la présentation et le choix du portail (Familles par défaut).
    static let resetArgument = "-resetOnboarding"
    /// Argument de lancement : rouvre l'app côté Familles, quel que soit le dernier portail utilisé (démo du jury).
    static let familyArgument = "-demoFamilyPortal"

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
    }
}

/// Étapes du parcours d'arrivée : présentation → connexion → choix du portail → app.
enum AppFlowStep: Equatable, Sendable {
    case intro
    case signIn
    case portalChoice
    case app

    /// Étape à afficher selon les drapeaux persistés et l'état de session.
    /// La présentation passe avant tout ; le choix du portail n'arrive qu'une fois connecté, et une seule fois.
    static func resolve(hasSeenIntro: Bool, isSignedIn: Bool, hasChosenPortal: Bool) -> AppFlowStep {
        guard hasSeenIntro else { return .intro }
        guard isSignedIn else { return .signIn }
        guard hasChosenPortal else { return .portalChoice }
        return .app
    }
}

/// Ce que la personne veut faire de Grenier. « Les deux » ouvre le portail Familles en premier.
enum PortalChoice: String, CaseIterable, Sendable {
    case family
    case vendor
    case both

    init?(selection: Set<Portal>) {
        switch (selection.contains(.family), selection.contains(.vendor)) {
        case (true, true): self = .both
        case (true, false): self = .family
        case (false, true): self = .vendor
        case (false, false): return nil
        }
    }

    /// Portail ouvert après le choix.
    var initialPortal: Portal {
        self == .vendor ? .vendor : .family
    }

    var portals: Set<Portal> {
        switch self {
        case .family: [.family]
        case .vendor: [.vendor]
        case .both: [.family, .vendor]
        }
    }
}

/// Logique de l'écran « Comment veux-tu utiliser Grenier ? » : sélection multiple et enregistrement.
@MainActor
@Observable
final class PortalChoiceViewModel {
    private(set) var selection: Set<Portal>

    init(selection: Set<Portal> = []) {
        self.selection = selection
    }

    var choice: PortalChoice? { PortalChoice(selection: selection) }
    var canContinue: Bool { choice != nil }

    func isSelected(_ portal: Portal) -> Bool { selection.contains(portal) }

    func toggle(_ portal: Portal) {
        if selection.contains(portal) {
            selection.remove(portal)
        } else {
            selection.insert(portal)
        }
    }

    /// Phrase sous les cartes, qui suit la sélection.
    var hint: String {
        switch choice {
        case nil: "Choisis une carte, ou les deux."
        case .family: "Tu pourras aussi vendre plus tard, depuis ton profil."
        case .vendor: "Tu pourras aussi acheter avec ton quartier, depuis ton profil."
        case .both: "Les deux : tu passeras de l'un à l'autre dans ton profil."
        }
    }

    /// Enregistre le choix (portail actif + drapeau) ; renvoie faux s'il n'y a rien de choisi.
    @discardableResult
    func confirm(in defaults: UserDefaults = .standard) -> Bool {
        guard let choice else { return false }
        defaults.set(choice.initialPortal.rawValue, forKey: Portal.storageKey)
        defaults.set(choice.rawValue, forKey: OnboardingKeys.portalChoice)
        defaults.set(true, forKey: OnboardingKeys.hasChosenPortal)
        return true
    }
}
