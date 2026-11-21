// Geohash.swift
// Petit décodeur geohash (base 32) pour placer les points de demande sur la carte V3.
// Les groupes et les lots stockent un geohash (ex. « f25dv » ≈ 5 km autour du centre-ville de Montréal).

import CoreLocation

nonisolated enum Geohash {
    /// Rectangle couvert par un geohash, en degrés.
    struct Bounds: Sendable, Equatable {
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            )
        }
    }

    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let values: [Character: Int] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) }
    )

    /// Rectangle du geohash ; nil s'il est vide ou contient un caractère hors base 32 (a, i, l, o).
    static func bounds(of hash: String) -> Bounds? {
        let characters = hash.lowercased()
        guard !characters.isEmpty else { return nil }
        var latitude = (-90.0, 90.0)
        var longitude = (-180.0, 180.0)
        var isLongitude = true
        for character in characters {
            guard let value = values[character] else { return nil }
            for bit in stride(from: 4, through: 0, by: -1) {
                let isUpperHalf = (value >> bit) & 1 == 1
                if isLongitude {
                    let middle = (longitude.0 + longitude.1) / 2
                    if isUpperHalf { longitude.0 = middle } else { longitude.1 = middle }
                } else {
                    let middle = (latitude.0 + latitude.1) / 2
                    if isUpperHalf { latitude.0 = middle } else { latitude.1 = middle }
                }
                isLongitude.toggle()
            }
        }
        return Bounds(minLatitude: latitude.0, maxLatitude: latitude.1, minLongitude: longitude.0, maxLongitude: longitude.1)
    }

    /// Centre du geohash, ou nil s'il est invalide.
    static func decode(_ hash: String) -> CLLocationCoordinate2D? {
        bounds(of: hash)?.center
    }
}
