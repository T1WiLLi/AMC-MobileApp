import Foundation
import Observation

/// État de session : qui est connecté, connexion Google ou courriel, vérification du courriel, déconnexion.
/// Partagé dans l'environnement SwiftUI (`.environment(session)`).
@MainActor
@Observable
final class SessionViewModel {
    enum State: Equatable {
        case signedOut
        case signingIn
        /// Connecté par courriel, mais le lien de vérification n'a pas encore été touché : l'app reste fermée.
        case awaitingVerification(AuthUser)
        case signedIn(AuthUser)
    }

    /// Délai minimal entre deux envois du courriel de vérification (anti-spam).
    static let resendCooldown: TimeInterval = 60

    private(set) var state: State = .signedOut
    /// Message d'erreur affiché sur l'écran de connexion (nil = aucune erreur).
    var errorMessage: String?
    /// Erreur du formulaire courriel ; `field` dit sous quel champ l'afficher.
    private(set) var emailAuthError: AuthError?
    /// Message de l'écran de vérification (pas encore vérifié, courriel renvoyé, erreur).
    private(set) var verificationMessage: String?
    private(set) var isCheckingVerification = false
    private(set) var isSendingVerification = false
    /// Moment du dernier envoi du lien de vérification (base du délai de renvoi).
    private(set) var verificationSentAt: Date?


    /// Lu par « Mon compte » (suppression du compte, RQ-021).
    let auth: AuthService
    private let now: () -> Date

    init(auth: AuthService, now: @escaping () -> Date = Date.init) {
        self.auth = auth
        self.now = now
        if let user = auth.currentUser { state = Self.state(for: user) }
    }

    /// Utilisateur qui a accès à l'app (connecté et, pour un compte courriel, vérifié).
    var currentUser: AuthUser? {
        if case .signedIn(let user) = state { user } else { nil }
    }

    /// Compte courriel en attente de vérification, ou nil.
    var pendingVerificationUser: AuthUser? {
        if case .awaitingVerification(let user) = state { user } else { nil }
    }

    /// Méthode de connexion en cours : seul le bouton touché affiche un indicateur (FB-03).
    enum AuthMethod: Equatable, Sendable {
        case google
        case email
    }

    var isSigningIn: Bool { state == .signingIn }

    /// Méthode dont la connexion est en cours (nil = aucune). Les autres boutons restent désactivés, sans indicateur.
    private(set) var signingInMethod: AuthMethod?

    func isSigningIn(with method: AuthMethod) -> Bool {
        isSigningIn && signingInMethod == method
    }

    private static func state(for user: AuthUser) -> State {
        user.needsEmailVerification ? .awaitingVerification(user) : .signedIn(user)
    }

    /// Suit la session (connexion restaurée, expiration). À lancer dans `.task` sur la vue racine.
    func observeSession() async {
        for await user in auth.authStateChanges() {
            guard state != .signingIn else { continue }
            // Firebase ne signale pas la vérification : on ne revient pas en arrière après un `reloadUser()` réussi.
            if let user, case .signedIn(let current) = state, current.id == user.id { continue }
            state = user.map(Self.state(for:)) ?? .signedOut
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        guard state != .signingIn else { return }
        errorMessage = nil
        emailAuthError = nil
        signingInMethod = .google
        defer { signingInMethod = nil }
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

    // MARK: Courriel et mot de passe

    /// Connexion par courriel. Un compte pas encore vérifié mène à l'écran de vérification.
    func signIn(email: String, password: String) async {
        await runEmailAuth { [auth] in
            try await auth.signIn(email: email, password: password)
        }
    }

    /// Création du compte, puis envoi immédiat du lien de vérification.
    func signUp(email: String, password: String, displayName: String) async {
        await runEmailAuth { [auth] in
            try await auth.signUp(email: email, password: password, displayName: displayName)
        }
        if pendingVerificationUser != nil {
            await sendVerification()
        }
    }

    private func runEmailAuth(_ operation: () async throws -> AuthUser) async {
        guard state != .signingIn else { return }
        errorMessage = nil
        emailAuthError = nil
        verificationMessage = nil
        signingInMethod = .email
        defer { signingInMethod = nil }
        state = .signingIn
        do {
            state = Self.state(for: try await operation())
        } catch {
            state = .signedOut
            let authError = (error as? AuthError) ?? .failed(AppError(error).message)
            emailAuthError = authError
        }
    }

    /// Efface l'erreur du formulaire dès que la personne corrige le champ concerné.
    func clearEmailError(for field: AuthError.Field? = nil) {
        guard let emailAuthError else { return }
        if field == nil || emailAuthError.field == field || emailAuthError.field == .general {
            self.emailAuthError = nil
        }
    }

    /// Envoie le lien de réinitialisation. Renvoie l'erreur à afficher dans la feuille, ou nil si c'est parti.
    func sendPasswordReset(email: String) async -> AuthError? {
        guard EmailAuthValidation.isValidEmail(email) else { return .invalidEmail }
        do {
            try await auth.sendPasswordReset(email: email)
            return nil
        } catch {
            return (error as? AuthError) ?? .failed(AppError(error).message)
        }
    }

    // MARK: Vérification du courriel

    /// Secondes avant de pouvoir renvoyer le courriel (0 = possible tout de suite).
    func resendSecondsRemaining(at date: Date? = nil) -> Int {
        guard let verificationSentAt else { return 0 }
        let elapsed = (date ?? now()).timeIntervalSince(verificationSentAt)
        return max(0, Int((Self.resendCooldown - elapsed).rounded(.up)))
    }

    func canResendVerification(at date: Date? = nil) -> Bool {
        pendingVerificationUser != nil && !isSendingVerification && resendSecondsRemaining(at: date) == 0
    }

    /// « Renvoyer le courriel » : ignoré pendant le délai anti-spam.
    func resendVerificationEmail() async {
        guard canResendVerification() else { return }
        if await sendVerification() {
            verificationMessage = String(localized: "C’est reparti ! Regarde aussi dans tes courriels indésirables.")
        }
    }

    @discardableResult
    private func sendVerification() async -> Bool {
        isSendingVerification = true
        defer { isSendingVerification = false }
        do {
            try await auth.sendEmailVerification()
            verificationSentAt = now()
            return true
        } catch {
            verificationMessage = ((error as? AuthError) ?? .failed(AppError(error).message)).errorDescription
            return false
        }
    }

    /// « J'ai vérifié mon courriel » : relit le compte. `silent` (retour au premier plan) n'affiche rien si ce n'est pas fait.
    /// Renvoie vrai si le courriel est vérifié.
    @discardableResult
    func checkEmailVerification(silent: Bool = false) async -> Bool {
        guard pendingVerificationUser != nil, !isCheckingVerification else { return false }
        isCheckingVerification = true
        defer { isCheckingVerification = false }
        if !silent { verificationMessage = nil }
        do {
            let user = try await auth.reloadUser()
            if user.isEmailVerified {
                verificationMessage = nil
                state = .signedIn(user)
                return true
            }
            if !silent {
                verificationMessage = String(localized: "Pas encore vérifié. Touche le lien dans le courriel, puis reviens ici.")
            }
            state = .awaitingVerification(user)
        } catch AuthError.notSignedIn {
            state = .signedOut
        } catch {
            if !silent {
                verificationMessage = ((error as? AuthError) ?? .failed(AppError(error).message)).errorDescription
            }
        }
        return false
    }

    // MARK: Déconnexion

    func signOut() {
        do {
            try auth.signOut()
            state = .signedOut
            emailAuthError = nil
            verificationMessage = nil
            verificationSentAt = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
