import Foundation

/// Authentification de l'app. Implémentations : `FirebaseAuthService` (Google Sign-In) et `FakeAuthService` (previews, tests).
protocol AuthService: AnyObject {
    /// Utilisateur connecté au lancement (session restaurée), ou nil.
    var currentUser: AuthUser? { get }
    /// Flux des changements de session (connexion, déconnexion, expiration).
    func authStateChanges() -> AsyncStream<AuthUser?>
    /// Ouvre la feuille Google et connecte l'utilisateur à Firebase.
    func signInWithGoogle() async throws -> AuthUser
    func signOut() throws
}

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case missingConfiguration
    case noPresentingScreen
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .missingConfiguration: "Configuration Firebase introuvable (GoogleService-Info.plist)."
        case .noPresentingScreen: "Impossible d'afficher la connexion Google pour le moment."
        case .failed(let message): message
        }
    }
}

/// Faux service : connexion instantanée (avec latence simulée), erreur activable pour les previews.
final class FakeAuthService: AuthService {
    private(set) var currentUser: AuthUser?
    var nextError: AuthError?
    private var continuation: AsyncStream<AuthUser?>.Continuation?

    init(signedInUser: AuthUser? = nil, nextError: AuthError? = nil) {
        self.currentUser = signedInUser
        self.nextError = nextError
    }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self.currentUser)
        }
    }

    func signInWithGoogle() async throws -> AuthUser {
        try? await Task.sleep(for: .milliseconds(400))
        if let nextError { throw nextError }
        currentUser = .sample
        continuation?.yield(currentUser)
        return .sample
    }

    func signOut() throws {
        currentUser = nil
        continuation?.yield(nil)
    }
}
