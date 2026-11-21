import Foundation
import Observation

/// Liens d'invitation reçus par l'app (B-058) : `grenier://join/<code>` ou `https://grenier.app/join/<code>`.
///
/// Un seul `onOpenURL` au niveau de l'app (voir `AMCMobileApp`) passe chaque lien ici avant Google Sign-In.
/// Le code reste en attente tant que personne ne l'a pris : un lien ouvert avant la connexion, ou pendant
/// que l'onglet Groupes n'est pas encore chargé, ouvre quand même la feuille « Rejoindre avec un code ».
@MainActor
@Observable
final class InviteLinkRouter {
    /// Code d'invitation reçu et pas encore présenté.
    private(set) var pendingCode: String?

    /// Retient le code d'un lien d'invitation. Renvoie false pour tout autre lien (Google Sign-In, etc.).
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let code = GroupRules.inviteCode(from: url) else { return false }
        pendingCode = code
        return true
    }

    /// Prend le code en attente, une seule fois.
    func consume() -> String? {
        defer { pendingCode = nil }
        return pendingCode
    }
}
