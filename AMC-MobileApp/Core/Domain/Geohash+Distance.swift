// Geohash+Distance.swift
// Extension du décodeur `Geohash` (Features/Vendor/Geohash.swift) pour T-063 : encoder une position,
// cellule décodée, distances (haversine), cellules voisines. Sert aux groupes à proximité (RQ-023).
// Le décodage reste celui de `Geohash.bounds(of:)` ; les calculs se font en `Geohash.Coordinate` (pur Swift).
//
// Usage :
//   Geohash.encode(latitude: 45.5017, longitude: -73.5673, precision: 7)   // "f25dvgm"
//   Geohash.cell(of: "f25dv")?.center                                      // Coordinate(45.505, -73.586)
//   Geohash.distanceMeters(from: "f25dv", to: "f25ej")                     // ≈ 4 887 m
//   Geohash.neighbors(of: "f25dv")                                         // 8 cellules autour

import CoreLocation
import Foundation

nonisolated extension Geohash {
    /// Position en degrés décimaux.
    nonisolated struct Coordinate: Sendable, Hashable {
        var latitude: Double
        var longitude: Double

        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        init(_ coordinate: CLLocationCoordinate2D) {
            self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    /// Cellule décodée : son geohash, son rectangle et son centre.
    nonisolated struct Cell: Sendable, Equatable {
        var geohash: String
        var bounds: Bounds

        var center: Coordinate {
            Coordinate(latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                       longitude: (bounds.minLongitude + bounds.maxLongitude) / 2)
        }
        /// Hauteur de la cellule, en degrés de latitude.
        var latitudeSpan: Double { bounds.maxLatitude - bounds.minLatitude }
        /// Largeur de la cellule, en degrés de longitude.
        var longitudeSpan: Double { bounds.maxLongitude - bounds.minLongitude }

        func contains(_ coordinate: Coordinate) -> Bool {
            (bounds.minLatitude...bounds.maxLatitude).contains(coordinate.latitude)
                && (bounds.minLongitude...bounds.maxLongitude).contains(coordinate.longitude)
        }
    }

    /// Rayon moyen de la Terre (mètres), pour la formule de haversine.
    static let earthRadiusMeters = 6_371_008.8
    /// Précision maximale acceptée (12 ≈ 3,7 cm × 1,9 cm).
    static let maxPrecision = 12

    /// Base 32 des geohash, pour l'encodage (le décodage passe par `bounds(of:)`).
    private static let encodingCharacters: [Character] = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    // MARK: Encodage / cellule

    /// Geohash de `precision` caractères (borné entre 1 et 12) pour la position.
    /// La latitude est bornée à ±90 ; la longitude est ramenée dans [-180, 180].
    static func encode(_ coordinate: Coordinate, precision: Int = 7) -> String {
        let precision = min(max(precision, 1), maxPrecision)
        let latitude = min(max(coordinate.latitude, -90), 90)
        let longitude = normalizedLongitude(coordinate.longitude)
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var result = ""
        var isLongitudeBit = true
        var bitCount = 0
        var value = 0
        while result.count < precision {
            if isLongitudeBit {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid { value = value << 1 | 1; lonRange.0 = mid } else { value <<= 1; lonRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid { value = value << 1 | 1; latRange.0 = mid } else { value <<= 1; latRange.1 = mid }
            }
            isLongitudeBit.toggle()
            bitCount += 1
            if bitCount == 5 {
                result.append(encodingCharacters[value])
                bitCount = 0
                value = 0
            }
        }
        return result
    }

    static func encode(latitude: Double, longitude: Double, precision: Int = 7) -> String {
        encode(Coordinate(latitude: latitude, longitude: longitude), precision: precision)
    }

    /// Cellule du geohash (insensible à la casse) ; nil s'il est vide, trop long (plus de 12)
    /// ou contient un caractère hors base 32.
    static func cell(of geohash: String) -> Cell? {
        guard geohash.count <= maxPrecision, let bounds = bounds(of: geohash) else { return nil }
        return Cell(geohash: geohash.lowercased(), bounds: bounds)
    }

    /// Centre de la cellule ; nil si le geohash est invalide.
    static func center(of geohash: String) -> Coordinate? { cell(of: geohash)?.center }

    static func isValid(_ geohash: String) -> Bool { cell(of: geohash) != nil }

    // MARK: Distances

    /// Distance à vol d'oiseau (haversine), en mètres.
    static func distanceMeters(from origin: Coordinate, to destination: Coordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(haversine)))
    }

    /// Distance entre les centres de deux cellules ; nil si un geohash est invalide.
    static func distanceMeters(from origin: String, to destination: String) -> Double? {
        guard let origin = center(of: origin), let destination = center(of: destination) else { return nil }
        return distanceMeters(from: origin, to: destination)
    }

    /// Distance entre une position et le centre d'une cellule ; nil si le geohash est invalide.
    static func distanceMeters(from origin: Coordinate, to destination: String) -> Double? {
        guard let destination = center(of: destination) else { return nil }
        return distanceMeters(from: origin, to: destination)
    }

    // MARK: Voisins

    /// Les 8 cellules de même précision autour du geohash (N, NE, E, SE, S, SO, O, NO), sans doublon ;
    /// moins de 8 près des pôles. Vide si le geohash est invalide.
    static func neighbors(of geohash: String) -> [String] {
        guard let cell = cell(of: geohash) else { return [] }
        let precision = cell.geohash.count
        let center = cell.center
        let offsets: [(Double, Double)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        var result: [String] = []
        for (dLat, dLon) in offsets {
            let latitude = center.latitude + dLat * cell.latitudeSpan
            // Au-delà d'un pôle, il n'y a pas de voisin.
            guard latitude > -90, latitude < 90 else { continue }
            let neighbor = encode(latitude: latitude, longitude: center.longitude + dLon * cell.longitudeSpan,
                                  precision: precision)
            if neighbor != cell.geohash, !result.contains(neighbor) { result.append(neighbor) }
        }
        return result
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        guard longitude < -180 || longitude > 180 else { return longitude }
        var value = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value - 180
    }
}
