import Foundation

/// Accord en nombre en français : 0 et 1 sont au singulier, 2 et plus au pluriel.
///
///     FrenchPlural.count(1, "part")              // « 1 part »
///     FrenchPlural.count(24, "famille")          // « 24 familles »
///     FrenchPlural.word(3, "engagée")            // « engagées »
nonisolated enum FrenchPlural {
    /// Vrai si `count` demande le pluriel (règle française : |n| ≥ 2).
    static func isPlural(_ count: Int) -> Bool {
        abs(count) >= 2
    }

    /// Le mot accordé, sans le nombre. Pluriel par défaut : singulier + « s ».
    /// En anglais (T-171), les mots courants du catalogue sont traduits ici : « 1 family », « 12 families ».
    static func word(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        if isEnglish, let english = englishWords[singular] {
            return count == 1 ? english.one : english.other
        }
        return isPlural(count) ? (plural ?? singular + "s") : singular
    }

    private static var isEnglish: Bool {
        AppLanguage.formattingLocale.language.languageCode?.identifier == "en"
    }

    /// Mots français passés littéralement à `word` / `count` → (singulier, pluriel) anglais.
    private static let englishWords: [String: (one: String, other: String)] = [
        "famille": ("family", "families"),
        "part": ("share", "shares"),
        "panier": ("basket", "baskets"),
        "panier suspendu": ("suspended basket", "suspended baskets"),
        "panier entier": ("full basket", "full baskets"),
        "famille intéressée": ("interested family", "interested families"),
        "famille aidée": ("family helped", "families helped"),
        "famille couverte": ("family covered", "families covered"),
        "membre": ("member", "members"),
        "lot ouvert": ("open bundle", "open bundles"),
        "autre lot": ("other bundle", "other bundles"),
        "commande": ("order", "orders"),
        "manquante": ("missing", "missing"),
        "engagée": ("committed", "committed"),
        "produit": ("product", "products"),
        "ménage": ("household", "households"),
        "ménage aidé": ("subsidised household", "subsidised households"),
        "photo": ("photo", "photos"),
        "mois": ("month", "months"),
        "personne": ("person", "people"),
        "heure": ("hour", "hours"),
        "jour": ("day", "days"),
        "groupe": ("group", "groups"),
        "groupe de quartier": ("neighbourhood group", "neighbourhood groups"),
        "portail": ("portal", "portals"),
        "ferme": ("closes", "close"),
        "lieu": ("place", "places"),
        "avis": ("review", "reviews"),
        "unité": ("unit", "units"),
        "zone": ("zone", "zones"),
        "douzaine": ("dozen", "dozens"),
        "voulue": ("wanted", "wanted"),
        "Lot ouvert": ("Open bundle", "Open bundles"),
        "panier suspendu offert": ("suspended basket offered", "suspended baskets offered"),
    ]

    /// Le nombre suivi du mot accordé : « 1 part », « 40 parts ».
    static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(word(count, singular, plural: plural))"
    }
}
