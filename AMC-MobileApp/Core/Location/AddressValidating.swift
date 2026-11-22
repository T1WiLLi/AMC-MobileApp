// AddressValidating.swift
// T-185 : toute adresse saisie dans l'app est vérifiée auprès d'Apple (MapKit) avant d'être enregistrée.
//
// - `AddressValidating` : suggestions pendant la frappe et validation d'une adresse (protocole + fake).
// - `ValidatedAddress` : adresse normalisée par Apple, avec sa position (pour le geohash).
// - `AddressMatching` : règles pures (numéro civique, nom de rue, appartement, code postal), testables.
//
// Implémentation réelle : `MapKitAddressValidator` (MKLocalSearchCompleter + MKLocalSearch).

import Foundation

/// Suggestion d'adresse affichée sous le champ (« 7420 Av Ogilvy » / « Montréal, QC, Canada »).
nonisolated struct AddressSuggestion: Identifiable, Sendable, Hashable {
    var title: String
    var subtitle: String

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    /// Texte complet, aussi utilisé comme requête de validation quand on la choisit.
    var id: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

/// Adresse trouvée par Apple, normalisée.
nonisolated struct ValidatedAddress: Sendable, Hashable {
    /// Adresse complète sur une ligne, sans le pays (« 8150 Boulevard Pie-IX, Montréal QC H1Z 3T8 »).
    var formatted: String
    /// Numéro et rue seulement (« 8150 Boulevard Pie-IX »).
    var streetLine: String
    /// Code postal si Apple le donne (« H1Z 3T8 »).
    var postalCode: String?
    var coordinate: Geohash.Coordinate

    init(formatted: String, streetLine: String, postalCode: String? = nil, coordinate: Geohash.Coordinate) {
        self.formatted = formatted
        self.streetLine = streetLine
        self.postalCode = postalCode
        self.coordinate = coordinate
    }

    /// Geohash de la position (7 caractères ≈ 150 m par défaut, comme les points de cueillette).
    func geohash(precision: Int = 7) -> String { Geohash.encode(coordinate, precision: precision) }
}

/// Vérifie qu'une adresse existe. Appelé depuis le main actor (les vues et leurs modèles).
@MainActor
protocol AddressValidating: Sendable {
    /// Suggestions d'adresses pour un début de saisie ; vide si rien ou en cas d'erreur.
    func suggestions(for query: String) async -> [AddressSuggestion]
    /// Adresse normalisée si elle existe (numéro civique compris), `nil` si Apple ne la trouve pas.
    /// Lève une erreur quand la vérification est impossible (réseau, service Apple) : ce n'est pas
    /// « introuvable », l'adresse tapée est alors gardée sans vérification.
    func validate(_ text: String) async throws -> ValidatedAddress?
}

// MARK: - Règles pures

nonisolated enum AddressMatching {
    /// Mots qui ne disent rien du nom de la rue (types de voie, directions, villes, pays).
    static let genericWords: Set<String> = [
        "rue", "avenue", "av", "ave", "boulevard", "boul", "bd", "blvd", "chemin", "ch", "place", "pl",
        "route", "rte", "montee", "rang", "street", "st", "road", "rd", "drive", "dr", "croissant", "terrasse",
        "est", "ouest", "nord", "sud", "east", "west", "north", "south",
        "de", "du", "des", "la", "le", "les", "l", "d",
        "montreal", "qc", "quebec", "canada", "app", "apt", "appartement", "unite", "suite", "bureau", "local",
    ]

    /// Numéro civique en tête (« 7420 », « 1234a », « 12-14 » → « 12 »), en minuscules ; nil s'il n'y en a pas.
    static func civicNumber(in text: String) -> String? {
        let folded = fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = folded.firstMatch(of: /^(\d+)([a-z](?![a-z]))?/) else { return nil }
        return String(match.output.1) + (match.output.2.map(String.init) ?? "")
    }

    /// Mots significatifs du nom de rue (pliés, sans types de voie ni numéros).
    static func streetWords(in text: String) -> [String] {
        let withoutUnit = text.replacing(unitPattern, with: "")
        return fold(withoutUnit)
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 && !genericWords.contains($0) }
    }

    /// Le résultat d'Apple correspond-il à ce qu'on a tapé ? Même numéro civique, et au moins un mot de rue
    /// qui se ressemble (4 premières lettres : « Ogilvy » et « Ogilvie » passent, « Jarry » et « Pie-IX » non).
    static func matches(input: String, candidateStreetLine: String) -> Bool {
        guard let number = civicNumber(in: input), let found = civicNumber(in: candidateStreetLine) else { return false }
        // « 1234a » accepte « 1234 » chez Apple (la lettre est souvent absente des données), pas l'inverse.
        guard found == number || (number.hasPrefix(found) && number.dropFirst(found.count).allSatisfy(\.isLetter)) else {
            return false
        }
        let typed = streetWords(in: input)
        guard !typed.isEmpty else { return true }
        let candidate = streetWords(in: candidateStreetLine)
        return typed.contains { word in candidate.contains { $0.prefix(4) == word.prefix(4) } }
    }

    /// Partie « appartement » tapée par la personne (« , app. 3 »), à garder après la normalisation.
    static func unitSuffix(in text: String) -> String? {
        guard let match = text.firstMatch(of: unitPattern) else { return nil }
        let unit = String(text[match.range]).trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        return unit.isEmpty ? nil : unit
    }

    /// Code postal canadien trouvé dans un texte, formaté « H1Z 3T8 ».
    static func postalCode(in text: String) -> String? {
        guard let match = text.uppercased().firstMatch(of: /\b([A-Z]\d[A-Z])\s?(\d[A-Z]\d)\b/) else { return nil }
        return "\(match.output.1) \(match.output.2)"
    }

    /// Adresse d'Apple sans le pays (« …, Canada »).
    static func withoutCountry(_ text: String) -> String {
        var parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 1, let last = parts.last, fold(last) == "canada" { parts.removeLast() }
        return parts.joined(separator: ", ")
    }

    /// Première partie de l'adresse (numéro et rue).
    static func streetLine(of text: String) -> String {
        text.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? text
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
    }

    nonisolated(unsafe) private static let unitPattern =
        /(?i)[,\s]*(?:app\.?|apt\.?|appartement|unit[ée]|suite|bureau|local|#)\s*[0-9A-Za-z-]+/
}

// MARK: - Fake

/// Validateur fake pour les tests et les previews : rien sur le réseau.
/// Par défaut, accepte toute adresse avec un numéro civique et un nom de rue, sauf si elle contient « inexistant ».
nonisolated struct FakeAddressValidator: AddressValidating {
    /// Adresses connues (texte normalisé renvoyé), cherchées par numéro et rue.
    var known: [ValidatedAddress]
    var latency: Duration
    /// Simule une vérification impossible (hors ligne) : `validate` lève `AppError.offline`.
    var isOffline = false

    /// Saint-Michel, Montréal : position par défaut des adresses acceptées.
    static let defaultCoordinate = Geohash.Coordinate(latitude: 45.5600, longitude: -73.6100)

    static let montreal: [ValidatedAddress] = [
        ValidatedAddress(formatted: "7420 Avenue Ogilvy, Montréal QC H3N 1N4", streetLine: "7420 Avenue Ogilvy",
                         postalCode: "H3N 1N4", coordinate: .init(latitude: 45.5249, longitude: -73.6278)),
        ValidatedAddress(formatted: "8150 Boulevard Pie-IX, Montréal QC H1Z 3T6", streetLine: "8150 Boulevard Pie-IX",
                         postalCode: "H1Z 3T6", coordinate: .init(latitude: 45.5718, longitude: -73.6040)),
        ValidatedAddress(formatted: "1234 Rue Jarry E, Montréal QC H2R 1A1", streetLine: "1234 Rue Jarry E",
                         postalCode: "H2R 1A1", coordinate: .init(latitude: 45.5490, longitude: -73.6229)),
    ]

    init(known: [ValidatedAddress] = Self.montreal, latency: Duration = .zero, isOffline: Bool = false) {
        self.known = known
        self.latency = latency
        self.isOffline = isOffline
    }

    func suggestions(for query: String) async -> [AddressSuggestion] {
        await wait()
        let typedNumber = AddressMatching.civicNumber(in: query)
        let typedWords = AddressMatching.streetWords(in: query)
        guard typedNumber != nil || !typedWords.isEmpty else { return [] }
        return known
            .filter { address in
                if let typedNumber, AddressMatching.civicNumber(in: address.streetLine)?.hasPrefix(typedNumber) != true {
                    return false
                }
                let words = AddressMatching.streetWords(in: address.streetLine)
                return typedWords.allSatisfy { typed in words.contains { $0.hasPrefix(typed.prefix(4)) } }
            }
            .map { AddressSuggestion(title: $0.streetLine, subtitle: "Montréal, QC, Canada") }
    }

    func validate(_ text: String) async throws -> ValidatedAddress? {
        await wait()
        if isOffline { throw AppError.offline }
        if let found = known.first(where: { AddressMatching.matches(input: text, candidateStreetLine: $0.streetLine) }) {
            return found
        }
        let folded = AddressMatching.fold(text)
        guard !folded.contains("inexistant"), AddressMatching.civicNumber(in: text) != nil,
              !AddressMatching.streetWords(in: text).isEmpty else { return nil }
        let withoutUnit = AddressMatching.unitSuffix(in: text).map { text.replacingOccurrences(of: $0, with: "") } ?? text
        let line = AddressMatching.streetLine(of: withoutUnit).trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        return ValidatedAddress(formatted: "\(line), Montréal QC", streetLine: line,
                                postalCode: AddressMatching.postalCode(in: text), coordinate: Self.defaultCoordinate)
    }

    private func wait() async {
        if latency > .zero { try? await Task.sleep(for: latency) }
    }
}
