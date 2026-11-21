import Foundation

/// Formatage des montants Grenier (cents CAD → « 2,60 $ »), en français du Canada.
enum Money {
    private static let locale = Locale(identifier: "fr_CA")

    /// « 2,60 $ »
    static func format(_ cents: Cents) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "CAD").locale(locale))
    }

    /// « 48 $ » (sans décimales quand le montant est rond), sinon « 48,50 $ ».
    static func formatRounded(_ cents: Cents) -> String {
        if cents % 100 == 0 {
            return (Decimal(cents) / 100).formatted(.currency(code: "CAD").precision(.fractionLength(0)).locale(locale))
        }
        return format(cents)
    }

    /// Pourcentage d'économie d'un prix par rapport à une référence, arrondi (37 pour −37 %). 0 si pas d'économie.
    static func savingsPercent(price: Cents, reference: Cents) -> Int {
        guard reference > 0, price < reference else { return 0 }
        return Int((Double(reference - price) / Double(reference) * 100).rounded())
    }

    // MARK: - Lecture VoiceOver

    /// Montant tel qu'on le dit à voix haute : « 2 dollars 60 », « 48 dollars », « 1 dollar », « 60 cents ».
    /// VoiceOver lit « 2,60 $ » comme « deux virgule soixante dollars » : on lui donne la forme parlée.
    static func spoken(_ cents: Cents) -> String {
        let sign = cents < 0 ? "moins " : ""
        let value = abs(cents)
        let dollars = value / 100
        let rest = value % 100
        if dollars == 0 { return sign + FrenchPlural.count(Int(rest), "cent") }
        let dollarsText = FrenchPlural.count(Int(dollars), "dollar")
        return sign + (rest == 0 ? dollarsText : "\(dollarsText) \(rest)")
    }

    /// Unité de prix à voix haute : « le kilo », « la livre », « par caisse ».
    static func spokenPerUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "kg": "le kilo"
        case "g": "le gramme"
        case "lb": "la livre"
        case "l": "le litre"
        case "ml": "le millilitre"
        case "unité", "u": "l'unité"
        default: "par \(unit)"
        }
    }

    /// « 2 dollars 60 le kilo » ; sans unité, le montant seul.
    static func spoken(_ cents: Cents, per unit: String?) -> String {
        guard let unit else { return spoken(cents) }
        return "\(spoken(cents)) \(spokenPerUnit(unit))"
    }
}
