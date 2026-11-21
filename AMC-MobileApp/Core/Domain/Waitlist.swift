// Waitlist.swift
// Liste d'attente d'un lot complet (E06 : RQ-056).
// Swift pur, sans Firebase : la transaction Firestore et les dépôts fake l'appellent.
//
// Règles :
// - Un ménage s'inscrit quand les parts restantes ne suffisent pas à sa demande (lot complet : committed == totalShares).
// - Une seule entrée par ménage. L'ordre est celui des demandes (FIFO, `requestedAt` puis ordre d'arrivée).
// - Quand des parts se libèrent, on sert la tête de liste d'abord, sans jamais la sauter :
//   elle reçoit min(parts libres, parts demandées). Si c'est partiel, elle garde sa place en tête
//   avec le reste de sa demande, et on s'arrête (il n'y a plus de parts libres).
// - Les parts promues s'ajoutent à la part existante du ménage, ou créent une nouvelle part.
// - Commande fermée : aucune promotion.

import Foundation

nonisolated struct Waitlist: Codable, Sendable, Equatable {
    nonisolated struct Entry: Identifiable, Codable, Sendable, Hashable {
        var householdId: String
        /// Parts encore attendues.
        var quantity: Int
        var requestedAt: Date

        var id: String { householdId }
    }

    /// Un ménage qui vient de recevoir des parts (pour une notification locale).
    nonisolated struct Promotion: Sendable, Equatable {
        var householdId: String
        /// Parts reçues à cette promotion.
        var quantity: Int
        /// Vrai si le ménage reste sur la liste pour le reste de sa demande.
        var isPartial: Bool
    }

    nonisolated struct PromotionResult: Sendable, Equatable {
        /// Parts après promotion ; déjà validées par `TierEngine.recalculated`.
        var shares: [Share]
        /// Commande recalculée (quantité, ménages, palier, statut).
        var order: GroupOrder
        var waitlist: Waitlist
        var promoted: [Promotion]
    }

    /// Entrées dans l'ordre de service (FIFO).
    private(set) var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = Self.ordered(entries)
    }

    var isEmpty: Bool { entries.isEmpty }

    func contains(householdId: String) -> Bool {
        entries.contains { $0.householdId == householdId }
    }

    /// Rang (1 = prochain servi), nil si le ménage n'est pas sur la liste.
    func position(of householdId: String) -> Int? {
        entries.firstIndex { $0.householdId == householdId }.map { $0 + 1 }
    }

    /// Inscrit un ménage. Refusé si la commande est fermée, si la demande tient dans les parts restantes
    /// (réserver directement), ou si le ménage est déjà sur la liste.
    func joining(
        householdId: String, quantity: Int, at requestedAt: Date,
        order: GroupOrder, offer: Offer, shares: [Share]
    ) throws -> Waitlist {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        guard quantity > 0 else { throw AppError.invalidInput("Choisis au moins une part.") }
        guard quantity <= offer.totalShares else {
            throw AppError.invalidInput("Ce lot ne compte que \(offer.totalShares) parts.")
        }
        guard !contains(householdId: householdId) else {
            throw AppError.invalidInput("Ton ménage est déjà sur la liste d'attente.")
        }
        guard quantity > Self.freeShares(offer: offer, shares: shares) else {
            throw AppError.invalidInput("Il reste assez de parts : réserve-les directement.")
        }
        return Waitlist(entries: entries + [Entry(householdId: householdId, quantity: quantity, requestedAt: requestedAt)])
    }

    /// Retire l'entrée d'un ménage ; sans effet s'il n'est pas sur la liste.
    func cancelling(householdId: String) -> Waitlist {
        Waitlist(entries: entries.filter { $0.householdId != householdId })
    }

    /// Sert la liste avec les parts libres (après qu'un ménage a baissé ou annulé sa part).
    /// Commande fermée : rien ne change, `promoted` est vide.
    func promoting(order: GroupOrder, offer: Offer, shares: [Share], now: Date = .now) throws -> PromotionResult {
        guard TierEngine.isOpen(order) else {
            return PromotionResult(shares: shares, order: order, waitlist: self, promoted: [])
        }
        var free = Self.freeShares(offer: offer, shares: shares)
        var shares = shares
        var remaining = entries
        var promoted: [Promotion] = []

        while free > 0, var head = remaining.first {
            let granted = min(free, head.quantity)
            free -= granted
            head.quantity -= granted
            if let index = shares.firstIndex(where: { $0.householdId == head.householdId }) {
                shares[index].quantity += granted
                shares[index].updatedAt = now
            } else {
                shares.append(Share(
                    householdId: head.householdId, quantity: granted, finalPriceCents: nil, isPaid: false,
                    suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false, updatedAt: now
                ))
            }
            let isPartial = head.quantity > 0
            promoted.append(Promotion(householdId: head.householdId, quantity: granted, isPartial: isPartial))
            if isPartial {
                remaining[0] = head
            } else {
                remaining.removeFirst()
            }
        }

        let recalculated = try TierEngine.recalculated(order, offer: offer, shares: shares)
        return PromotionResult(shares: shares, order: recalculated, waitlist: Waitlist(entries: remaining), promoted: promoted)
    }

    /// Parts encore libres dans le lot.
    static func freeShares(offer: Offer, shares: [Share]) -> Int {
        max(0, offer.totalShares - shares.reduce(0) { $0 + $1.quantity })
    }

    /// Le lot est complet : toute nouvelle demande va sur la liste d'attente.
    static func isFull(offer: Offer, shares: [Share]) -> Bool {
        freeShares(offer: offer, shares: shares) == 0
    }

    private static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.enumerated()
            .sorted { ($0.element.requestedAt, $0.offset) < ($1.element.requestedAt, $1.offset) }
            .map(\.element)
    }
}
