// SolidarityLedger.swift
// Solidarité d'un groupe de quartier (E10 : RQ-078 à RQ-080, RQ-083).
// Swift pur, sans Firebase : panier suspendu, fonds de solidarité et application anonyme du fonds.
// Codes d'organisme (RQ-082) : voir `ReferralCode`.
//
// Définition : un « panier » = une part au prix unitaire de la commande (`unitPriceCents`).
// Anonymat : rien de ce qui est montré au groupe (fonds, historique, résumé) ne contient d'identifiant de ménage.

import Foundation

/// Fonds de solidarité d'un groupe (RQ-079). Le solde se déduit de l'historique.
nonisolated struct SolidarityFund: Sendable, Equatable, Codable {
    /// Ligne d'historique, sans aucun identifiant de ménage.
    struct Entry: Sendable, Equatable, Codable {
        enum Kind: String, Sendable, Equatable, Codable {
            /// Paniers suspendus ou dons versés dans le fonds.
            case contribution
            /// Argent du fonds qui a payé des parts de ménages subventionnés.
            case application
        }

        var kind: Kind
        /// Commande d'où vient ou où va l'argent ; nil pour un don hors commande.
        var orderId: String?
        /// Montant positif, en cents.
        var amountCents: Cents
        /// Paniers offerts par cette application (0 pour une contribution).
        var basketCount: Int
        var date: Date
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Solde : contributions moins applications.
    var balanceCents: Cents {
        entries.reduce(0) { $0 + ($1.kind == .contribution ? $1.amountCents : -$1.amountCents) }
    }

    /// Total versé dans le fonds depuis le début.
    var totalContributedCents: Cents {
        entries.filter { $0.kind == .contribution }.reduce(0) { $0 + $1.amountCents }
    }

    /// Paniers suspendus déjà offerts dans le quartier (compteur public, RQ-083).
    var basketsOffered: Int {
        entries.filter { $0.kind == .application }.reduce(0) { $0 + $1.basketCount }
    }

    /// Paniers entiers que le solde peut encore payer à ce prix unitaire.
    func basketsFundable(unitPriceCents: Cents) -> Int {
        SolidarityLedger.baskets(in: balanceCents, unitPriceCents: unitPriceCents)
    }

    /// Historique du plus récent au plus ancien.
    var history: [Entry] {
        entries.sorted { $0.date > $1.date }
    }
}

nonisolated enum SolidarityLedger {
    /// Plafond d'un panier suspendu sur une même part : 200 $.
    static let maxSuspendedAmountCents: Cents = 20_000

    /// Résumé visible du groupe après une application du fonds : des totaux, jamais qui a été aidé (RQ-080).
    struct GroupSummary: Sendable, Equatable {
        /// Paniers suspendus versés par les ménages de cette commande.
        var contributedCents: Cents
        /// Montant pris dans le fonds pour cette commande.
        var fundUsedCents: Cents
        var fundRemainingCents: Cents
        /// Paniers offerts : `fundUsedCents / unitPriceCents`, arrondi vers le bas.
        var basketsFunded: Int
    }

    /// Résultat de `apply`. `allocation` est privée (serveur, et chaque ménage ne lit que sa part) ;
    /// `summary` et `fund` peuvent être montrés au groupe.
    struct Application: Sendable, Equatable {
        var allocation: ShareAllocator.Allocation
        var fund: SolidarityFund
        var summary: GroupSummary
    }

    // MARK: RQ-078 panier suspendu

    /// Ajoute un panier suspendu (montant libre) à ma part. Le montant s'additionne à celui déjà donné.
    /// Lève `.orderClosed` si la commande est fermée, `.invalidInput` si le montant est nul, négatif ou trop grand.
    static func addingSuspendedBasket(_ amountCents: Cents, to share: Share, in order: GroupOrder) throws -> Share {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        guard amountCents > 0 else {
            throw AppError.invalidInput(String(localized: "Choisis un montant plus grand que 0 $."))
        }
        // Comparé sans additionner : un montant énorme ferait déborder l'addition (plantage, T-093).
        guard amountCents <= maxSuspendedAmountCents - share.suspendedAmountCents else {
            throw AppError.invalidInput(String(localized: "Tu peux offrir jusqu'à 200 $ de paniers suspendus par commande."))
        }
        var share = share
        share.suspendedAmountCents += amountCents
        return share
    }

    /// T-181 : fixe le panier suspendu de ma part à `amountCents` (0 = aucun) au moment de réserver, sans l'additionner.
    /// Même plafond que `addingSuspendedBasket`. Lève `.orderClosed` si la commande est fermée.
    static func settingSuspendedBasket(_ amountCents: Cents, on share: Share, in order: GroupOrder) throws -> Share {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        guard amountCents >= 0 else {
            throw AppError.invalidInput(String(localized: "Le montant ne peut pas être négatif."))
        }
        guard amountCents <= maxSuspendedAmountCents else {
            throw AppError.invalidInput(String(localized: "Tu peux offrir jusqu'à 200 $ de paniers suspendus par commande."))
        }
        var share = share
        share.suspendedAmountCents = amountCents
        return share
    }

    /// Retire le panier suspendu de ma part tant que la commande est ouverte.
    static func removingSuspendedBasket(from share: Share, in order: GroupOrder) throws -> Share {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        var share = share
        share.suspendedAmountCents = 0
        return share
    }

    // MARK: RQ-079 fonds

    /// Paniers entiers qu'un montant peut payer : une part au prix unitaire. 0 si le prix est nul.
    static func baskets(in amountCents: Cents, unitPriceCents: Cents) -> Int {
        guard unitPriceCents > 0, amountCents > 0 else { return 0 }
        return amountCents / unitPriceCents
    }

    /// Ajoute un don direct au fonds (hors commande).
    static func donating(_ amountCents: Cents, to fund: SolidarityFund, date: Date = .now) throws -> SolidarityFund {
        guard amountCents > 0 else {
            throw AppError.invalidInput(String(localized: "Choisis un montant plus grand que 0 $."))
        }
        var fund = fund
        fund.entries.append(.init(kind: .contribution, orderId: nil, amountCents: amountCents, basketCount: 0, date: date))
        return fund
    }

    // MARK: RQ-080 application anonyme

    /// À la clôture d'une commande confirmée : verse les paniers suspendus de la commande dans le fonds,
    /// puis paie les parts des ménages subventionnés avec `ShareAllocator.allocate`.
    /// - Parameter eligibleHouseholdIds: ménages subventionnés (`ReferralCode.eligibleHouseholdIds`), jamais montrés au groupe.
    static func apply(
        orderId: String,
        offer: Offer,
        shares: [Share],
        unitPriceCents: Cents,
        eligibleHouseholdIds: Set<String>,
        fund: SolidarityFund,
        date: Date = .now
    ) throws -> Application {
        guard fund.balanceCents >= 0 else {
            throw AppError.invalidInput(String(localized: "Le fonds de solidarité ne peut pas être négatif."))
        }
        let allocation = try ShareAllocator.allocate(
            orderId: orderId, offer: offer, shares: shares, unitPriceCents: unitPriceCents,
            eligibleHouseholdIds: eligibleHouseholdIds, solidarityFundCents: fund.balanceCents
        )
        let contributed = shares.filter { $0.quantity > 0 }.reduce(0) { $0 + $1.suspendedAmountCents }
        let basketsFunded = baskets(in: allocation.fundUsedCents, unitPriceCents: unitPriceCents)

        var fund = fund
        if contributed > 0 {
            fund.entries.append(.init(kind: .contribution, orderId: orderId, amountCents: contributed, basketCount: 0, date: date))
        }
        if allocation.fundUsedCents > 0 {
            fund.entries.append(.init(
                kind: .application, orderId: orderId, amountCents: allocation.fundUsedCents,
                basketCount: basketsFunded, date: date
            ))
        }
        return Application(
            allocation: allocation,
            fund: fund,
            summary: GroupSummary(
                contributedCents: contributed,
                fundUsedCents: allocation.fundUsedCents,
                fundRemainingCents: allocation.fundRemainingCents,
                basketsFunded: basketsFunded
            )
        )
    }

    // MARK: RQ-083 compteur public

    /// « 12 paniers suspendus offerts dans ton quartier ». En français, 0 et 1 restent au singulier.
    static func publicCounterText(basketsOffered: Int) -> String {
        let count = max(0, basketsOffered)
        let noun = count < 2 ? String(localized: "panier suspendu offert") : String(localized: "paniers suspendus offerts")
        return String(localized: "\(count) \(noun) dans ton quartier")
    }

    /// Sous-titre du fonds : « 42,50 $ dans le fonds, de quoi offrir 4 paniers ».
    @MainActor
    static func fundSummary(_ fund: SolidarityFund, unitPriceCents: Cents) -> String {
        let balance = Money.format(fund.balanceCents)
        let count = fund.basketsFundable(unitPriceCents: unitPriceCents)
        switch count {
        case 0: return String(localized: "\(balance) dans le fonds")
        case 1: return String(localized: "\(balance) dans le fonds, de quoi offrir 1 panier")
        default: return String(localized: "\(balance) dans le fonds, de quoi offrir \(count) paniers")
        }
    }
}
