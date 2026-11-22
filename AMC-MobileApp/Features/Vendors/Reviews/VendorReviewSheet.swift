import SwiftUI

/// Feuille de notation d'un producteur (T-157) : 1 à 5 étoiles et un commentaire facultatif.
/// Préremplie avec l'avis existant du ménage (un seul avis par ménage, modifiable).
/// Mise en page commune avec les groupes (T-174) : `RatingSheet`.
///
///     .sheet(isPresented: $rates) {
///         VendorReviewSheet(vendorName: "Ferme Bio-Rive", saleText: "Carottes nantaises, il y a 9 jours",
///                           existing: myReview) { rating, comment in await model.saveReview(rating: rating, comment: comment) }
///     }
struct VendorReviewSheet: View {
    let vendorName: String
    /// Le lot reçu qui permet de noter (« Carottes nantaises · il y a 9 jours »), nil si inconnu.
    var saleText: String?
    var existing: VendorReview?
    /// Enregistre ; renvoie l'erreur à afficher, nil si c'est enregistré.
    let onSave: (Int, String) async -> AppError?

    init(vendorName: String, saleText: String? = nil, existing: VendorReview? = nil,
         onSave: @escaping (Int, String) async -> AppError?) {
        self.vendorName = vendorName
        self.saleText = saleText
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        RatingSheet(
            title: vendorName,
            prompt: String(localized: "Comment était ton lot ?"),
            context: saleText.map { .init(text: $0, systemImage: "shippingbox.fill") },
            placeholder: String(localized: "Fraîcheur, ponctualité, quantité…"),
            maxLength: VendorReview.maxCommentLength,
            existingRating: existing?.rating,
            existingComment: existing?.comment,
            onSave: onSave
        )
    }
}

#Preview("Nouvel avis") {
    Color.fond.sheet(isPresented: .constant(true)) {
        VendorReviewSheet(vendorName: "Ferme Bio-Rive", saleText: "Carottes nantaises · il y a 9 jours") { _, _ in nil }
    }
}

#Preview("Modifier, sombre") {
    Color.fond.sheet(isPresented: .constant(true)) {
        VendorReviewSheet(vendorName: "Le Fournil du coin", existing: FakeData.demoVendorReviews[8]) { _, _ in .offline }
    }
    .preferredColorScheme(.dark)
}
