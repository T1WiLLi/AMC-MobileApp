// OrganizationPayment.swift
// T-207 : paiement d'un organisme (don au fonds, paniers suspendus, parrainage mensuel), sur le même faux terminal
// que la clôture côté Famille (`PaymentSimulator`). Aucun argent ne bouge : la décision et le reçu sont calculés ici,
// le don lui-même reste le document `organizations/{id}/donations/{id}` déjà permis par les règles (T-194).
//
// Le reçu se déduit du don : numéro tiré de son id, date du don, moyen de paiement de la carte de l'organisme.
// Rien de nouveau n'est écrit dans Firestore, donc aucun changement de règles.

import Foundation

/// Pourquoi le faux terminal refuse un paiement d'organisme.
nonisolated enum OrganizationPaymentDecline: Sendable, Hashable {
    /// Montant au-dessus du plafond de la carte.
    case overCardLimit(limitCents: Cents)
    /// Refus de l'émetteur (même cas que `PaymentSimulator.Outcome.declined` côté Famille).
    case refusedByIssuer
}

/// Reçu d'un paiement d'organisme.
nonisolated struct OrganizationPaymentReceipt: Identifiable, Sendable, Hashable {
    enum Purpose: Sendable, Hashable {
        /// Don unique (fonds ou paniers suspendus).
        case donation(kind: OrganizationDonation.Kind, basketCount: Int, householdsReached: Int)
        /// Parrainage : montant prélevé chaque mois.
        case sponsorship(monthlyBasketGoal: Int)
    }

    /// Numéro lisible : « LG-20261122-4F9K2A ».
    var number: String
    var date: Date
    var amountCents: Cents
    /// « Apple Pay •••• 4242 ».
    var methodLabel: String
    var groupName: String
    var purpose: Purpose

    var id: String { number }

    var isRecurring: Bool {
        if case .sponsorship = purpose { return true }
        return false
    }

    /// Reçu d'un don enregistré (feuille Financer, historique du Tableau et de l'Impact).
    static func make(donation: OrganizationDonation, calendar: Calendar = .current) -> OrganizationPaymentReceipt {
        OrganizationPaymentReceipt(
            number: number(for: donation.id, date: donation.date, calendar: calendar),
            date: donation.date,
            amountCents: donation.amountCents,
            methodLabel: PaymentSimulator.organizationCardLabel,
            groupName: donation.groupName,
            purpose: .donation(kind: donation.kind, basketCount: donation.basketCount,
                               householdsReached: donation.householdsReached)
        )
    }

    /// Reçu d'engagement d'un parrainage, au moment où il est confirmé.
    static func make(
        sponsorship: Sponsorship,
        monthlyAmountCents: Cents,
        date: Date,
        calendar: Calendar = .current
    ) -> OrganizationPaymentReceipt {
        OrganizationPaymentReceipt(
            number: number(for: "\(sponsorship.organizationId)-\(sponsorship.groupId)-\(Int(date.timeIntervalSince1970))",
                           date: date, calendar: calendar),
            date: date,
            amountCents: monthlyAmountCents,
            methodLabel: PaymentSimulator.organizationCardLabel,
            groupName: sponsorship.groupName,
            purpose: .sponsorship(monthlyBasketGoal: sponsorship.monthlyBasketGoal)
        )
    }

    /// « LG-AAAAMMJJ-XXXXXX » : date du paiement et six caractères tirés de l'id (stable d'un affichage à l'autre).
    static func number(for id: String, date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "LG-\(day)-\(suffix(for: id))"
    }

    /// Six caractères [0-9A-Z] : la fin de l'id s'il en a assez, sinon un hachage FNV-1a de l'id (déterministe).
    private static func suffix(for id: String) -> String {
        let alphanumerics = id.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        // Les ids Firestore (20 caractères) et les UUID des faux dépôts donnent directement leur fin.
        if alphanumerics.count >= 12 { return String(alphanumerics.suffix(6)) }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var text = ""
        for _ in 0..<6 {
            text.append(digits[Int(hash % 36)])
            hash /= 36
        }
        return text
    }
}

nonisolated extension PaymentSimulator {
    /// Quatre derniers chiffres de la carte affichée (Famille et Organismes).
    static let cardLast4 = "4242"

    /// « Apple Pay •••• 4242 » : moyen de paiement des organismes, sur leurs reçus.
    static var organizationCardLabel: String { "\(methodLabel) •••• \(cardLast4)" }

    /// Plafond de la carte d'un organisme : au-delà, le terminal refuse le paiement (2 500 $).
    static let organizationCardLimitCents: Cents = 250_000

    /// Décision du faux terminal pour un paiement d'organisme : nil si accepté, sinon la raison du refus.
    /// Refuse au-dessus du plafond de la carte, et toujours quand `outcome` vaut `.declined` (comme à la clôture).
    func authorizeOrganizationCharge(amountCents: Cents) -> OrganizationPaymentDecline? {
        if amountCents > Self.organizationCardLimitCents {
            return .overCardLimit(limitCents: Self.organizationCardLimitCents)
        }
        return outcome == .declined ? .refusedByIssuer : nil
    }
}
