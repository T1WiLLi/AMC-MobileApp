// ShareSpec.swift
// B-050 : ce que contient une part d'un lot, structuré au lieu d'une chaîne libre.
// Type de contenant (sac, caisse, palette, botte…), nombre de contenants, poids ou volume
// (valeur + unité) et valeur indicative en dollars. `label` redonne le texte affiché partout
// (« sac de 10 kg ») et `init(parsing:)` relit les anciennes chaînes (`Offer.shareUnit`).

import Foundation

nonisolated struct ShareSpec: Codable, Sendable, Hashable {
    /// Contenant d'une part. `bulk` : pas de contenant nommé (« 10 kg »).
    enum Container: String, Codable, Sendable, CaseIterable, Identifiable {
        case bag = "sac"
        case crate = "caisse"
        case box = "boite"
        case pallet = "palette"
        case bunch = "botte"
        case bottle = "bouteille"
        case net = "filet"
        case tray = "plateau"
        case bulk = "vrac"

        var id: String { rawValue }

        /// Nom au singulier, accentué : « sac », « boîte ».
        var name: String {
            switch self {
            case .bag: "sac"
            case .crate: "caisse"
            case .box: "boîte"
            case .pallet: "palette"
            case .bunch: "botte"
            case .bottle: "bouteille"
            case .net: "filet"
            case .tray: "plateau"
            case .bulk: "vrac"
            }
        }

        /// Nom au pluriel : « sacs », « plateaux ».
        var pluralName: String {
            switch self {
            case .tray: "plateaux"
            case .bulk: "vrac"
            default: name + "s"
            }
        }

        /// Nom affiché dans un menu : « Sac », « En vrac ».
        var menuTitle: String {
            self == .bulk ? "En vrac" : name.prefix(1).uppercased() + name.dropFirst()
        }

        var systemImage: String {
            switch self {
            case .bag: "bag.fill"
            case .crate: "shippingbox.fill"
            case .box: "archivebox.fill"
            case .pallet: "square.stack.3d.up.fill"
            case .bunch: "leaf.fill"
            case .bottle: "waterbottle.fill"
            case .net: "basket.fill"
            case .tray: "tray.fill"
            case .bulk: "scalemass.fill"
            }
        }
    }

    /// Unité du poids (ou du volume, ou du nombre d'unités) d'un contenant.
    enum Unit: String, Codable, Sendable, CaseIterable, Identifiable {
        case kilogram = "kg"
        case gram = "g"
        case pound = "lb"
        case liter = "L"
        case milliliter = "mL"
        case piece = "unité"

        var id: String { rawValue }

        var isVolume: Bool { self == .liter || self == .milliliter }

        /// Facteur vers le kg (masse), le L (volume) ou l'unité.
        var factor: Double {
            switch self {
            case .kilogram, .liter, .piece: 1
            case .gram, .milliliter: 0.001
            case .pound: 0.453_592
            }
        }
    }

    /// Poids (ou volume, ou nombre d'unités) d'un contenant : « 10 kg », « 500 g », « 12 unités ».
    struct Weight: Codable, Sendable, Hashable {
        var value: Double
        var unit: Unit

        init(_ value: Double, _ unit: Unit) {
            self.value = value
            self.unit = unit
        }

        /// « 10 kg », « 2,5 kg », « 1 unité », « 12 unités ».
        var label: String {
            let number = ShareSpec.format(value)
            guard unit == .piece else { return "\(number) \(unit.rawValue)" }
            return value > 1 ? "\(number) unités" : "\(number) unité"
        }
    }

    var container: Container
    /// Contenants par part (« 2 sacs de 5 kg ») ; 1 le plus souvent.
    var count: Int
    var weight: Weight
    /// Valeur indicative d'une part, en cents (ex. prix en épicerie) ; nil si non renseignée.
    var valueCents: Int?

    init(container: Container, count: Int = 1, weight: Weight, valueCents: Int? = nil) {
        self.container = container
        self.count = count
        self.weight = weight
        self.valueCents = valueCents
    }

    /// Texte affiché : « sac de 10 kg », « 2 sacs de 5 kg », « 10 kg » (vrac), « botte de 12 unités ».
    var label: String {
        guard container != .bulk else {
            return count > 1 ? "\(count) × \(weight.label)" : weight.label
        }
        // Contenant sans poids connu : « 1 caisse », pas « caisse de 1 unité ».
        if weight == Weight(1, .piece) { return "\(count) \(count > 1 ? container.pluralName : container.name)" }
        let name = count > 1 ? "\(count) \(container.pluralName)" : container.name
        return "\(name) de \(weight.label)"
    }

    /// Contenu total d'une part, pour les économies et le planificateur (`ShareMeasure`).
    var measure: ShareMeasure {
        let total = Double(max(count, 1)) * weight.value * weight.unit.factor
        guard total > 0, total.isFinite, total <= ShareMeasure.maxParsedAmount else { return .unknown }
        switch weight.unit {
        case .liter, .milliliter: return .volume(liters: total)
        case .piece: return .count(units: max(1, Int(total.rounded())))
        case .kilogram, .gram, .pound: return .mass(kilograms: total)
        }
    }

    /// Part valide : au moins un contenant et un poids positif et fini.
    var isValid: Bool {
        count >= 1 && count <= 1_000 && weight.value > 0 && weight.value.isFinite
            && weight.value <= ShareMeasure.maxParsedAmount && (valueCents ?? 0) >= 0
    }

    /// Part par défaut d'un nouveau lot : un sac de 10 kg.
    static let `default` = ShareSpec(container: .bag, weight: .init(10, .kilogram))
}

