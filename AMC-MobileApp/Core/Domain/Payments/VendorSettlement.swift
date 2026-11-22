// VendorSettlement.swift
// Ce que le vendeur a réellement encaissé sur ses commandes fermées (T-195), lu depuis les documents écrits à la
// clôture (`payments`, `payouts/vendor`) : encaissé, commission, net, acompte versé, reste dû. Swift pur.
// Le « revenu prévu » des commandes ouvertes reste calculé ailleurs (`VendorRevenueSummary`).

import Foundation

nonisolated struct VendorSettlement: Sendable, Equatable {
    /// Commandes fermées avec un versement enregistré.
    var closedOrderCount: Int
    /// Encaissé : prix finaux des parts payées, la part du fonds de solidarité comprise.
    var grossCents: Cents
    /// Dont payé par le fonds de solidarité (subventions).
    var solidarityCents: Cents
    /// Commission de l'app (6 %).
    var commissionCents: Cents
    var netCents: Cents
    /// Acompte déjà versé (vendeur vérifié) ou remise de la cueillette.
    var releasedCents: Cents
    /// Reste dû : versé à la cueillette.
    var heldCents: Cents
    /// Ce que les familles ont payé (prix final moins subvention), d'après les paiements enregistrés.
    var collectedFromFamiliesCents: Cents
    /// Parts engagées mais pas encore payées (paiement refusé) : encore à encaisser.
    var outstandingCents: Cents

    /// - Parameters:
    ///   - report: `VendorRevenue.report` sur les commandes fermées du vendeur.
    ///   - payouts: un récapitulatif de versement par commande fermée (`payouts/vendor`).
    init(report: VendorRevenue.Report, payouts: [VendorPayoutRecord]) {
        closedOrderCount = payouts.count
        grossCents = payouts.reduce(0) { $0 + $1.grossCents }
        solidarityCents = payouts.reduce(0) { $0 + $1.subsidyTotalCents }
        commissionCents = payouts.reduce(0) { $0 + $1.commissionCents }
        netCents = payouts.reduce(0) { $0 + $1.netCents }
        releasedCents = payouts.reduce(0) { $0 + $1.releasedCents }
        heldCents = payouts.reduce(0) { $0 + $1.heldCents }
        collectedFromFamiliesCents = report.total.collectedCents
        outstandingCents = max(0, report.total.outstandingCents)
    }

    /// Faux tant qu'aucune commande fermée n'a de versement enregistré (commandes d'avant T-195 comprises).
    var isEmpty: Bool { closedOrderCount == 0 }
}
