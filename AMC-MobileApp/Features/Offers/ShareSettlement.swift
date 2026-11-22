// ShareSettlement.swift
// E21-4 : ce qui est arrivé à la part du ménage à la clôture de la commande (paiement simulé au pot du groupe).
// Swift pur, partagé par la fiche du lot et ses tests.

import Foundation

nonisolated enum ShareSettlement: Sendable, Hashable {
    /// Part payée au pot : `paidCents` = prix final − subvention + don ; `savedCents` = économie vs l'épicerie
    /// (même définition que l'Accueil : (prix d'épicerie − prix unitaire final) × parts, jamais négative).
    case paid(paidCents: Cents, savedCents: Cents)
    /// Paiement simulé refusé : la part reste due (`dueCents`), la coordination recontacte le ménage.
    case declined(dueCents: Cents)
    /// Minimum non atteint : commande annulée, rien n'a été débité.
    case cancelled

    /// État de la part du ménage après la clôture ; nil tant que la commande est ouverte, sans part,
    /// ou si le prix final n'est pas encore lu.
    /// - Parameter groceryPricePerShareCents: prix en épicerie d'une part (`Product.referenceGroceryPriceCents`).
    static func make(order: GroupOrder?, share: Share?, groceryPricePerShareCents: Cents) -> ShareSettlement? {
        guard let order, let share, share.quantity > 0 else { return nil }
        switch order.status {
        case .open, .reached:
            return nil
        case .cancelled:
            return .cancelled
        case .closed, .delivered:
            guard let unitPrice = share.finalUnitPriceCents else { return nil }
            let due = PaymentPot.amountDue(share)
            guard share.isPaid else { return .declined(dueCents: due) }
            let saved = max(0, groceryPricePerShareCents - unitPrice) * share.quantity
            return .paid(paidCents: due, savedCents: saved)
        }
    }

    var isPaid: Bool {
        if case .paid = self { return true }
        return false
    }
}