// MARK: - Lecture d'une ancienne chaîne

nonisolated extension ShareSpec {
    /// Relit une unité de part écrite à la main (« sac de 10 kg », « 2 sacs de 5 kg », « 5 L », « kg »,
    /// « 1 douzaine », « caisse de 5 kg »). Ce qui n'est pas reconnu donne 1 unité en vrac.
    init(parsing text: String) {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .replacingOccurrences(of: ",", with: ".")
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init)

        // Contenant : premier mot connu (« sac », « sacs », « boite »…), avec un nombre juste avant (« 2 sacs »).
        var container = Container.bulk
        var count = 1
        for (index, word) in words.enumerated() {
            guard let found = Container.allCases.first(where: { $0 != .bulk && (word == $0.rawValue || word == $0.rawValue + "s" || word == $0.rawValue + "x") }) else { continue }
            container = found
            if index > 0, let number = Int(words[index - 1]), number >= 1, number <= 1_000 { count = number }
            break
        }

        // Poids : lu par `ShareMeasure` sur le texte après le contenant (« 2 sacs de 5 kg » → 5 kg par sac).
        // « 3 caisses » sans « de … » : le nombre est celui des contenants, pas un poids.
        var weight = Weight(1, .piece)
        if container == .bulk {
            weight = Self.weight(in: folded)
        } else if let range = folded.range(of: " de ") {
            weight = Self.weight(in: String(folded[range.upperBound...]))
        }
        self.init(container: container, count: count, weight: weight)
    }

    /// Poids lu dans `text`, en gardant l'unité écrite quand elle est simple (« 500 g » reste en g).
    private static func weight(in text: String) -> Weight {
        if let match = text.firstMatch(of: /(\d+(?:\.\d+)?)\s*(kg|g|lb|l|ml)\b/),
           let value = Double(match.1), value > 0, value <= ShareMeasure.maxParsedAmount {
            let unit: Unit = switch match.2 {
            case "kg": .kilogram
            case "g": .gram
            case "lb": .pound
            case "l": .liter
            default: .milliliter
            }
            return Weight(value, unit)
        }
        switch ShareMeasure.parse(text) {
        case .mass(let kilograms): return Weight(kilograms, .kilogram)
        case .volume(let liters): return Weight(liters, .liter)
        case .count(let units): return Weight(Double(units), .piece)
        case .unknown: return Weight(1, .piece)
        }
    }

    /// « 10 », « 2,5 », « 0,45 » : virgule décimale, deux décimales au plus, sans zéros inutiles.
    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "fr_CA")))
    }
}
