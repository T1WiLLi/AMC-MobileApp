// Receipt.swift
// Reçu d'une part (E07 : RQ-059) : quantité, prix, économie par rapport à l'épicerie,
// subvention, don solidaire et total, plus un rendu texte en français.

import Foundation

nonisolated struct Receipt: Sendable, Equatable {
    var householdId: String
    var groupOrderId: String
    var productName: String
    /// Ce que contient une part : « 10 kg »…
    var shareUnit: String
    var quantity: Int
    var unitPriceCents: Cents
    var finalPriceCents: Cents
    /// Prix d'épicerie de référence pour la même quantité.
    var referencePriceCents: Cents
    /// Économie par rapport à l'épicerie (jamais négative).
    var savingsCents: Cents
    var subsidyCents: Cents
    var donationCents: Cents
    /// Prix final − subvention + don.
    var totalCents: Cents
    /// Paiement réussi associé, nil si la part n'est pas encore payée.
    var payment: PaymentRecord?

    var isPaid: Bool { payment?.status == .succeeded }

    /// - Parameters:
    ///   - share: part répartie par `ShareAllocator.allocate` (prix final fixé).
    ///   - referencePricePerShareCents: prix en épicerie d'une part (même contenu que `offer.shareUnit`).
    ///   - payment: paiement de cette part, s'il y en a un.
    static func make(
        share: Share,
        order: GroupOrder,
        offer: Offer,
        productName: String,
        referencePricePerShareCents: Cents,
        payment: PaymentRecord? = nil
    ) throws -> Receipt {
        guard share.quantity > 0 else {
            throw AppError.invalidInput(String(localized: "Cette part est vide."))
        }
        guard referencePricePerShareCents >= 0 else {
            throw AppError.invalidInput(String(localized: "Montants négatifs."))
        }
        let total = try PaymentSimulator.amountDue(for: share)
        let finalPrice = share.finalPriceCents ?? 0
        let reference = referencePricePerShareCents * share.quantity
        let matchingPayment = payment.flatMap {
            $0.householdId == share.householdId && $0.groupOrderId == order.id && $0.status == .succeeded ? $0 : nil
        }
        return Receipt(
            householdId: share.householdId,
            groupOrderId: order.id,
            productName: productName,
            shareUnit: offer.shareUnit,
            quantity: share.quantity,
            unitPriceCents: finalPrice / share.quantity,
            finalPriceCents: finalPrice,
            referencePriceCents: reference,
            savingsCents: max(0, reference - finalPrice),
            subsidyCents: share.subsidyCents,
            donationCents: share.suspendedAmountCents,
            totalCents: total,
            payment: matchingPayment
        )
    }
}

extension Receipt {
    /// Rendu texte du reçu, en français (tutoiement). `Money` est isolé au MainActor.
    @MainActor
    func plainText() -> String {
        var lines = [
            String(localized: "Reçu LeGrenier"),
            "\(productName) : \(quantity) × \(shareUnit)",
            String(localized: "Prix par part : \(Money.format(unitPriceCents))"),
            String(localized: "Prix final : \(Money.format(finalPriceCents))"),
            String(localized: "Prix en épicerie : \(Money.format(referencePriceCents))"),
        ]
        if savingsCents > 0 {
            let percent = Money.savingsPercent(price: finalPriceCents, reference: referencePriceCents)
            lines.append(String(localized: "Tu économises \(Money.format(savingsCents)) (\(percent) %)"))
        }
        if subsidyCents > 0 {
            lines.append(String(localized: "Payé par le fonds de solidarité : −\(Money.format(subsidyCents))"))
        }
        if donationCents > 0 {
            lines.append(String(localized: "Ton don pour un panier suspendu : +\(Money.format(donationCents))"))
        }
        if let payment, isPaid {
            lines.append(String(localized: "Total payé : \(Money.format(totalCents))"))
            let date = payment.date.formatted(
                .dateTime.day().month(.wide).year().locale(AppLanguage.formattingLocale)
            )
            lines.append(String(localized: "Payé avec \(payment.methodLabel) le \(date)"))
        } else {
            lines.append(String(localized: "Total à payer : \(Money.format(totalCents))"))
        }
        if donationCents > 0 {
            lines.append(String(localized: "Merci pour ton geste solidaire !"))
        }
        lines.append(String(localized: "Merci d'acheter avec ton quartier !"))
        return lines.joined(separator: "\n")
    }
}
