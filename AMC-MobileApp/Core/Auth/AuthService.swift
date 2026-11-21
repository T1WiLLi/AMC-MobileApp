import Foundation

/// Authentification de l'app. Implémentations : `FirebaseAuthService` (Google Sign-In, Apple, courriel et mot de passe)
/// et `FakeAuthService` (previews, tests).
protocol AuthService: AnyObject {
    /// Utilisateur connecté au lancement (session restaurée), ou nil.
    var currentUser: AuthUser? { get }
    /// Flux des changements de session (connexion, déconnexion, expiration).
    func authStateChanges() -> AsyncStream<AuthUser?>
    /// Ouvre la feuille Google et connecte l'utilisateur à Firebase.
    func signInWithGoogle() async throws -> AuthUser
    /// Connecte à Firebase le jeton reçu de « Se connecter avec Apple ». `rawNonce` = nonce brut dont le SHA-256
    /// est parti dans la requête Apple ; `fullName` n'arrive qu'à la première connexion.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser
    /// Crée un compte courriel et mot de passe (le prénom devient le nom affiché). Le courriel n'est pas encore vérifié.
    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser
    /// Connexion avec un compte courriel existant.
    func signIn(email: String, password: String) async throws -> AuthUser
    /// Envoie (ou renvoie) le lien de vérification à l’utilisateur connecté, dans la langue de l’appareil (français ou anglais).
    func sendEmailVerification() async throws
    /// Relit l'utilisateur sur le serveur, pour savoir s'il a touché le lien (`isEmailVerified`).
    func reloadUser() async throws -> AuthUser
    /// Envoie le lien de réinitialisation du mot de passe.
    func sendPasswordReset(email: String) async throws
    func signOut() throws
}

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case missingConfiguration
    case noPresentingScreen
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case wrongPassword
    case tooManyRequests
    case network
    case notSignedIn
    case failed(String)

    /// Champ du formulaire sous lequel afficher l'erreur.
    enum Field: Equatable, Sendable {
        case email, password, general
    }

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .missingConfiguration: "Configuration Firebase introuvable (GoogleService-Info.plist)."
        case .noPresentingScreen: "Impossible d'afficher la connexion Google pour le moment."
        case .invalidEmail: "Ce courriel n'a pas l'air valide. Vérifie-le."
        case .emailAlreadyInUse: "Un compte existe déjà avec ce courriel. Connecte-toi plutôt."
        case .weakPassword: "Ton mot de passe doit avoir au moins 6 caractères."
        case .wrongPassword: "Courriel ou mot de passe incorrect."
        case .tooManyRequests: "Trop de tentatives. Attends quelques minutes, puis réessaie."
        case .network: "Pas de connexion. Vérifie ton Internet, puis réessaie."
        case .notSignedIn: "Ta session a expiré. Connecte-toi de nouveau."
        case .failed(let message): message
        }
    }

    /// Champ sous lequel l'erreur s'affiche dans le formulaire courriel.
    var field: Field {
        switch self {
        case .invalidEmail, .emailAlreadyInUse: .email
        case .weakPassword, .wrongPassword: .password
        default: .general
        }
    }

    /// Même erreur dans le vocabulaire commun de l'app.
    var appError: AppError {
        switch self {
        case .network: .offline
        case .notSignedIn: .unauthenticated
        case .invalidEmail, .emailAlreadyInUse, .weakPassword, .wrongPassword:
            .invalidInput(errorDescription ?? "")
        case .tooManyRequests, .cancelled, .missingConfiguration, .noPresentingScreen, .failed:
            .unknown(errorDescription ?? "")
        }
    }
}

