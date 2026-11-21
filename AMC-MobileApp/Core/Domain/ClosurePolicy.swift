// ClosurePolicy.swift
// Qui ferme une commande groupée, et quand (E06 : RQ-053).
// Swift pur, sans Firebase : s'appuie sur TierEngine pour l'issue (confirmée au palier atteint ou annulée).

import Foundation

nonisolated enum ClosurePolicy {
    /// Résultat de la clôture automatique tentée par un appareil.
    enum AutomaticClosure: Sendable, Equatable {
        /// La date limite n'est pas passée : rien à faire.
        case notDue
        /// La commande était déjà fermée (par un autre appareil, la coordination ou le vendeur) : rien à faire.
        case alreadyClosed(GroupOrder)
        /// Cet appareil vient de fermer la commande ; à écrire dans la transaction Firestore.
        case closed(GroupOrder, TierEngine.ClosureOutcome)
    }

    /// Message montré à qui n'a pas le droit de fermer la commande.
    static let notAllowedMessage = "Seuls la coordination du groupe et le vendeur du lot peuvent fermer cette commande."

    // MARK: RQ-053 (a) clôture automatique

    /// Vrai si cet appareil doit tenter la clôture maintenant : date limite passée et commande encore ouverte.
    /// « Le premier appareil qui ouvre la commande après la date limite la ferme. »
    static func shouldAttemptAutomaticClosure(order: GroupOrder, offer: Offer, now: Date = .now) -> Bool {
        TierEngine.shouldClose(order, offer: offer, now: now)
    }

    /// Clôture automatique, idempotente : une commande déjà fermée donne `.alreadyClosed`, jamais une erreur.
    static func automaticClosure(order: GroupOrder, offer: Offer, now: Date = .now) -> AutomaticClosure {
        guard TierEngine.isOpen(order) else { return .alreadyClosed(order) }
        guard shouldAttemptAutomaticClosure(order: order, offer: offer, now: now),
              let result = try? TierEngine.closed(order, offer: offer) else { return .notDue }
        return .closed(result.order, result.outcome)
    }

    // MARK: RQ-053 (b) bouton « Fermer »

    /// Le bouton « Fermer » est visible : la commande est ouverte et l'utilisateur est
    /// coordonnateur du groupe (via `membership`, le membre de son ménage dans le groupe de la commande)
    /// ou le vendeur du lot.
    /// - Parameter membership: document `groups/{order.groupId}/members/{user.householdId}`, nil si pas membre.
    static func canClose(user: AppUser, membership: GroupMember?, offer: Offer, order: GroupOrder) -> Bool {
        TierEngine.isOpen(order) && order.offerId == offer.id && isAllowed(user: user, membership: membership, offer: offer)
    }

    /// Fermeture manuelle, avant ou après la date limite. Mêmes règles d'issue que la clôture automatique :
    /// confirmée au palier atteint, annulée sous le minimum.
    /// - Throws: `.orderClosed` si la commande est déjà fermée, `.invalidInput` si le lot ne correspond pas,
    ///   `.invalidInput(notAllowedMessage)` si l'utilisateur n'est ni coordonnateur ni vendeur.
    static func close(
        user: AppUser, membership: GroupMember?, offer: Offer, order: GroupOrder
    ) throws -> (GroupOrder, TierEngine.ClosureOutcome) {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        guard order.offerId == offer.id else {
            throw AppError.invalidInput("Ce lot ne correspond pas à cette commande.")
        }
        guard isAllowed(user: user, membership: membership, offer: offer) else {
            throw AppError.invalidInput(notAllowedMessage)
        }
        let result = try TierEngine.closed(order, offer: offer)
        return (result.order, result.outcome)
    }

    private static func isAllowed(user: AppUser, membership: GroupMember?, offer: Offer) -> Bool {
        if let vendorId = user.vendorId, vendorId == offer.vendorId { return true }
        guard let membership, membership.role == .coordinator,
              let householdId = user.householdId else { return false }
        return membership.householdId == householdId
    }
}
