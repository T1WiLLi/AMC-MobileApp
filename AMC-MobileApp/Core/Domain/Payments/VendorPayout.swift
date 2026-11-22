// VendorPayout.swift
// Versement du pot au vendeur (E21), moins la commission de l'app.
// Vendeur non vérifié : l'argent d'une part est versé à la cueillette.
// Vendeur vérifié : un acompte de 50 % à la clôture, le reste à la cueillette.
// Swift pur ; paiements simulés.

import Foundation

nonisolated struct VendorPayout: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        /// Vendeur non vérifié : le net d'une part payée est versé quand elle est récupérée.
        case atPickup
        /// Vendeur vérifié : 50 % du net à la clôture, le reste à la cueillette.
        case deposit
    }

    /// Acompte d'un vendeur vérifié, en points de base du net (50 %).
    static let depositRateBasisPoints = 5_000

    var mode: Mode
    /// Prix finaux des parts payées : subventions comprises (payées par le fonds de solidarité),
    /// dons pour paniers suspendus exclus — comme `VendorRevenue`.
    var grossCents: Cents
    /// Commission de l'app, calculée part par part (chaque paiement est une transaction).
    var commissionCents: Cents
    /// `grossCents − commissionCents`.
    var netCents: Cents
    /// Déjà versé au vendeur.
    var releasedCents: Cents
    /// Encore retenu dans le pot ; `releasedCents + heldCents == netCents`.
    var heldCents: Cents

    static func mode(vendorIsVerified: Bool) -> Mode {
        vendorIsVerified ? .deposit : .atPickup
    }

    /// - Parameters:
    ///   - shares: parts réparties par `ShareAllocator.allocate` ; seules les parts payées comptent.
    ///   - vendorIsVerified: `Vendor.isVerified`.
    /// Une commande ouverte, atteinte ou annulée ne verse rien (tout à 0) : rien n'est payé avant la clôture,
    /// et une commande annulée est remboursée.
    init(order: GroupOrder, shares: [Share], vendorIsVerified: Bool, commission: Commission = .standard) {
        mode = Self.mode(vendorIsVerified: vendorIsVerified)
        grossCents = 0
        commissionCents = 0
        netCents = 0
        releasedCents = 0
        heldCents = 0
        guard VendorRevenue.counts(order) else { return }

        for share in shares where share.quantity > 0 && share.isPaid {
            let gross = PaymentPot.vendorGross(share)
            let fee = commission.fee(onCents: gross)
            let net = gross - fee
            let released: Cents
            if share.isPickedUp {
                released = net
            } else if mode == .deposit {
                // Acompte arrondi au cent inférieur : le cent restant suit à la cueillette.
                released = net * Self.depositRateBasisPoints / Commission.fullRate
            } else {
                released = 0
            }
            grossCents += gross
            commissionCents += fee
            netCents += net
            releasedCents += released
            heldCents += net - released
        }
    }
}
