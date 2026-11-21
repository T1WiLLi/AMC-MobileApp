import SwiftUI

/// Fiche d'un lot et choix de sa part (maquettes F3, F4).
/// Version provisoire : l'agent des écrans F3/F4 la remplace par la vraie fiche branchée sur `OfferDetailViewModel`.
struct OfferDetailScreen: View {
    let offerId: String
    @Environment(\.appContext) private var context

    var body: some View {
        ContentUnavailableView(
            "Fiche du lot",
            systemImage: "shippingbox.fill",
            description: Text("Le détail de ce lot arrive très bientôt.")
        )
        .grenierBackground()
        .navigationTitle("Lot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack {
        OfferDetailScreen(offerId: FakeData.ID.riceOffer)
    }
}
