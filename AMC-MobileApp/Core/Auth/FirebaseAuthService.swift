#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

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

    // MARK: Apple

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        do {
            let result = try await Auth.auth().signIn(with: credential)
            // Apple ne donne le nom qu'une fois : on le garde dans le profil Firebase s'il manque.
            if result.user.displayName?.isEmpty ?? true, let name = Self.displayName(from: fullName) {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
            return AuthUser(firebaseUser: Auth.auth().currentUser ?? result.user)
        } catch {
            if (error as NSError).domain == AuthErrorDomain,
               AuthErrorCode(rawValue: (error as NSError).code) == .operationNotAllowed {
                throw AuthError.failed("La connexion avec Apple n'est pas encore activée. Utilise Google ou ton courriel.")
            }
            throw Self.authError(from: error)
        }
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Courriel et mot de passe

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: Self.clean(email), password: password)
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                // Le prénom est un plus : un échec ici ne doit pas bloquer l'inscription.
                try? await change.commitChanges()
            }
            return AuthUser(firebaseUser: Auth.auth().currentUser ?? result.user)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: Self.clean(email), password: password)
            return AuthUser(firebaseUser: result.user)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        Auth.auth().useAppLanguage()
        do {
            try await user.sendEmailVerification()
        } catch {
            throw Self.authError(from: error)
        }
    }

    func reloadUser() async throws -> AuthUser {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        do {
            try await user.reload()
        } catch {
            throw Self.authError(from: error)
        }
        guard let refreshed = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        return AuthUser(firebaseUser: refreshed)
    }

    func sendPasswordReset(email: String) async throws {
        Auth.auth().useAppLanguage()
        do {
            try await Auth.auth().sendPasswordReset(withEmail: Self.clean(email))
        } catch {
            throw Self.authError(from: error)
        }
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Erreurs Firebase Auth → `AuthError` en français (messages pour l'utilisateur, pas pour les logs).
    static func authError(from error: any Error) -> AuthError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) else {
            if let urlError = error as? URLError, AppError(urlError) == .offline { return .network }
            return .failed("Oups, un problème est survenu. Réessaie dans un instant.")
        }
        switch code {
        case .invalidEmail: return .invalidEmail
        case .emailAlreadyInUse, .credentialAlreadyInUse: return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        case .wrongPassword, .invalidCredential, .userNotFound: return .wrongPassword
        case .tooManyRequests: return .tooManyRequests
        case .networkError: return .network
        case .userDisabled: return .failed("Ce compte a été désactivé. Écris-nous pour le réactiver.")
        case .operationNotAllowed: return .failed("La connexion par courriel n'est pas encore activée. Utilise Google pour l'instant.")
        case .userTokenExpired, .requiresRecentLogin, .invalidUserToken, .userMismatch: return .notSignedIn
        default: return .failed("Oups, un problème est survenu. Réessaie dans un instant.")
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

    // MARK: Suppression du compte (RQ-021)

    /// Au-delà, Firebase refuse `user.delete()` (`requiresRecentLogin`) : on le vérifie avant d'effacer les données.
    static let recentLoginWindow: TimeInterval = 5 * 60

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        // Connexion trop ancienne : on s'arrête avant de toucher aux données, sinon il resterait un compte vide.
        if let lastSignIn = user.metadata.lastSignInDate,
           Date().timeIntervalSince(lastSignIn) > Self.recentLoginWindow {
            throw AuthError.requiresRecentLogin
        }
        #if canImport(FirebaseFirestore)
        try await Self.deleteUserData(uid: user.uid)
        #endif
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain, AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
                throw AuthError.requiresRecentLogin
            }
            throw Self.authError(from: error)
        }
        GIDSignIn.sharedInstance.signOut()
    }

    #if canImport(FirebaseFirestore)
    /// Retire l'uid du ménage (le ménage ne se supprime pas : `delete: if false`), puis supprime `users/{uid}`.
    /// Dernier membre : le ménage garde son uid, les règles exigent au moins un membre.
    /// `nonisolated` : les instantanés Firestore (non Sendable) ne quittent pas cette fonction.
    nonisolated private static func deleteUserData(uid: String) async throws {
        let db = Firestore.firestore()
        let userRef = db.collection(FirestoreCollection.users).document(uid)
        do {
            let snapshot = try await userRef.getDocument()
            if let householdId = snapshot.data()?["householdId"] as? String, !householdId.isEmpty {
                let householdRef = db.collection(FirestoreCollection.households).document(householdId)
                // Ménage illisible ou disparu : rien à retirer.
                if let household = try? await householdRef.getDocument(),
                   let userIds = household.data()?["userIds"] as? [String],
                   userIds.contains(uid), userIds.count > 1 {
                    try await householdRef.updateData(["userIds": FieldValue.arrayRemove([uid])])
                }
            }
            if snapshot.exists { try await userRef.delete() }
        } catch {
            let appError = FirestoreGroupOrderRepository.appError(from: error)
            throw appError == .offline ? AuthError.network : AuthError.failed(appError.message)
        }
    }
    #endif

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
            photoURL: user.photoURL,
            isEmailVerified: user.isEmailVerified,
            usesPassword: user.providerData.contains { $0.providerID == EmailAuthProviderID }
        )
    }
}
#endif
