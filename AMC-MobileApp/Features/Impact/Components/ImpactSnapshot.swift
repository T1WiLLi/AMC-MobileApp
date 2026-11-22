import Foundation

/// Données de vue de l'écran Impact (maquette F6). Pas de logique de chargement ici :
/// `ImpactViewModel` produira un `ImpactSnapshot`, les composants ne font que l'afficher.
struct ImpactSnapshot: Sendable, Hashable {
    /// Économies d'un mois, pour le graphique.
    struct MonthlySaving: Identifiable, Sendable, Hashable {
        /// Premier jour du mois.
        let month: Date
        let savedCents: Cents
        var id: Date { month }

        /// « août », « sept. », « nov. »
        var shortLabel: String {
            month.formatted(.dateTime.month(.abbreviated).locale(ImpactFormat.locale))
        }

        /// « novembre », pour VoiceOver.
        var longLabel: String {
            month.formatted(.dateTime.month(.wide).locale(ImpactFormat.locale))
        }
    }

    // MARK: Le ménage
    /// Prénom de la personne connectée (« Amina »).
    var firstName: String
    /// Quartier (« Parc-Extension »).
    var neighborhoodName: String
    /// Économies des derniers mois, du plus ancien au plus récent ; le dernier est le mois courant.
    var monthlySavings: [MonthlySaving]

    // MARK: Le quartier
    /// Ménages du groupe (« 24 familles »).
    var households: Int
    /// Hôtes de cueillette bénévoles.
    var hosts: Int
    /// Économies cumulées du quartier ce mois-ci, vs épicerie.
    var neighborhoodSavedCents: Cents
    /// Paniers suspendus offerts.
    var suspendedBasketsOffered: Int
    /// Ménages qui ont reçu un panier suspendu.
    var householdsHelped: Int
    /// Argent versé directement aux producteurs du Québec.
    var paidToProducersCents: Cents
    /// Fermes et producteurs du Québec servis.
    var producers: Int
    /// Kilos achetés en direct.
    var kilogramsBought: Double
    /// Emballages individuels évités grâce au vrac.
    var packagingAvoided: Int
    /// Trajets de livraison (camions vers les épiceries) évités.
    var deliveryTripsAvoided: Int
    /// Trajets des familles vers l'épicerie évités.
    var groceryTripsAvoided: Int
    /// Kilomètres de ces trajets évités.
    var groceryKilometersAvoided: Double
    /// Part des achats en produits frais (fruits, légumes, légumineuses), de 0 à 1.
    var freshProduceShare: Double

    /// Économies du mois courant (dernier mois du graphique).
    var currentMonthSavedCents: Cents { monthlySavings.last?.savedCents ?? 0 }

    /// Mois courant (« novembre »), ou chaîne vide.
    var currentMonthName: String { monthlySavings.last?.longLabel ?? "" }
}

extension ImpactSnapshot {
    /// Démo cohérente avec DESIGN-SYSTEM.md : Amina 48 $ ce mois-ci, quartier 3 900 $, 12 paniers suspendus,
    /// 1,2 t chez 6 fermes du Québec, −41 km de trajets vers l'épicerie.
    static let demo = ImpactSnapshot(
        firstName: "Amina",
        neighborhoodName: "Parc-Extension",
        monthlySavings: [
            .init(month: ImpactFormat.month(2026, 8), savedCents: 22_00),
            .init(month: ImpactFormat.month(2026, 9), savedCents: 31_00),
            .init(month: ImpactFormat.month(2026, 10), savedCents: 39_00),
            .init(month: ImpactFormat.month(2026, 11), savedCents: 48_00)
        ],
        households: 24,
        hosts: 2,
        neighborhoodSavedCents: 3_900_00,
        suspendedBasketsOffered: 12,
        householdsHelped: 9,
        // Environ 37 % d'économie vs épicerie : 3 900 $ économisés ≈ 6 640 $ payés aux fermes.
        paidToProducersCents: 6_640_00,
        producers: 6,
        kilogramsBought: 1_200,
        packagingAvoided: 310,
        deliveryTripsAvoided: 22,
        groceryTripsAvoided: 38,
        groceryKilometersAvoided: 41,
        freshProduceShare: 0.62
    )
}

/// Formats partagés de l'écran Impact (français du Canada, espaces insécables).
enum ImpactFormat {
    static var locale: Locale { AppLanguage.formattingLocale }
    static let nbsp = "\u{00A0}"

    /// Premier jour d'un mois, à Montréal.
    static func month(_ year: Int, _ month: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    /// « 3 900 » (séparateur de milliers québécois).
    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// « 1,2 » (au plus `fractionDigits` décimales).
    static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)).locale(locale))
    }

    /// Accord simple : « 1 famille », « 24 familles ».
    static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        "\(integer(count))\(nbsp)\(count > 1 ? (pluralForm ?? singular + "s") : singular)"
    }
}
