// MontrealNeighborhood.swift
// RQ-015 : trouver le quartier d'un ménage à partir des 3 premiers caractères du code postal (RTA).
// On ne garde jamais l'adresse : seulement le nom du quartier et un geohash tronqué (≈ 5 km) de son centre.

import Foundation

nonisolated struct MontrealNeighborhood: Identifiable, Sendable, Hashable {
    /// Nom affiché et enregistré dans `AppUser.neighborhood` (« Saint-Michel »).
    let name: String
    /// Régions de tri d'acheminement (RTA) : 3 premiers caractères du code postal.
    let postalPrefixes: Set<String>
    let latitude: Double
    let longitude: Double

    var id: String { name }

    /// Geohash à 5 caractères du centre du quartier, pour `Household.geohash`.
    var geohash: String { Geohash.encode(latitude: latitude, longitude: longitude, precision: 5) }

    /// Résultat de la lecture d'un code postal.
    enum Lookup: Equatable, Sendable {
        /// Rien de saisi.
        case empty
        /// Saisie en cours (moins de 3 caractères utiles).
        case incomplete
        /// Ce n'est pas un code postal canadien.
        case invalid
        /// Code valide, mais hors des quartiers desservis.
        case notServed
        case found(MontrealNeighborhood)

        var neighborhood: MontrealNeighborhood? {
            if case .found(let neighborhood) = self { neighborhood } else { nil }
        }
    }

    /// Lit un code postal (« h2a 1b3 », « H2A1B3 », ou seulement « H2A ») et renvoie le quartier desservi.
    static func lookup(postalCode text: String) -> Lookup {
        let cleaned = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return .empty }
        let pattern: [Character.Kind] = [.letter, .digit, .letter, .digit, .letter, .digit]
        let isWellFormed = cleaned.count <= 6 && zip(cleaned, pattern).allSatisfy { $1.matches($0) }
        guard isWellFormed else { return .invalid }
        guard cleaned.count >= 3 else { return .incomplete }
        // Le quartier ne dépend que des 3 premiers caractères : on le montre dès qu'ils sont tapés.
        let prefix = String(cleaned.prefix(3))
        guard let match = all.first(where: { $0.postalPrefixes.contains(prefix) }) else { return .notServed }
        return .found(match)
    }

    /// Normalise un code complet en « H2A 1B3 » (laisse la saisie telle quelle sinon).
    static func formatted(postalCode text: String) -> String {
        let cleaned = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 6 else { return text.uppercased() }
        return "\(cleaned.prefix(3)) \(cleaned.suffix(3))"
    }

    static func named(_ name: String) -> MontrealNeighborhood? {
        all.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Quartiers desservis pour la démo, triés par nom. Centres approximatifs.
    static let all: [MontrealNeighborhood] = [
        .init(name: "Ahuntsic", postalPrefixes: ["H2C", "H2M", "H3L"], latitude: 45.555, longitude: -73.660),
        .init(name: "Centre-Sud", postalPrefixes: ["H2K", "H2L"], latitude: 45.522, longitude: -73.552),
        .init(name: "Côte-des-Neiges", postalPrefixes: ["H3S", "H3T", "H3V", "H3W"], latitude: 45.495, longitude: -73.625),
        .init(name: "Hochelaga", postalPrefixes: ["H1V", "H1W"], latitude: 45.548, longitude: -73.540),
        .init(name: "Mile End", postalPrefixes: ["H2V"], latitude: 45.523, longitude: -73.600),
        .init(name: "Montréal-Nord", postalPrefixes: ["H1G", "H1H"], latitude: 45.598, longitude: -73.630),
        .init(name: "Notre-Dame-de-Grâce", postalPrefixes: ["H4A", "H4B", "H3X"], latitude: 45.472, longitude: -73.613),
        .init(name: "Parc-Extension", postalPrefixes: ["H3N"], latitude: 45.530, longitude: -73.630),
        .init(name: "Petite-Patrie", postalPrefixes: ["H2G", "H2S"], latitude: 45.538, longitude: -73.600),
        .init(name: "Plateau-Mont-Royal", postalPrefixes: ["H2H", "H2J", "H2T", "H2W"], latitude: 45.522, longitude: -73.580),
        .init(name: "Pointe-Saint-Charles", postalPrefixes: ["H3K"], latitude: 45.481, longitude: -73.560),
        .init(name: "Rosemont", postalPrefixes: ["H1X", "H1Y", "H2E"], latitude: 45.552, longitude: -73.585),
        .init(name: "Saint-Henri", postalPrefixes: ["H4C"], latitude: 45.477, longitude: -73.585),
        .init(name: "Saint-Michel", postalPrefixes: ["H1Z", "H2A"], latitude: 45.565, longitude: -73.615),
        .init(name: "Verdun", postalPrefixes: ["H4E", "H4G", "H4H"], latitude: 45.457, longitude: -73.570),
        .init(name: "Villeray", postalPrefixes: ["H2P", "H2R"], latitude: 45.545, longitude: -73.625),
    ]
}

private extension Character {
    enum Kind { case letter, digit }
}

private extension Character.Kind {
    func matches(_ character: Character) -> Bool {
        switch self {
        case .letter: character.isASCII && character.isLetter
        case .digit: character.isASCII && character.isNumber
        }
    }
}
