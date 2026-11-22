// OrderArrival.swift
// « La livraison est arrivée » : un coordonnateur du groupe ou l'hôte du point marque la commande fermée
// comme arrivée (closed → delivered). Les familles ne peuvent venir chercher leur part qu'à partir de là
// (`PickupDesk.canPickUp`), et leur app les prévient (`GrenierNotification.Event.deliveryArrived`).

import Foundation

nonisolated enum OrderArrival {
    /// Où en est la remise d'une commande fermée.
    enum Stage: Sendable, Equatable {
        /// Fermée : la livraison n'est pas encore au point de cueillette.
        case enRoute
        /// Arrivée : les familles viennent chercher leur part.
        case handingOut
        /// Arrivée et toutes les parts sont remises.
        case finished
    }

    /// Étape d'une commande, nil si elle n'est pas (ou plus) à remettre (ouverte, annulée).
    static func stage(of status: GroupOrder.Status, allPickedUp: Bool) -> Stage? {
        switch status {
        case .closed: .enRoute
        case .delivered: allPickedUp ? .finished : .handingOut
        case .open, .reached, .cancelled: nil
        }
    }

    /// Seule une commande fermée peut être marquée comme arrivée.
    static func canMark(_ order: GroupOrder) -> Bool { order.status == .closed }

    /// Coordonnateur du groupe ou hôte du point de la commande (même vérification que firestore.rules).
    static func isAllowed(userId: String, coordinatorIds: [String], pointHostUserId: String?) -> Bool {
        guard !userId.isEmpty else { return false }
        return coordinatorIds.contains(userId) || pointHostUserId == userId
    }

    /// closed → delivered, avec le moment de l'arrivée. Lève `.invalidInput` pour tout autre statut.
    static func markArrived(_ order: GroupOrder, at date: Date) throws -> GroupOrder {
        var delivered = try DeliveryManifest.markDelivered(order)
        delivered.deliveredAt = date
        return delivered
    }
}

/// Nom d'un ménage tel que l'hôte le voit (la part porte `householdName`, voir `Share`).
nonisolated enum ShareHouseholdName {
    /// Longueur maximale acceptée par firestore.rules.
    static let maxLength = 80

    /// Nom nettoyé (espaces retirés, tronqué) ; nil s'il est vide.
    static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// Nom affiché : celui de la part, sinon un nom connu (lu ailleurs), sinon « Famille 041 ».
    static func display(householdId: String, householdName: String?, known: String? = nil) -> String {
        normalized(householdName) ?? normalized(known) ?? String(localized: "Famille \(shortId(householdId))")
    }

    /// Fin courte et lisible d'un id : « household-041 » → « 041 », « Xk3f9QpL2m » → « PL2M » (4 derniers caractères).
    static func shortId(_ householdId: String) -> String {
        if let last = householdId.split(separator: "-").last, last.count <= 6, last.count < householdId.count {
            return String(last).uppercased()
        }
        return String(householdId.suffix(4)).uppercased()
    }
}
