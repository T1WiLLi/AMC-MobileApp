import Foundation
import Observation

/// État de session : qui est connecté, connexion Google, déconnexion.
/// Partagé dans l'environnement SwiftUI (`.environment(session)`).
@MainActor
@Observable
final class SessionViewModel {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(AuthUser)
    }

    private(set) var state: State = .signedOut
    /// Message d'erreur affiché sur l'écran de connexion (nil = aucune erreur).
    var errorMessage: String?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
        if let user = auth.currentUser { state = .signedIn(user) }
    }

    var currentUser: AuthUser? {
        if case .signedIn(let user) = state { user } else { nil }
    }

    /// Suit la session (connexion restaurée, expiration). À lancer dans `.task` sur la vue racine.
    func observeSession() async {
        for await user in auth.authStateChanges() {
            guard state != .signingIn else { continue }
            state = user.map(State.signedIn) ?? .signedOut
        }
    }

    func signInWithGoogle() async {
        guard state != .signingIn else { return }
        errorMessage = nil
        state = .signingIn
        do {
            state = .signedIn(try await auth.signInWithGoogle())
        } catch AuthError.cancelled {
            state = .signedOut
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try auth.signOut()
            state = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
