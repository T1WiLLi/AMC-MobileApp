// OrderPhase.swift
// T-196 : phase d'un lot vue d'une carte (`OfferCard`, carte vendeur) : ouvert, fermé en préparation, livré ou annulé.
// Logique pure et testable ; la carte n'a qu'à afficher `title`, `symbol` et `tint`.

import SwiftUI

nonisolated enum OrderPhase: Sendable, Equatable {
    /// Commande ouverte (ou pas encore lancée) : on affiche l'échéance.
    case open
    /// Commande fermée, prix figé : le vendeur prépare les parts.
    case closed
    /// Commande livrée.
    case delivered
    /// Commande annulée (minimum non atteint) ou lot retiré.
    case cancelled

    /// Phase d'un lot pour une commande de groupe.
    /// - Parameters:
    ///   - offer: statut du lot (un lot clos ou retiré ne se présente plus comme ouvert).
    ///   - order: statut de la commande du groupe, nil si le groupe n'en a pas lancé.
    ///   - isClosed: la commande est déjà connue comme fermée par l'appelant (compatibilité `OfferCard.isClosed`).
    static func of(offer: Offer.Status, order: GroupOrder.Status?, isClosed: Bool = false) -> OrderPhase {
        switch order {
        case .delivered: return .delivered
        case .cancelled: return .cancelled
        case .closed: return .closed
        case .open, .reached, nil:
            if isClosed { return .closed }
            switch offer {
            case .closed: return .closed
            case .cancelled: return .cancelled
            case .active, .draft: return .open
            }
        }
    }

    /// Phase d'un lot du vendeur, agrégée sur toutes ses commandes de groupe.
    /// Ouverte tant qu'une commande est ouverte ; sinon livrée si toutes le sont, sinon fermée.
    static func aggregate(offer: Offer.Status, orders: [GroupOrder.Status]) -> OrderPhase {
        if orders.contains(where: { $0 == .open || $0 == .reached }) { return .open }
        let settled = orders.filter { $0 != .cancelled }
        if !settled.isEmpty {
            return settled.allSatisfy { $0 == .delivered } ? .delivered : .closed
        }
        return of(offer: offer, order: orders.isEmpty ? nil : .cancelled)
    }

    /// Texte court du statut ; nil pour une commande ouverte (la carte montre alors l'échéance).
    var title: String? {
        switch self {
        case .open: nil
        case .closed: String(localized: "Fermée, en préparation")
        case .delivered: String(localized: "Livrée")
        case .cancelled: String(localized: "Annulée")
        }
    }

    var symbol: String {
        switch self {
        case .open: "clock.fill"
        case .closed: "lock.fill"
        case .delivered: "checkmark.seal.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .open: .texteSecondaire
        case .closed: .grenier
        case .delivered: .economie
        case .cancelled: .red
        }
    }

    /// Lecture VoiceOver du statut, nil si ouverte.
    var spokenText: String? {
        switch self {
        case .open: nil
        case .closed: String(localized: "Commande fermée, en préparation")
        case .delivered: String(localized: "Commande livrée")
        case .cancelled: String(localized: "Commande annulée")
        }
    }

    /// Ligne sous la barre de progression d'une carte non ouverte.
    var detail: String? {
        switch self {
        case .open: nil
        case .closed, .delivered: String(localized: "Commande fermée · prix final figé")
        case .cancelled: String(localized: "Minimum non atteint · aucune famille débitée")
        }
    }

    var detailSymbol: String {
        switch self {
        case .cancelled: "xmark.circle"
        case .open, .closed, .delivered: "lock.fill"
        }
    }
}
