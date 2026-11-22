import Foundation

/// Utilisateur connecté, indépendant de Firebase (les vues et ViewModels ne voient que ce type).
struct AuthUser: Identifiable, Hashable, Sendable {
    let id: String            // uid Firebase Auth
    var displayName: String
    var email: String
    var photoURL: URL?
    /// Courriel confirmé par le lien reçu (toujours vrai avec Google).
    var isEmailVerified: Bool = true
    /// Compte créé avec un courriel et un mot de passe (fournisseur « password »).
    var usesPassword: Bool = false

    /// Connecté par courriel sans avoir encore touché le lien de vérification : l'app reste fermée.
    var needsEmailVerification: Bool { usesPassword && !isEmailVerified }
}

extension AuthUser {
    /// Connexion Google fake (`FakeAuthService`) : la même personne que le ménage de démo (`FakeData`, Amina Benali),
    /// pour que le choix du portail, l'Accueil et le Profil disent tous le même prénom.
    static let sample = AuthUser(
        id: FakeData.ID.amina,
        displayName: "Amina Benali",
        email: "amina.benali@example.com",
        photoURL: nil
    )

    /// Compte courriel tout juste créé, pas encore vérifié (previews, tests).
    static let unverifiedSample = AuthUser(
        id: "fake-uid-002",
        displayName: "Amina",
        email: "amina@example.com",
        photoURL: nil,
        isEmailVerified: false,
        usesPassword: true
    )
}
