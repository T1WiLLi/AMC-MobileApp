// PaymentSimulator.swift
// Paiement simulé « style Apple Pay » à la clôture (E07 : RQ-058) et remboursement simulé
// quand une commande est annulée (RQ-061). Aucun vrai paiement : tout reste en mémoire.

import Foundation

/// Trace d'une tentative de paiement d'une part.
nonisolated struct PaymentRecord: Identifiable, Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable, CaseIterable {
        case succeeded
        case declined
    }

    var id: String
    var householdId: String
    var groupOrderId: String
    /// Prix final de la part (avant subvention).
    var finalPriceCents: Cents
    /// Part payée par le fonds de solidarité.
    var subsidyCents: Cents
    /// Don ajouté pour un panier suspendu.
    var donationCents: Cents
    /// Ce que le ménage paie : prix final − subvention + don.
    var amountDueCents: Cents
    var status: Status
    var date: Date
    var methodLabel: String
}

/// Remboursement simulé d'un paiement réussi.
nonisolated struct RefundRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var paymentId: String
    var householdId: String
    var groupOrderId: String
    var amountCents: Cents
    var date: Date
    var methodLabel: String
}

nonisolated struct PaymentSimulator: Sendable {
    /// Résultat imposé au faux terminal de paiement.
    enum Outcome: Sendable, Equatable {
        case success
        case declined
    }

    static let methodLabel = String(localized: "Apple Pay")

    var outcome: Outcome
    var now: @Sendable () -> Date

    init(outcome: Outcome = .success, now: @escaping @Sendable () -> Date = { Date() }) {
        self.outcome = outcome
        self.now = now
    }

    /// Ce que le ménage doit payer pour une part répartie par `ShareAllocator.allocate`.
    static func amountDue(for share: Share) throws -> Cents {
        guard let finalPrice = share.finalPriceCents else {
            throw AppError.invalidInput(String(localized: "Le prix de cette part n'est pas encore fixé."))
        }
        guard finalPrice >= 0, share.subsidyCents >= 0, share.suspendedAmountCents >= 0,
              share.subsidyCents <= finalPrice else {
            throw AppError.invalidInput(String(localized: "Montants invalides pour cette part."))
        }
        return finalPrice - share.subsidyCents + share.suspendedAmountCents
    }

    /// Paie une part d'une commande fermée.
    /// - Parameter existing: paiements déjà enregistrés (sert à refuser un second paiement et à numéroter les tentatives).
    /// - Returns: un reçu de transaction réussi ou refusé, selon `outcome`.
    func pay(share: Share, order: GroupOrder, existing: [PaymentRecord] = []) throws -> PaymentRecord {
        guard order.status == .closed || order.status == .delivered else {
            throw AppError.invalidInput(String(localized: "La commande n'est pas encore fermée : rien à payer pour l'instant."))
        }
        let previous = existing.filter { $0.groupOrderId == order.id && $0.householdId == share.householdId }
        guard !share.isPaid, !previous.contains(where: { $0.status == .succeeded }) else {
            throw AppError.invalidInput(String(localized: "Cette part est déjà payée."))
        }
        let amount = try Self.amountDue(for: share)
        return PaymentRecord(
            id: "PAY-\(order.id)-\(share.householdId)-\(previous.count + 1)",
            householdId: share.householdId,
            groupOrderId: order.id,
            finalPriceCents: share.finalPriceCents ?? 0,
            subsidyCents: share.subsidyCents,
            donationCents: share.suspendedAmountCents,
            amountDueCents: amount,
            status: outcome == .success ? .succeeded : .declined,
            date: now(),
            methodLabel: Self.methodLabel
        )
    }

    /// Paie toutes les parts non payées d'une commande fermée, dans l'ordre des ménages.
    func payAll(shares: [Share], order: GroupOrder, existing: [PaymentRecord] = []) throws -> [PaymentRecord] {
        var records = existing
        var created: [PaymentRecord] = []
        for share in shares.sorted(by: { $0.householdId < $1.householdId }) where !share.isPaid {
            let alreadyPaid = records.contains {
                $0.groupOrderId == order.id && $0.householdId == share.householdId && $0.status == .succeeded
            }
            guard !alreadyPaid else { continue }
            let record = try pay(share: share, order: order, existing: records)
            records.append(record)
            created.append(record)
        }
        return created
    }

    /// La part marquée payée si le paiement a réussi, inchangée sinon.
    static func applying(_ record: PaymentRecord, to share: Share) -> Share {
        guard record.status == .succeeded, record.householdId == share.householdId else { return share }
        var share = share
        share.isPaid = true
        return share
    }

    /// Remboursements d'une commande annulée : un par paiement réussi, rien pour les parts non payées.
    /// - Parameter existingRefunds: remboursements déjà émis (jamais deux fois le même paiement).
    func refunds(
        for order: GroupOrder,
        payments: [PaymentRecord],
        existingRefunds: [RefundRecord] = []
    ) throws -> [RefundRecord] {
        guard order.status == .cancelled else {
            throw AppError.invalidInput(String(localized: "Seule une commande annulée peut être remboursée."))
        }
        let refunded = Set(existingRefunds.map(\.paymentId))
        let date = now()
        return payments
            .filter { $0.groupOrderId == order.id && $0.status == .succeeded && !refunded.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { payment in
                RefundRecord(
                    id: "RF-\(payment.id)",
                    paymentId: payment.id,
                    householdId: payment.householdId,
                    groupOrderId: order.id,
                    amountCents: payment.amountDueCents,
                    date: date,
                    methodLabel: Self.methodLabel
                )
            }
    }
}
