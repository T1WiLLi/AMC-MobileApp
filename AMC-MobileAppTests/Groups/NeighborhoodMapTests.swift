import CoreLocation
import Foundation
import Testing
@testable import AMC_MobileApp

struct GeohashDecoderTests {
    @Test func decodesKnownGeohash() throws {
        // Exemple de référence : « ezs42 » ≈ 42,605, −5,603.
        let center = try #require(GeohashDecoder.coordinate(for: "ezs42"))
        #expect(abs(center.latitude - 42.605) < 0.01)
        #expect(abs(center.longitude - -5.603) < 0.01)
    }

    @Test func decodesLongGeohashPrecisely() throws {
        let center = try #require(GeohashDecoder.coordinate(for: "u4pruydqqvj"))
        #expect(abs(center.latitude - 57.64911) < 0.0001)
        #expect(abs(center.longitude - 10.40744) < 0.0001)
    }

    @Test func parcExIsInMontreal() throws {
        let cell = try #require(GeohashDecoder.cell(for: "f25eh2q"))
        #expect(cell.minLatitude <= 45.5300 && 45.5300 <= cell.maxLatitude)
        #expect(cell.minLongitude <= -73.6320 && -73.6320 <= cell.maxLongitude)
    }

    @Test func isCaseInsensitive() {
        #expect(GeohashDecoder.cell(for: "F25DV") == GeohashDecoder.cell(for: "f25dv"))
    }

    @Test func rejectsInvalidGeohash() {
        #expect(GeohashDecoder.cell(for: "") == nil)
        #expect(GeohashDecoder.cell(for: "f25a") == nil)   // « a » hors alphabet
        #expect(GeohashDecoder.cell(for: "f2 5") == nil)
    }

    @Test func longerGeohashIsSmallerCell() throws {
        let short = try #require(GeohashDecoder.cell(for: "f25"))
        let long = try #require(GeohashDecoder.cell(for: "f25dv"))
        #expect(long.maxLatitude - long.minLatitude < short.maxLatitude - short.minLatitude)
        #expect(short.minLatitude <= long.minLatitude && long.maxLatitude <= short.maxLatitude)
    }
}

struct NeighborhoodMapLayoutTests {
    let center = CLLocationCoordinate2D(latitude: 45.5300, longitude: -73.6320)
    let group = NeighborhoodGroup(
        id: "parc-ex-ouest", name: "Parc-Ex Ouest", neighborhood: "Parc-Extension", centerGeohash: "f25eh2q",
        radiusMeters: 1_500, coordinatorIds: [], householdCount: 24, isPublic: true, inviteCode: "PARCEX"
    )

