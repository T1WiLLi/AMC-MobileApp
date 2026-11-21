// GeohashDecoder.swift
// Décode un geohash (base 32, alphabet standard) en cellule : centre et étendue.
// Les modèles ne gardent que des geohash tronqués (jamais d'adresse exacte) : la carte
// s'en sert pour placer le centre d'un groupe et la position approximative des membres.

import CoreLocation

nonisolated enum GeohashDecoder {
    /// Cellule couverte par un geohash.
    struct Cell: Sendable, Hashable {
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2,
                                   longitude: (minLongitude + maxLongitude) / 2)
        }

        /// Point de la cellule aux fractions (0...1) données ; 0,5 et 0,5 = le centre.
        func point(latitudeFraction: Double, longitudeFraction: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: minLatitude + (maxLatitude - minLatitude) * min(max(latitudeFraction, 0), 1),
                longitude: minLongitude + (maxLongitude - minLongitude) * min(max(longitudeFraction, 0), 1)
            )
        }
    }

    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let values: [Character: Int] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) }
    )

    /// Cellule du geohash ; nil s'il est vide ou contient un caractère hors alphabet (a, i, l, o…).
    static func cell(for geohash: String) -> Cell? {
        let characters = geohash.lowercased()
        guard !characters.isEmpty else { return nil }
        var latitude = (-90.0, 90.0)
        var longitude = (-180.0, 180.0)
        var isLongitude = true
        for character in characters {
            guard let value = values[character] else { return nil }
            for shift in stride(from: 4, through: 0, by: -1) {
                let isUpper = (value >> shift) & 1 == 1
                if isLongitude {
                    let middle = (longitude.0 + longitude.1) / 2
                    if isUpper { longitude.0 = middle } else { longitude.1 = middle }
                } else {
                    let middle = (latitude.0 + latitude.1) / 2
                    if isUpper { latitude.0 = middle } else { latitude.1 = middle }
                }
                isLongitude.toggle()
            }
        }
        return Cell(minLatitude: latitude.0, maxLatitude: latitude.1,
                    minLongitude: longitude.0, maxLongitude: longitude.1)
    }

    /// Centre de la cellule du geohash ; nil s'il est invalide.
    static func coordinate(for geohash: String) -> CLLocationCoordinate2D? {
        cell(for: geohash)?.center
    }
}
