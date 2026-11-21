import Foundation

/// Utilisateur connecté, indépendant de Firebase (les vues et ViewModels ne voient que ce type).
struct AuthUser: Identifiable, Hashable, Sendable {
    let id: String            // uid Firebase Auth
    var displayName: String
    var email: String
    var photoURL: URL?
}

extension AuthUser {
    static let sample = AuthUser(
        id: "fake-uid-001",
        displayName: "Camille Tremblay",
        email: "camille.tremblay@example.com",
        photoURL: nil
    )
}
