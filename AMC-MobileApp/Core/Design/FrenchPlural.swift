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
    static func word(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        isPlural(count) ? (plural ?? singular + "s") : singular
    }

    /// Le nombre suivi du mot accordé : « 1 part », « 40 parts ».
    static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(word(count, singular, plural: plural))"
    }
}
