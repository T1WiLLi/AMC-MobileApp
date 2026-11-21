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

    var id: String { householdId }
}
