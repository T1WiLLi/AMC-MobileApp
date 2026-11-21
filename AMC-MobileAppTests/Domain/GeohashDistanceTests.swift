import Foundation
import Testing
@testable import AMC_MobileApp

/// T-063 : extension Geohash (encodage, cellule, distances, voisins). Le décodage de base est testé dans `Vendor/GeohashTests`.
struct GeohashDistanceTests {
    private func isClose(_ value: Double, _ expected: Double, tolerance: Double) -> Bool {
        abs(value - expected) <= tolerance
    }

    // MARK: Encodage

    @Test func encodesReferenceVectors() {
        #expect(Geohash.encode(latitude: 42.6, longitude: -5.6, precision: 5) == "ezs42")
        #expect(Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11) == "u4pruydqqvj")
        // Centre-ville de Montréal.
        #expect(Geohash.encode(latitude: 45.5017, longitude: -73.5673, precision: 7) == "f25dvgm")
        #expect(Geohash.encode(latitude: 45.5017, longitude: -73.5673, precision: 5) == "f25dv")
    }

    @Test func encodeClampsPrecisionAndCoordinates() {
        #expect(Geohash.encode(latitude: 42.6, longitude: -5.6, precision: 0).count == 1)
        #expect(Geohash.encode(latitude: 42.6, longitude: -5.6, precision: 40).count == 12)
        #expect(Geohash.encode(latitude: 120, longitude: 0, precision: 3) == Geohash.encode(latitude: 90, longitude: 0, precision: 3))
        #expect(Geohash.encode(latitude: 42.6, longitude: 354.4, precision: 5) == "ezs42")
    }

    // MARK: Décodage

    @Test func decodesCenterAndBounds() throws {
        let cell = try #require(Geohash.cell(of: "ezs42"))
        #expect(isClose(cell.center.latitude, 42.605, tolerance: 0.001))
        #expect(isClose(cell.center.longitude, -5.603, tolerance: 0.001))
        #expect(cell.bounds.minLatitude == 42.5830078125)
        #expect(cell.bounds.maxLatitude == 42.626953125)
        #expect(cell.bounds.minLongitude == -5.625)
        #expect(cell.bounds.maxLongitude == -5.5810546875)
        #expect(cell.contains(Geohash.Coordinate(latitude: 42.6, longitude: -5.6)))

        let montreal = try #require(Geohash.center(of: "f25dv"))
        #expect(isClose(montreal.latitude, 45.5054, tolerance: 0.0001))
        #expect(isClose(montreal.longitude, -73.5864, tolerance: 0.0001))
    }

    @Test func decodeIsCaseInsensitiveAndRejectsInvalidInput() {
        #expect(Geohash.cell(of: "EZS42") == Geohash.cell(of: "ezs42"))
        #expect(Geohash.cell(of: "") == nil)
        #expect(Geohash.cell(of: "ezs4a") == nil)  // « a » n'est pas dans l'alphabet
        #expect(Geohash.cell(of: "f25dvf25dvf25") == nil)  // 13 caractères
        #expect(!Geohash.isValid("ilo"))
        #expect(Geohash.isValid("f25dv"))
    }

    @Test func encodeThenDecodeStaysInTheCell() throws {
        let point = Geohash.Coordinate(latitude: 45.5631, longitude: -73.6107)
        for precision in 1...12 {
            let cell = try #require(Geohash.cell(of: Geohash.encode(point, precision: precision)))
            #expect(cell.contains(point))
            #expect(cell.geohash.count == precision)
        }
    }

    // MARK: Distances

    @Test func haversineMatchesKnownDistances() {
        let montreal = Geohash.Coordinate(latitude: 45.5017, longitude: -73.5673)
        let quebec = Geohash.Coordinate(latitude: 46.8139, longitude: -71.2080)
        #expect(isClose(Geohash.distanceMeters(from: montreal, to: quebec), 233_000, tolerance: 2_000))
        #expect(Geohash.distanceMeters(from: montreal, to: montreal) == 0)
        // Un degré de latitude ≈ 111,2 km.
        let a = Geohash.Coordinate(latitude: 0, longitude: 0), b = Geohash.Coordinate(latitude: 1, longitude: 0)
        #expect(isClose(Geohash.distanceMeters(from: a, to: b), 111_195, tolerance: 10))
    }

    @Test func distanceBetweenGeohashes() throws {
        // Saint-Michel (f25dv) → Hochelaga (f25ej) : une cellule plus au nord, ≈ 4,9 km.
        let distance = try #require(Geohash.distanceMeters(from: "f25dv", to: "f25ej"))
        #expect(isClose(distance, 4_887, tolerance: 5))
        #expect(Geohash.distanceMeters(from: "f25dv", to: "f25dv") == 0)
        #expect(Geohash.distanceMeters(from: "f25dv", to: "nope!") == nil)

        let fromCoordinate = try #require(Geohash.distanceMeters(
            from: Geohash.Coordinate(latitude: 45.50537109375, longitude: -73.58642578125), to: "f25dvk"
        ))
        #expect(isClose(fromCoordinate, 526, tolerance: 2))
    }

    // MARK: Voisins

    @Test func neighborsSurroundTheCell() {
        let neighbors = Geohash.neighbors(of: "f25dv")
        #expect(neighbors.count == 8)
        #expect(Set(neighbors).count == 8)
        #expect(!neighbors.contains("f25dv"))
        #expect(neighbors.first == "f25ej")  // nord
        #expect(neighbors.contains("f25dy"))  // est
        #expect(neighbors.contains("f25dt"))  // sud
        #expect(neighbors.contains("f25du"))  // ouest
        #expect(neighbors.allSatisfy { $0.count == 5 })
        #expect(Geohash.neighbors(of: "??").isEmpty)
    }

    @Test func neighborsWrapAroundTheAntimeridianAndStopAtThePoles() {
        // Cellule collée au 180e méridien : ses voisins de l'est sont de l'autre côté (longitude ≈ -180).
        let east = Geohash.encode(latitude: 0.1, longitude: 179.99, precision: 3)
        let eastNeighbors = Geohash.neighbors(of: east)
        #expect(eastNeighbors.count == 8)
        #expect(eastNeighbors.contains(Geohash.encode(latitude: 0.1, longitude: -179.99, precision: 3)))

        let north = Geohash.encode(latitude: 89.99, longitude: 0, precision: 2)
        #expect(Geohash.neighbors(of: north).count == 5)
    }
}
