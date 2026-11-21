// FakeData+VendorReviews.swift
// Avis et ventes passées de démo pour la page producteur (T-157).
// Amina (Famille Benali) a reçu des lots de la Ferme Bio-Rive (pas encore notée : elle peut laisser un avis)
// et du Fournil (déjà noté : elle peut modifier son avis). Elle n'a jamais acheté aux Moulins du Nord.

import Foundation

nonisolated extension FakeData {
    private static let reviewDay: TimeInterval = 86_400

    /// Ventes livrées des producteurs de démo.
    static let demoVendorSales: [VendorSale] = {
        let now = Date.now
        func sale(_ id: String, _ vendorId: String, _ product: String, _ label: String, shares: Int, households: Int,
                  daysAgo: Double, buyers: Set<String> = []) -> VendorSale {
            VendorSale(id: id, vendorId: vendorId, offerId: "offer-\(id)", productName: product, shareLabel: label,
                       shares: shares, households: households, date: now.addingTimeInterval(-daysAgo * reviewDay),
                       buyerHouseholdIds: buyers)
        }
        return [
            sale("order-past-rive-carottes", ID.fermeRive, "Carottes nantaises", "sac de 5 kg",
                 shares: 34, households: 21, daysAgo: 9, buyers: [ID.aminaHousehold, "household-tremblay"]),
            sale("order-past-rive-courges", ID.fermeRive, "Courges musquées", "caisse de 8 kg",
                 shares: 22, households: 17, daysAgo: 23),
            sale("order-past-rive-pdt", ID.fermeRive, "Pommes de terre jaunes", "sac de 10 kg",
                 shares: 41, households: 29, daysAgo: 38, buyers: [ID.aminaHousehold]),
            sale("order-past-rive-oignons", ID.fermeRive, "Oignons jaunes", "sac de 5 kg",
                 shares: 18, households: 14, daysAgo: 61),
            sale("order-past-moulins-riz", ID.moulinsDuNord, "Riz basmati", "sac de 10 kg",
                 shares: 52, households: 38, daysAgo: 12),
            sale("order-past-moulins-lentilles", ID.moulinsDuNord, "Lentilles vertes", "sac de 5 kg",
                 shares: 27, households: 20, daysAgo: 33),
            sale("order-past-fournil-levain", ID.fournil, "Pains au levain", "panier de 4 pains",
                 shares: 30, households: 24, daysAgo: 5, buyers: [ID.aminaHousehold]),
        ]
    }()

    /// Avis de démo, en français, de familles des quartiers desservis.
    static let demoVendorReviews: [VendorReview] = {
        let now = Date.now
        func review(_ vendorId: String, _ householdId: String, _ author: String, _ rating: Int, _ comment: String?,
                    order: String, daysAgo: Double) -> VendorReview {
            let date = now.addingTimeInterval(-daysAgo * reviewDay)
            return VendorReview(id: VendorReview.documentId(vendorId: vendorId, householdId: householdId),
                                vendorId: vendorId, householdId: householdId, authorName: author, rating: rating,
                                comment: comment, groupOrderId: order, createdAt: date, updatedAt: date)
        }
        return [
            review(ID.fermeRive, "household-tremblay", "Julie T.", 5,
                   "Carottes sucrées, encore pleines de terre. Mes enfants les mangent crues !",
                   order: "order-past-rive-carottes", daysAgo: 8),
            review(ID.fermeRive, "household-nguyen", "Minh N.", 5,
                   "Livraison à l'heure au point de cueillette, et le sac pesait bien 10 kg.",
                   order: "order-past-rive-pdt", daysAgo: 36),
            review(ID.fermeRive, "household-diallo", "Fatou D.", 4,
                   "Très bonnes courges. Un peu de retard le samedi, mais on a été prévenus.",
                   order: "order-past-rive-courges", daysAgo: 21),
            review(ID.fermeRive, "household-roy", "Marc R.", 5, nil, order: "order-past-rive-courges", daysAgo: 20),
            review(ID.fermeRive, "household-haddad", "Rania H.", 4,
                   "Bon rapport qualité-prix, on économise vraiment par rapport à l'épicerie.",
                   order: "order-past-rive-oignons", daysAgo: 58),
            review(ID.moulinsDuNord, "household-lopez", "Carlos L.", 5,
                   "Riz parfumé, sac bien scellé. On recommande en groupe dès le prochain lot.",
                   order: "order-past-moulins-riz", daysAgo: 11),
            review(ID.moulinsDuNord, "household-gagnon", "Sophie G.", 4,
                   "Lentilles de qualité, juste un peu de poussière dans le sac.",
                   order: "order-past-moulins-lentilles", daysAgo: 30),
            review(ID.moulinsDuNord, "household-pierre", "Jean P.", 4, nil,
                   order: "order-past-moulins-riz", daysAgo: 10),
            review(ID.fournil, ID.aminaHousehold, "Amina B.", 5,
                   "Le levain est incroyable, et le boulanger nous a ajouté des croissants.",
                   order: "order-past-fournil-levain", daysAgo: 4),
            review(ID.fournil, "household-martin", "Élodie M.", 5,
                   "Pain encore tiède à la cueillette. Merci !", order: "order-past-fournil-levain", daysAgo: 4),
        ]
    }()
}
