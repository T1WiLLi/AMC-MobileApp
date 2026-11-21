import Foundation

/// Erreur unique montrée à l'utilisateur. Les dépôts (Firebase ou fake) convertissent leurs erreurs en `AppError`.
enum AppError: Error, Equatable, Sendable {
    /// Pas de connexion ou serveur injoignable.
    case offline
    /// L'utilisateur doit se connecter (ou sa session a expiré).
    case unauthenticated
    /// Les règles de sécurité ont refusé l'action.
    case permissionDenied
    /// La ressource n'existe plus (lot retiré, groupe supprimé…).
    case notFound
    /// La commande groupée est fermée : on ne peut plus changer sa part.
    case orderClosed
    /// Les Activités en direct sont désactivées pour Grenier (Réglages).
    case liveActivitiesDisabled
    /// Saisie invalide ; le message dit quoi corriger.
    case invalidInput(String)
    /// Autre erreur, avec un détail technique pour les logs.
    case unknown(String)

    var title: String {
        switch self {
        case .offline: "Pas de connexion"
        case .unauthenticated: "Connexion requise"
        case .permissionDenied: "Action non permise"
        case .notFound: "Introuvable"
        case .orderClosed: "Commande fermée"
        case .liveActivitiesDisabled: "Activités en direct désactivées"
        case .invalidInput: "Vérifie ta saisie"
        case .unknown: "Oups, un problème est survenu"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "Vérifie ta connexion Internet, puis réessaie."
        case .unauthenticated:
            "Connecte-toi pour continuer."
        case .permissionDenied:
            "Tu n'as pas les droits pour faire cette action."
        case .notFound:
            "Cet élément n'existe plus. Il a peut-être été retiré."
        case .orderClosed:
            "La date limite est passée : les parts ne peuvent plus être modifiées."
        case .liveActivitiesDisabled:
            "Active-les dans Réglages > Grenier pour suivre ta commande sur l'écran verrouillé."
        case .invalidInput(let detail):
            detail
        case .unknown:
            "Réessaie dans un instant."
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .unauthenticated: "person.crop.circle.badge.exclamationmark"
        case .permissionDenied: "lock.fill"
        case .notFound: "questionmark.folder"
        case .orderClosed: "clock.badge.xmark"
        case .liveActivitiesDisabled: "bell.slash"
        case .invalidInput: "exclamationmark.bubble"
        case .unknown: "exclamationmark.triangle"
        }
    }

    /// Réessayer a du sens (problème passager), contrairement à une saisie invalide ou un refus.
    var isRetryable: Bool {
        switch self {
        case .offline, .unknown: true
        case .unauthenticated, .permissionDenied, .notFound, .orderClosed, .liveActivitiesDisabled, .invalidInput: false
        }
    }

    /// Convertit n'importe quelle erreur en `AppError` (utile dans les `catch` des ViewModels).
    init(_ error: any Error) {
        if let appError = error as? AppError {
            self = appError
        } else if let urlError = error as? URLError,
                  [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(urlError.code) {
            self = .offline
        } else {
            self = .unknown(String(describing: error))
        }
    }
}

extension AppError: LocalizedError {
    var errorDescription: String? { title }
    var failureReason: String? { message }
}
