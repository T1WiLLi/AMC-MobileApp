import Foundation

/// Les concepts de LeGrenier expliqués en français simple (FB-08).
/// Un seul endroit pour tous les textes des boutons « i » : `InfoButton(topic:)`.
nonisolated enum InfoTopic: String, CaseIterable, Identifiable, Sendable {
    case offers
    case tiers
    case share
    case suspendedBasket
    case pickup
    case pickupSlot
    /// Carte « Ton code de cueillette » quand le QR est affiché.
    case pickupCode
    /// Carte « Ton code de cueillette » avant la clôture (pas encore de code).
    case pickupCodePending
    case mapRadius
    case group
    case impact
    case vendorDemand
    case vendorOffers
    case lockedTerms

    var id: String { rawValue }

    /// Titre court de la fenêtre d'explication.
    var title: String {
        switch self {
        case .offers: String(localized: "Les lots")
        case .tiers: String(localized: "Les paliers de prix")
        case .share: String(localized: "Une part")
        case .suspendedBasket: String(localized: "Le panier suspendu")
        case .pickup: String(localized: "La cueillette")
        case .pickupSlot: String(localized: "Les créneaux")
        case .pickupCode, .pickupCodePending: String(localized: "Ton code de cueillette")
        case .mapRadius: String(localized: "Le rayon de la carte")
        case .group: String(localized: "Les groupes")
        case .impact: String(localized: "Ton impact")
        case .vendorDemand: String(localized: "La demande")
        case .vendorOffers: String(localized: "Tes lots")
        case .lockedTerms: String(localized: "Conditions figées")
        }
    }

    /// Deux ou trois phrases simples.
    var message: String {
        switch self {
        case .offers:
            String(localized: "Un lot, c'est une grosse quantité qu'un producteur vend à tout le quartier. Chaque famille en prend une part. Plus on est nombreux, moins ça coûte.")
        case .tiers:
            String(localized: "Le prix baisse quand assez de parts sont prises : c'est un palier. Tout le monde paie le prix du dernier palier atteint, même ceux qui ont réservé tôt.")
        case .share:
            String(localized: "Une part, c'est ta portion du lot, par exemple 2 kg de riz. Tu peux en réserver plusieurs. Tu paies seulement quand le lot ferme.")
        case .suspendedBasket:
            String(localized: "Tu peux ajouter quelques dollars pour une famille qui en a besoin. Ton groupe s'en sert pour offrir un panier, sans dire à qui. Personne ne voit qui a donné.")
        case .pickup:
            String(localized: "Quand le lot est livré, tu viens chercher tes parts au point de cueillette de ton groupe. Montre ton code QR : un voisin bénévole te remet ton panier.")
        case .pickupCode:
            String(localized: "L'hôte scanne ce code et te remet toutes tes parts du groupe. Les articles encore ouverts s'ajoutent au code à leur clôture. La luminosité monte au maximum pour faciliter le scan.")
        case .pickupCodePending:
            String(localized: "Quand la commande ferme, ton code de cueillette s'affiche ici. On te prévient ensuite dès que la livraison arrive.")
        case .pickupSlot:
            String(localized: "Un créneau, c'est l'heure où tu passes chercher ton panier. Choisis celui qui t'arrange : ça évite la file au point de cueillette.")
        case .mapRadius:
            String(localized: "La carte montre les groupes, producteurs et points de cueillette autour de toi. Le rayon, c'est la distance jusqu'où on cherche. Agrandis-le si tu ne vois rien.")
        case .group:
            String(localized: "Un groupe, ce sont des familles du même quartier qui commandent ensemble. Ensemble, vous atteignez les paliers plus vite et vous partagez le même point de cueillette.")
        case .impact:
            String(localized: "Ici, tu vois ce que tes achats en groupe ont changé : l'argent économisé, la nourriture sauvée et les paniers offerts. Les chiffres grandissent à chaque commande.")
        case .vendorDemand:
            String(localized: "La demande, c'est ce que les familles ont commandé ou souhaitent acheter près de chez elles. Sers-t'en pour savoir quoi proposer et où livrer.")
        case .vendorOffers:
            String(localized: "Un lot, c'est un produit que tu vends en grande quantité à un groupe. Tu fixes des paliers : plus les familles prennent de parts, plus le prix baisse.")
        case .lockedTerms:
            String(localized: "Le lot est publié : les familles voient déjà ces conditions, elles ne peuvent plus changer.")
        }
    }

    /// Symbole affiché à côté du titre.
    var systemImage: String {
        switch self {
        case .offers, .vendorOffers: "shippingbox.fill"
        case .tiers: "chart.line.downtrend.xyaxis"
        case .share: "chart.pie.fill"
        case .suspendedBasket: "heart.fill"
        case .pickup, .pickupCode, .pickupCodePending: "qrcode"
        case .pickupSlot: "calendar.badge.clock"
        case .mapRadius: "scope"
        case .group: "person.3.fill"
        case .impact: "leaf.fill"
        case .vendorDemand: "map.fill"
        case .lockedTerms: "lock.fill"
        }
    }

    /// Label VoiceOver du bouton « i ».
    var accessibilityLabel: String {
        String(localized: "En savoir plus sur \(title.lowercased(with: AppLanguage.formattingLocale))")
    }
}
