// GroupRating.swift
// Note d'une famille sur un groupe de quartier (T-174, FB-20) : `groups/{groupId}/ratings/{householdId}`.
// Un seul avis par ménage et par groupe (l'id du document est le ménage), modifiable par le ménage auteur.
// Agrégats tenus sur le groupe (`NeighborhoodGroup.ratingSum` / `ratingCount`) dans la même transaction.

import Foundation

nonisolated struct GroupRating: Identifiable, Codable, Sendable, Hashable {
    /// = `householdId` (id du document).
    var id: String
    var groupId: String
    var householdId: String
    /// Prénom et initiale (« Amina B. ») : jamais le nom complet ni le courriel.
    var authorName: String
    /// 1 à 5 étoiles.
    var rating: Int
    /// Commentaire court facultatif (`maxCommentLength` caractères au plus).
    var comment: String?
    /// Ancien membre (plus dans le groupe) : commande du groupe où le ménage avait une part, vérifiée par
    /// firestore.rules. nil pour un membre actuel.
    var groupOrderId: String?
    var createdAt: Date
    var updatedAt: Date

    /// Commentaire court : une phrase ou deux, assez pour aider sans ouvrir la porte aux pavés.
    static let maxCommentLength = 280
}

/// Ce que le ménage lecteur peut faire avec la note d'un groupe.
nonisolated enum GroupRatingEligibility: Hashable, Sendable {
    /// Membre actuel du groupe.
    case member
    /// Ancien membre : il a eu une part dans cette commande du groupe.
    case formerMember(groupOrderId: String)
    /// A déjà noté : il peut modifier son avis.
    case alreadyRated
    /// Jamais membre : il ne peut pas noter.
    case notEligible

    var canRate: Bool { self != .notEligible }

    /// Preuve d'ancienne adhésion à écrire dans l'avis.
    var groupOrderId: String? {
        if case .formerMember(let id) = self { return id }
        return nil
    }
}
