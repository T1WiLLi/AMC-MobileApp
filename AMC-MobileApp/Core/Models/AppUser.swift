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
}
