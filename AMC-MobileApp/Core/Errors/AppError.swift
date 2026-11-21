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
        case .offline: String(localized: "Pas de connexion")
        case .unauthenticated: String(localized: "Connexion requise")
        case .permissionDenied: String(localized: "Action non permise")
        case .notFound: String(localized: "Introuvable")
        case .orderClosed: String(localized: "Commande fermée")
        case .liveActivitiesDisabled: String(localized: "Activités en direct désactivées")
        case .invalidInput: String(localized: "Vérifie ta saisie")
        case .unknown: String(localized: "Oups, un problème est survenu")
        }
    }

    var message: String {
        switch self {
        case .offline:
            String(localized: "Vérifie ta connexion Internet, puis réessaie.")
        case .unauthenticated:
            String(localized: "Connecte-toi pour continuer.")
        case .permissionDenied:
            String(localized: "Tu n'as pas les droits pour faire cette action.")
        case .notFound:
            String(localized: "Cet élément n'existe plus. Il a peut-être été retiré.")
        case .orderClosed:
            String(localized: "La date limite est passée : les parts ne peuvent plus être modifiées.")
        case .liveActivitiesDisabled:
            String(localized: "Active-les dans Réglages > LeGrenier pour suivre ta commande sur l'écran verrouillé.")
        case .invalidInput(let detail):
            detail
        case .unknown:
            String(localized: "Réessaie dans un instant.")
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

    /// Détail de `.unknown` pour un chargement annulé : la `.task` de l'écran s'est arrêtée parce que
    /// l'écran a disparu (onglet quitté avant la fin). Ce n'est pas une panne à montrer à l'utilisateur.
    static let cancelledDetail = String(localized: "Chargement annulé")

    /// true si l'erreur vient d'une tâche annulée (voir `cancelledDetail`).
    var isCancellation: Bool { self == .unknown(Self.cancelledDetail) }

    /// Convertit n'importe quelle erreur en `AppError` (utile dans les `catch` des ViewModels).
    init(_ error: any Error) {
        if let appError = error as? AppError {
            self = appError
        } else if error is CancellationError {
            self = .unknown(Self.cancelledDetail)
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
