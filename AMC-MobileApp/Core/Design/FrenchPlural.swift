import Foundation

/// Accord en nombre : en français 0 et 1 sont au singulier, 2 et plus au pluriel ; en anglais seul 1 est singulier.
///
///     FrenchPlural.count(1, "part")              // « 1 part » / "1 share"
///     FrenchPlural.count(24, "famille")          // « 24 familles » / "24 families"
///     FrenchPlural.word(3, "engagée")            // « engagées » / "committed"
///
/// T-171 : les mots courants (`knownNouns`) passent par le catalogue de chaînes, avec une clé `%lld <singulier>`
/// et des variations de pluriel `one` / `other` dans chaque langue. Un mot absent de la liste (unité de vente saisie
/// par un producteur, mot déjà traduit par `String(localized:)`) garde la règle simple « singulier + s ».
nonisolated enum FrenchPlural {
    /// Vrai si `count` demande le pluriel (règle française : |n| ≥ 2).
    static func isPlural(_ count: Int) -> Bool {
        abs(count) >= 2
    }

    /// Le mot accordé, sans le nombre. Pluriel par défaut : singulier + « s ».
    static func word(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        if knownNouns.contains(singular) {
            let counted = localizedCount(count, singular)
            let prefix = "\(count) "
            return counted.hasPrefix(prefix) ? String(counted.dropFirst(prefix.count)) : counted
        }
        let plurals = AppLanguage.isEnglish ? count != 1 : isPlural(count)
        return plurals ? (plural ?? singular + "s") : singular
    }

    /// Le nombre suivi du mot accordé : « 1 part », « 40 parts ».
    static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        if knownNouns.contains(singular) { return localizedCount(count, singular) }
        return "\(count) \(word(count, singular, plural: plural))"
    }

    /// Résout la clé `%lld <singulier>` du catalogue (variations de pluriel de la langue en cours).
    private static func localizedCount(_ count: Int, _ singular: String) -> String {
        var interpolation = String.LocalizationValue.StringInterpolation(literalCapacity: singular.count + 1, interpolationCount: 1)
        interpolation.appendInterpolation(count)
        interpolation.appendLiteral(" " + singular)
        return AppLanguage.localized(String.LocalizationValue(stringInterpolation: interpolation))
    }

    /// Mots du catalogue (clé `%lld <mot>`, ajoutée à la main dans `Localizable.xcstrings`).
    private static let knownNouns: Set<String> = [
        "famille",
        "part",
        "panier",
        "panier suspendu",
        "panier entier",
        "famille intéressée",
        "famille aidée",
        "famille couverte",
        "membre",
        "lot ouvert",
        "autre lot",
        "commande",
        "manquante",
        "engagée",
        "produit",
        "ménage",
        "ménage aidé",
        "photo",
        "mois",
        "personne",
        "heure",
        "jour",
        "groupe",
        "groupe de quartier",
        "portail",
        "ferme",
        "lieu",
        "avis",
        "unité",
        "zone",
        "douzaine",
        "voulue",
        "panier suspendu offert",
        "hôte",
        "trajet",
        "producteur",
    ]
}
