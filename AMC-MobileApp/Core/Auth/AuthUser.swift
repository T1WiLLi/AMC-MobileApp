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
    static let sample = AuthUser(
        id: "fake-uid-001",
        displayName: "Camille Tremblay",
        email: "camille.tremblay@example.com",
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