    @Test func voiceOverSummaryMatchesMockup() {
        #expect(NeighborhoodMapLayout.summary(group: group, pickupAddress: "7420 rue Ogilvy, Montréal")
            == "Parc-Ex Ouest, 24 familles, rayon de 1,5 km, point de cueillette rue Ogilvy")
        #expect(NeighborhoodMapLayout.summary(group: group, pickupAddress: nil)
            == "Parc-Ex Ouest, 24 familles, rayon de 1,5 km")
    }

    @Test func distanceText() {
        #expect(NeighborhoodMapLayout.distanceText(450) == "450 m")
        #expect(NeighborhoodMapLayout.distanceText(1_500) == "1,5 km")
        #expect(NeighborhoodMapLayout.distanceText(2_000) == "2 km")
    }

    @Test func streetLabelDropsCivicNumber() {
        #expect(NeighborhoodMapLayout.streetLabel(from: "7420 rue Ogilvy") == "rue Ogilvy")
        #expect(NeighborhoodMapLayout.streetLabel(from: "Rue Jarry Est, Saint-Michel") == "Rue Jarry Est")
        #expect(NeighborhoodMapLayout.streetLabel(from: "12-14 avenue Querbes") == "avenue Querbes")
        #expect(NeighborhoodMapLayout.streetLabel(from: "7420") == nil)
    }

    @Test func membersStayInsideRadius() {
        // Cellules larges (précision 5, ≈ 5 km) : les membres restent quand même dans le cercle.
        let geohashes = Array(repeating: "f25dv", count: 20) + ["f25eh2", "f25eh8", "f25ej"]
        let positions = NeighborhoodMapLayout.anonymousPositions(memberGeohashes: geohashes, center: center, radiusMeters: 1_500)
        #expect(positions.count == geohashes.count)
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        for position in positions {
            let distance = origin.distance(from: CLLocation(latitude: position.latitude, longitude: position.longitude))
            #expect(distance <= 1_500)
        }
    }

    @Test func membersAreSpreadAndDeterministic() {
        let geohashes = Array(repeating: "f25eh2", count: 8)
        let first = NeighborhoodMapLayout.anonymousPositions(memberGeohashes: geohashes, center: center, radiusMeters: 1_500)
        let second = NeighborhoodMapLayout.anonymousPositions(memberGeohashes: geohashes, center: center, radiusMeters: 1_500)
        #expect(first.map(\.latitude) == second.map(\.latitude))
        // Même cellule : aucun point superposé.
        let keys = Set(first.map { "\(Int($0.latitude * 100_000)),\(Int($0.longitude * 100_000))" })
        #expect(keys.count == geohashes.count)
    }

    @Test func invalidGeohashesAreSkipped() {
        let positions = NeighborhoodMapLayout.anonymousPositions(memberGeohashes: ["f25eh2", "zzai", ""], center: center, radiusMeters: 1_000)
        #expect(positions.count == 1)
    }
}

@MainActor
struct PickupPointCardTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        return calendar
    }

    func slot() -> PickupSlot {
        // Jeudi 26 novembre 2026, 17 h – 18 h 30 (Montréal).
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 17))!
        return PickupSlot(start: start, end: start.addingTimeInterval(90 * 60))
    }

    func point(accessibility: [PickupPoint.Accessibility] = [.stepFree, .nearMetro]) -> PickupPoint {
        PickupPoint(id: "p", hostUserId: "fatima", name: "Chez Fatima", address: "7420 rue Ogilvy, Montréal",
                    photoURL: nil, capacity: 30, accessibility: accessibility, slots: [slot()])
    }

    @Test func slotTextMatchesMockup() {
        #expect(PickupPointFormatting.slotText(slot(), calendar: calendar) == "Jeudi, 17 h – 18 h 30")
    }

    @Test func accessibilityText() {
        #expect(PickupPointFormatting.accessibilityText([.stepFree, .nearMetro]) == "Sans marches · Près du métro")
        #expect(PickupPointFormatting.label(for: .wheelchair) == "Accessible en fauteuil roulant")
    }

    @Test func titleAndSubtitle() {
        let card = PickupPointCard(point: point(), hostName: "Fatima", distanceMeters: 450)
        #expect(card.title == "Chez Fatima, 7420 rue Ogilvy")
        #expect(card.placeSubtitle == "Point de cueillette · 450 m à pied")
        let anonymous = PickupPointCard(point: point())
        #expect(anonymous.title == "Chez Fatima, 7420 rue Ogilvy")
        #expect(anonymous.placeSubtitle == "Point de cueillette")
    }

    @Test func mapItemUsesCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.5306, longitude: -73.6296)
        let item = PickupPointFormatting.mapItem(name: "Chez Fatima", address: "7420 rue Ogilvy, Montréal", coordinate: coordinate)
        #expect(item.name == "Chez Fatima")
        #expect(abs(item.location.coordinate.latitude - 45.5306) < 0.0001)
    }

    @Test func directionsURLWithoutCoordinate() throws {
        let url = try #require(PickupPointFormatting.directionsURL(address: "7420 rue Ogilvy, Montréal"))
        #expect(url.scheme == "maps")
        #expect(url.absoluteString.contains("dirflg=w"))
        #expect(url.absoluteString.contains("Ogilvy"))
    }
}
