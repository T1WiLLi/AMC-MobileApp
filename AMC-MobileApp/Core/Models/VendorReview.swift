// VendorReview.swift
// Avis d'une famille sur un producteur (T-157) : collection `vendorReviews/{vendorId}_{householdId}`.
// Un seul avis par ménage et par producteur (l'id du document le garantit), modifiable par le ménage auteur.
// Ventes passées d'un producteur (`VendorSale`) : projection des commandes groupées livrées, pour la page
// publique (dernière vente, lots livrés, familles servies) et l'éligibilité à noter.

import Foundation

nonisolated struct VendorReview: Identifiable, Codable, Sendable, Hashable {
    /// `VendorReview.documentId(vendorId:householdId:)`.
    var id: String
    var vendorId: String
    var householdId: String
    /// Prénom affiché (« Amina B. ») : jamais le nom complet ni le courriel.
    var authorName: String
    /// 1 à 5 étoiles.
    var rating: Int
    /// Commentaire facultatif (500 caractères au plus).
    var comment: String?
    /// Commande livrée qui rend le ménage éligible (vérifiée par firestore.rules).
    var groupOrderId: String
    var createdAt: Date
    var updatedAt: Date

    static func documentId(vendorId: String, householdId: String) -> String {
        "\(vendorId)_\(householdId)"
    }

    static let ratingRange = 1...5
    static let maxCommentLength = 500
    static let maxAuthorNameLength = 60
}

/// Une commande groupée livrée d'un producteur, prête à afficher.
nonisolated struct VendorSale: Identifiable, Sendable, Hashable {
    /// Id de la commande groupée.
    var id: String
    var vendorId: String
    var offerId: String
    var productName: String
    /// « sac de 10 kg ».
    var shareLabel: String
    /// Parts vendues.
    var shares: Int
    /// Ménages servis.
    var households: Int
    /// Date de la vente (date limite du lot).
    var date: Date
    /// Ménages acheteurs connus du lecteur (ses propres groupes seulement) : sert à l'éligibilité.
    var buyerHouseholdIds: Set<String> = []
}
