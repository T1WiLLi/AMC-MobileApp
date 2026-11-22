// GroupOrder.swift
// Collection `groupOrders` et sa sous-collection `groupOrders/{id}/shares`.

import Foundation

/// Commande groupée : un groupe de quartier qui s'engage sur un lot.
nonisolated struct GroupOrder: Identifiable, Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable, CaseIterable {
        case open
        case reached
        case closed
        case delivered
        case cancelled
    }

    var id: String
    var groupId: String
    var offerId: String
    var status: Status
    /// Index du palier courant dans `Offer.sortedTiers`, nil sous le premier palier.
    var currentTierIndex: Int?
    var committedShares: Int
    var committedHouseholds: Int
    var pickupPointId: String?
    var pickupSlots: [PickupSlot]
    /// Moment où un coordonnateur ou l'hôte a marqué la livraison comme arrivée au point (closed → delivered) ;
    /// nil avant, et pour les anciennes commandes livrées.
    var deliveredAt: Date? = nil
}

/// Document `groupOrders/{groupOrderId}/shares/{householdId}` : la part d'un ménage.
nonisolated struct Share: Identifiable, Codable, Sendable, Hashable {
    var householdId: String
    var quantity: Int
    /// Prix final figé à la clôture ; nil tant que la commande est ouverte.
    var finalPriceCents: Cents?
    var isPaid: Bool
    /// Montant ajouté pour un panier suspendu.
    var suspendedAmountCents: Cents
    /// Montant payé par le fonds de solidarité ; visible du seul ménage.
    var subsidyCents: Cents
    var qrCode: String?
    var isPickedUp: Bool
    /// Dernière modification de la part (réservation ou changement de quantité) ; nil dans les anciennes données.
    var updatedAt: Date? = nil
    /// Début du créneau de cueillette réservé par le ménage (RQ-064) ; nil = pas encore choisi.
    var pickupSlotStart: Date? = nil
    /// T-159 : membre du ménage (uid) qui a récupéré la part ; nil si inconnu ou pas encore récupérée.
    var pickedUpBy: String? = nil
    /// T-159 : moment de la remise.
    var pickedUpAt: Date? = nil
    /// Nom du ménage (« Famille Benali »), copié dans la part quand il réserve : l'hôte ne peut pas lire
    /// `households/{id}` (réservé aux membres). nil dans les anciennes parts.
    var householdName: String? = nil
    /// T-195 : le ménage a un statut subventionné (code d'organisme) au moment de réserver. Posé par le ménage, et
    /// vérifié par firestore.rules contre son profil privé ; la clôture s'en sert pour répartir le fonds de solidarité.
    var solidarityEligible: Bool? = nil

    var id: String { householdId }

    /// Prix unitaire figé à la clôture : `finalPriceCents` est le total de la part (quantité × prix unitaire).
    var finalUnitPriceCents: Cents? {
        guard let finalPriceCents, quantity > 0 else { return nil }
        return finalPriceCents / quantity
    }
}
