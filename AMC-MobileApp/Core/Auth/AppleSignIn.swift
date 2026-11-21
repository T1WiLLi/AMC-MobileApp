import AuthenticationServices
import CryptoKit
import Foundation

/// Outils de « Se connecter avec Apple » (RQ-012) : flag, nonce, lecture du résultat d'`ASAuthorization`.
/// Logique pure, sans Firebase : partagée par `SessionViewModel` et testée sans réseau.
nonisolated enum AppleSignIn {
    /// Clé Info.plist qui affiche le bouton. À mettre à `false` si l'App ID n'a pas la capability
    /// Sign in with Apple (compte Apple gratuit, « Personal Team ») : voir docs/firebase.md §3.
    static let infoPlistKey = "GRNSignInWithAppleEnabled"

    /// Le bouton Apple est-il affiché ? Lu une fois dans l'Info.plist (absent = caché).
    static let isEnabled: Bool = isEnabled(in: Bundle.main.infoDictionary ?? [:])

    static func isEnabled(in info: [String: Any]) -> Bool {
        info[infoPlistKey] as? Bool ?? false
    }

    // MARK: Nonce

    /// Nonce aléatoire (32 caractères URL-safe). Le brut part à Firebase, son SHA-256 dans la requête Apple.
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    /// SHA-256 en hexadécimal minuscule, le format attendu par Apple et Firebase.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: Résultat d'Apple

    /// Jeton et nom renvoyés par Apple (le nom n'arrive qu'à la toute première connexion).
    struct Credential: Equatable, Sendable {
        var idToken: String
        var fullName: PersonNameComponents?
    }

    /// L'utilisateur a fermé la feuille Apple : pas de message d'erreur.
    static func isCancellation(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// Lit le jeton d'identité dans le résultat d'Apple.
    static func credential(from authorization: ASAuthorization) throws -> Credential {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = apple.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            throw AuthError.failed(String(localized: "Apple n'a pas renvoyé d'identifiant. Réessaie."))
        }
        return Credential(idToken: token, fullName: apple.fullName)
    }

    /// Erreur d'Apple (hors annulation) → message en français.
    static func authError(from error: any Error) -> AuthError {
        if let authError = error as? AuthError { return authError }
        if (error as? ASAuthorizationError)?.code == .notInteractive {
            return .failed(String(localized: "Connecte-toi à ton compte Apple dans Réglages, puis réessaie."))
        }
        return .failed(String(localized: "La connexion avec Apple n'a pas abouti. Réessaie dans un instant."))
    }
}
