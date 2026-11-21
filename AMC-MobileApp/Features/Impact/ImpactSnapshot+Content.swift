import Foundation

extension ImpactSnapshot {
    /// Aller-retour moyen en auto vers une grande surface, en km (estimation).
    static let groceryRoundTripKilometers = 3.4

    /// Convertit la sortie d'`ImpactViewModel` pour les composants de l'écran Impact.
    /// Le modèle n'a pas de série mensuelle : les économies du ménage deviennent le mois courant.
    /// Les indicateurs sans donnée directe (emballages, trajets) sont des estimations prudentes tirées des parts.
    init(content: ImpactViewModel.Content, firstName: String, neighborhoodName: String, now: Date = .now) {
        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let products = content.byProduct
        let paidCents = products.reduce(0) { total, item in
            total + max(0, item.product.referenceGroceryPriceCents * item.shares - item.savingsCents)
        }
        let freshKilograms = products
            .filter { [.produce, .legumes, .eggs].contains($0.product.category) }
            .reduce(0) { $0 + $1.kilograms }

        self.init(
            firstName: firstName,
            neighborhoodName: neighborhoodName,
            monthlySavings: [MonthlySaving(month: month, savedCents: content.mySavingsCents)],
            households: content.householdCount,
            hosts: 1,
            neighborhoodSavedCents: content.neighborhoodSavingsCents,
            suspendedBasketsOffered: content.suspendedBasketCount,
            householdsHelped: content.suspendedBasketCount,
            paidToProducersCents: paidCents,
            producers: Set(products.map(\.product.vendorId)).count,
            kilogramsBought: content.totalKilograms,
            // Une part en vrac remplace au moins un emballage individuel.
            packagingAvoided: content.totalShares,
            // Une livraison par produit au point de cueillette au lieu d'une par part.
            deliveryTripsAvoided: max(0, content.totalShares - products.count),
            // Chaque ménage remplace au moins un trajet vers l'épicerie par la cueillette à pied.
            groceryTripsAvoided: content.householdCount,
            groceryKilometersAvoided: Double(content.householdCount) * Self.groceryRoundTripKilometers,
            freshProduceShare: content.totalKilograms > 0 ? min(1, freshKilograms / content.totalKilograms) : 0
        )
    }
}
