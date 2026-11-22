import Foundation

/// Mots rapides de la feuille d'avis (« Bonne ambiance », « Produits frais ») : toucher une pastille l'ajoute au
/// commentaire, la retoucher l'en retire. Rien de plus qu'un texte : aucun champ du modèle n'est ajouté.
///
///     RatingCommentTags.toggled("Bien organisé", in: "Bonne ambiance", maxLength: 280)  // "Bonne ambiance, bien organisé"
nonisolated enum RatingCommentTags {
    /// Pastilles proposées pour un groupe.
    static var group: [String] {
        [String(localized: "Bonne ambiance"), String(localized: "Bien organisé"), String(localized: "Cueillettes à l'heure"),
         String(localized: "Bonne communication"), String(localized: "Prix avantageux")]
    }

    /// Pastilles proposées pour un producteur.
    static var vendor: [String] {
        [String(localized: "Produits frais"), String(localized: "Bonne quantité"), String(localized: "Livré à l'heure"),
         String(localized: "Bon prix"), String(localized: "Bien emballé")]
    }

    /// Le commentaire contient déjà ce mot rapide (sans tenir compte de la casse).
    static func contains(_ tag: String, in comment: String) -> Bool {
        comment.range(of: tag, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Ajoute le mot rapide à la fin du commentaire, ou le retire s'il y est déjà.
    /// Renvoie nil si l'ajout dépasserait `maxLength` (le commentaire ne change pas).
    static func toggled(_ tag: String, in comment: String, maxLength: Int) -> String? {
        if let range = comment.range(of: tag, options: [.caseInsensitive, .diacriticInsensitive]) {
            return removing(range, from: comment)
        }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: String
        if trimmed.isEmpty {
            result = tag
        } else if let last = trimmed.last, ".!?".contains(last) {
            result = trimmed + " " + tag
        } else {
            result = trimmed + ", " + lowercasedFirst(tag)
        }
        return result.count <= maxLength ? result : nil
    }

    private static func removing(_ range: Range<String.Index>, from comment: String) -> String {
        let startsAtBeginning = comment[..<range.lowerBound].allSatisfy { $0.isWhitespace || $0 == "," }
        var text = comment
        text.removeSubrange(range)
        // Virgules orphelines laissées par le retrait : « a, , b » → « a, b », « , b » → « b ».
        text = text.replacingOccurrences(of: #"\s*,(\s*,)+\s*"#, with: ", ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([.!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^[\s,]+|[\s,]+$"#, with: "", options: .regularExpression)
        return startsAtBeginning ? uppercasedFirst(text) : text
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func uppercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
