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
}
