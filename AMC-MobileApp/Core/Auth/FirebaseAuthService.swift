#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

/// Transporte un `AuthStateDidChangeListenerHandle` (non Sendable) dans une closure `@Sendable`.
/// Sûr : le handle n'est que passé à `removeStateDidChangeListener`, sur le MainActor.
private struct ListenerHandleBox: @unchecked Sendable {
    let handle: AuthStateDidChangeListenerHandle
    init(_ handle: AuthStateDidChangeListenerHandle) { self.handle = handle }
}

/// Google Sign-In → Firebase Authentication.
/// À créer APRÈS `FirebaseApp.configure()` (Auth.auth() n'est jamais appelé dans un initialiseur de propriété).
final class FirebaseAuthService: AuthService {
    private var listenerHandle: AuthStateDidChangeListenerHandle?

    var currentUser: AuthUser? {
        Auth.auth().currentUser.map(AuthUser.init(firebaseUser:))
    }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield(user.map(AuthUser.init(firebaseUser:)))
            }
            self.listenerHandle = handle
            // Le handle Firebase n'est pas Sendable : on le transporte dans une boîte pour le retirer à la fin du flux.
            let box = ListenerHandleBox(handle)
            continuation.onTermination = { _ in
                Task { @MainActor in Auth.auth().removeStateDidChangeListener(box.handle) }
            }
        }
    }

    func signInWithGoogle() async throws -> AuthUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingConfiguration
        }
        guard let presenter = Self.topViewController() else {
            throw AuthError.noPresentingScreen
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let googleResult: GIDSignInResult
        do {
            googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }

        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw AuthError.failed("Jeton Google manquant.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleResult.user.accessToken.tokenString
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            return AuthUser(firebaseUser: result.user)
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private extension AuthUser {
    init(firebaseUser user: User) {
        self.init(
            id: user.uid,
            displayName: user.displayName ?? "Utilisateur",
            email: user.email ?? "",
            photoURL: user.photoURL
        )
    }
}
#endif
