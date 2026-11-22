// Commission.swift
// Commission de l'app sur les ventes (E21) : un seul taux, 1 % par défaut (au plus 1 %, décision de zachary).
// Swift pur ; paiements simulés, aucun vrai prélèvement.

import Foundation

nonisolated struct Commission: Sendable, Equatable {
    /// 1 %, en points de base (1 point = 0,01 %).
    static let defaultRate = 100
    /// 100 % en points de base.
    static let fullRate = 10_000
    /// La commission de l'app, au taux par défaut.
    static let standard = Commission()

    /// Taux en points de base, borné entre 0 et 10 000.
    let rateBasisPoints: Int

    init(rateBasisPoints: Int = Commission.defaultRate) {
        self.rateBasisPoints = min(max(rateBasisPoints, 0), Self.fullRate)
    }

    /// Commission prise sur `amount` cents, arrondie au cent le plus proche
    /// (une demie se range vers le haut : 1 % de 50 ¢ = 0,5 ¢ → 1 ¢).
    /// Jamais négative (montant ≤ 0 → 0) et jamais plus que le montant.
    func fee(onCents amount: Cents) -> Cents {
        guard amount > 0 else { return 0 }
        let fee = (amount * rateBasisPoints + Self.fullRate / 2) / Self.fullRate
        return min(fee, amount)
    }

    /// Ce qui reste après la commission : `amount − fee(onCents: amount)`, jamais négatif.
    func net(onCents amount: Cents) -> Cents {
        guard amount > 0 else { return 0 }
        return amount - fee(onCents: amount)
    }
}
