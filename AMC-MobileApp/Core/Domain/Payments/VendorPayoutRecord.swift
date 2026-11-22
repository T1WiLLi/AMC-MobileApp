// VendorPayoutRecord.swift
// Récapitulatif du versement au vendeur, écrit à la clôture (T-195) dans `groupOrders/{id}/payouts/vendor`.
// Photographie `VendorPayout` (brut, commission, net, acompte, retenu) au moment de la clôture ; paiements simulés.

import Foundation

nonisolated struct VendorPayoutRecord: Identifiable, Codable, Sendable, Hashable {
    /// Toujours `FirestoreCollection.vendorPayoutDocumentId` : un seul versement par commande.
    var id: String
    var groupOrderId: String
    var vendorId: String
    /// `VendorPayout.Mode` : « deposit » (acompte de 50 %, vendeur vérifié) ou « atPickup » (tout à la cueillette).
    var mode: String
    /// Prix finaux des parts payées (la part du fonds de solidarité comprise).
    var grossCents: Cents
    /// Commission de l'app (6 %).
    var commissionCents: Cents
    var netCents: Cents
    /// Versé à la clôture (acompte), le reste suit à la cueillette.
    var releasedCents: Cents
    var heldCents: Cents
    /// Part du `grossCents` payée par le fonds de solidarité.
    var subsidyTotalCents: Cents
    /// Paniers suspendus des familles de la commande, comptés dans le fonds avant les subventions.
    var solidarityContributedCents: Cents
    var paidShareCount: Int
    var date: Date

    init(
        orderId: String, vendorId: String, payout: VendorPayout,
        subsidyTotalCents: Cents, solidarityContributedCents: Cents, paidShareCount: Int, date: Date
    ) {
        id = FirestoreCollection.vendorPayoutDocumentId
        groupOrderId = orderId
        self.vendorId = vendorId
        mode = payout.mode == .deposit ? "deposit" : "atPickup"
        grossCents = payout.grossCents
        commissionCents = payout.commissionCents
        netCents = payout.netCents
        releasedCents = payout.releasedCents
        heldCents = payout.heldCents
        self.subsidyTotalCents = subsidyTotalCents
        self.solidarityContributedCents = solidarityContributedCents
        self.paidShareCount = paidShareCount
        self.date = date
    }

    var isDeposit: Bool { mode == "deposit" }
}
