// AppUser.swift
// Collection `users`. Nommé AppUser pour ne pas entrer en conflit avec FirebaseAuth.User.

import Foundation

nonisolated struct AppUser: Identifiable, Codable, Sendable, Hashable {
    enum Role: String, Codable, Sendable, CaseIterable {
        case family
        case vendor
        case host
        case organization
    }

    enum Language: String, Codable, Sendable, CaseIterable {
        case french = "fr"
        case english = "en"
    }

    var id: String
    var displayName: String
    var photoURL: URL?
    var language: Language
    var roles: [Role]
    var neighborhood: String
    var dietaryPreferences: [DietaryTag]
    /// Mode aîné : texte plus grand, parcours simplifié.
    var seniorMode: Bool
    var householdId: String?
    var vendorId: String?
    /// Catégories de produits aimées, choisies à l'onboarding (T-156). Absent sur les anciens profils.
    var favoriteCategories: [Product.Category]? = nil
    /// Onboarding après l'inscription (T-156) : `false` pour un compte tout neuf, `true` une fois fini.
    /// Absent (`nil`) sur les profils d'avant T-156.
    var onboardingCompleted: Bool? = nil
    /// T-159 : ménage que la personne a demandé à rejoindre (`households/{id}/joinRequests/{uid}`), en attente
    /// du propriétaire. Une fois acceptée, `householdId` y pointe et ce champ redevient `nil`.
    var pendingHouseholdId: String? = nil
    /// T-194 : organisme auquel le compte est rattaché (portail Organismes). Posé par le seed ou l'Admin SDK seulement :
    /// les règles Firestore interdisent au client de l'écrire, de le changer ou de l'effacer.
    var organizationId: String? = nil

    /// Le compte n'a pas encore fini l'onboarding.
    /// Un profil sans drapeau (créé avant T-156 ou par un ancien build) le voit aussi tant qu'il n'a ni quartier
    /// ni catégories : c'est un compte qui n'a jamais rien choisi. Les profils du seed ont un quartier.
    var needsOnboarding: Bool {
        switch onboardingCompleted {
        case .some(let completed): !completed
        case .none: neighborhood.isEmpty && (favoriteCategories ?? []).isEmpty
        }
    }
}
