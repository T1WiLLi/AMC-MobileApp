import SwiftUI

/// Route vers la fiche d'un lot (F3, F4). Poussée depuis l'Accueil, les Groupes ou la Recherche :
///
///     NavigationLink(value: OfferRoute(offerId: offer.id)) { OfferCard(…) }
///     …
///     .offerDestination()   // une fois, sur la racine du NavigationStack de l'onglet
struct OfferRoute: Hashable, Sendable {
    let offerId: String
}

extension View {
    /// Enregistre la destination `OfferRoute` → `OfferDetailScreen` dans le NavigationStack englobant.
    /// La fiche sort en zoom de la carte marquée `.grenierZoomSource(OfferRoute(…))` (T-123).
    func offerDestination() -> some View {
        grenierZoomDestination(for: OfferRoute.self) { route in
            OfferDetailScreen(offerId: route.offerId)
        }
    }
}