/// Faux service : connexion instantanée (avec latence simulée), erreur activable pour les previews.
/// Les comptes courriel vivent en mémoire ; `markEmailVerified()` simule le lien touché dans Mail.
final class FakeAuthService: AuthService {
    private(set) var currentUser: AuthUser?
    var nextError: AuthError?
    /// Latence simulée des appels courriel (`.zero` dans les tests).
    var latency: Duration
    private(set) var sentVerificationCount = 0
    private(set) var passwordResetEmails: [String] = []
    private var accounts: [String: (password: String, user: AuthUser)] = [:]
    private var continuation: AsyncStream<AuthUser?>.Continuation?

    init(signedInUser: AuthUser? = nil, nextError: AuthError? = nil, latency: Duration = .milliseconds(400)) {
        self.currentUser = signedInUser
        self.nextError = nextError
        self.latency = latency
        if let signedInUser, signedInUser.usesPassword {
            accounts[signedInUser.email.lowercased()] = ("motdepasse", signedInUser)
        }
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

    /// Dernier nonce brut reçu par `signInWithApple` (tests).
    private(set) var lastAppleNonce: String?

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        try await simulateCall()
        lastAppleNonce = rawNonce
        let name = fullName?.givenName ?? AuthUser.sample.displayName
        let user = AuthUser(
            id: "fake-apple-\(idToken.prefix(8))",
            displayName: name,
            email: "relais@privaterelay.appleid.com",
            photoURL: nil,
            isEmailVerified: true,
            usesPassword: false
        )
        setCurrentUser(user)
        return user
    }

    /// Ajoute un compte courriel existant (previews, tests).
    func addAccount(email: String, password: String, displayName: String = "Amina", verified: Bool = true) {
        let key = email.lowercased()
        let user = AuthUser(
            id: "fake-\(key)",
            displayName: displayName,
            email: key,
            photoURL: nil,
            isEmailVerified: verified,
            usesPassword: true
        )
        accounts[key] = (password, user)
    }

    /// Simule le lien de vérification touché dans Mail : visible au prochain `reloadUser()`.
    func markEmailVerified() {
        guard let user = currentUser else { return }
        var verified = user
        verified.isEmailVerified = true
        let key = user.email.lowercased()
        accounts[key] = (accounts[key]?.password ?? "motdepasse", verified)
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUser {
        try await simulateCall()
        let key = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard EmailAuthValidation.isValidEmail(key) else { throw AuthError.invalidEmail }
        guard accounts[key] == nil else { throw AuthError.emailAlreadyInUse }
        guard password.count >= EmailAuthValidation.minimumPasswordLength else { throw AuthError.weakPassword }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let user = AuthUser(
            id: "fake-\(key)",
            displayName: name.isEmpty ? "Utilisateur" : name,
            email: key,
            photoURL: nil,
            isEmailVerified: false,
            usesPassword: true
        )
        accounts[key] = (password, user)
        setCurrentUser(user)
        return user
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        try await simulateCall()
        let key = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard EmailAuthValidation.isValidEmail(key) else { throw AuthError.invalidEmail }
        guard let account = accounts[key], account.password == password else { throw AuthError.wrongPassword }
        setCurrentUser(account.user)
        return account.user
    }

    func sendEmailVerification() async throws {
        try await simulateCall()
        guard currentUser != nil else { throw AuthError.notSignedIn }
        sentVerificationCount += 1
    }

    func reloadUser() async throws -> AuthUser {
        try await simulateCall()
        guard let user = currentUser else { throw AuthError.notSignedIn }
        let refreshed = accounts[user.email.lowercased()]?.user ?? user
        currentUser = refreshed
        return refreshed
    }

    func sendPasswordReset(email: String) async throws {
        try await simulateCall()
        guard EmailAuthValidation.isValidEmail(email) else { throw AuthError.invalidEmail }
        passwordResetEmails.append(email)
    }

    func signOut() throws {
        setCurrentUser(nil)
    }

    /// Latence, puis l'erreur programmée (consommée : l'appel suivant réussit).
    private func simulateCall() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func setCurrentUser(_ user: AuthUser?) {
        currentUser = user
        continuation?.yield(user)
    }
}
