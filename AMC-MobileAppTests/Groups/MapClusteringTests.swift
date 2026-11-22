import Foundation
import Testing
@testable import AMC_MobileApp

/// T-176 : regroupement des épingles de la carte selon l'écart à l'écran (donc selon le zoom).
/// Repère : Saint-Michel (45,56 N, −73,60). 0,0009° de latitude ≈ 100 m.
struct MapClusteringTests {
    private struct Pin: Identifiable, Sendable {
        let id: String
        let coordinate: Geohash.Coordinate
    }

    private static let base = Geohash.Coordinate(latitude: 45.56, longitude: -73.60)

    private func pin(_ id: String, north degrees: Double = 0, east lonDegrees: Double = 0) -> Pin {
        Pin(id: id, coordinate: Geohash.Coordinate(latitude: Self.base.latitude + degrees,
                                                   longitude: Self.base.longitude + lonDegrees))
    }

    /// iPhone en portrait (400 × 800 pt) montrant `latitudeDelta` degrés de haut.
    private func viewport(latitudeDelta: Double) -> MapClustering.Viewport {
        MapClustering.Viewport(latitudeDelta: latitudeDelta, longitudeDelta: latitudeDelta, width: 400, height: 800)
    }

    private func groups(_ pins: [Pin], latitudeDelta: Double?, spacing: Double = 46) -> [[String]] {
        MapClustering.clusters(pins, coordinate: \.coordinate,
                               viewport: latitudeDelta.map(viewport(latitudeDelta:)), minimumDistance: spacing)
            .map { $0.members.map(\.id) }
    }

    @Test func identicalCoordinatesAlwaysCluster() {
        let pins = [pin("a"), pin("b"), pin("c", north: 0.02)]
        // Même au zoom le plus fort, deux lieux au même endroit restent ensemble.
        #expect(groups(pins, latitudeDelta: 0.0005) == [["a", "b"], ["c"]])
        // Sans zone visible (avant le premier mouvement de carte), seuls les lieux identiques se regroupent.
        #expect(groups(pins, latitudeDelta: nil) == [["a", "b"], ["c"]])
    }

    @Test func closePinsClusterAndFarPinsDoNot() {
        // Quartier entier à l'écran (≈ 2,2 km de haut) : 10 m ≈ 4 pt → ensemble ; 500 m ≈ 180 pt → à part.
        let pins = [pin("pres", north: 0.00009), pin("ici"), pin("loin", north: 0.0045)]
        #expect(groups(pins, latitudeDelta: 0.02) == [["pres", "ici"], ["loin"]])
    }

    @Test func clustersSplitWhenZoomingIn() {
        let pins = [pin("a"), pin("b", north: 0.0009)]   // ≈ 100 m d'écart
        #expect(groups(pins, latitudeDelta: 0.02).count == 1)    // 36 pt : se chevauchent
        #expect(groups(pins, latitudeDelta: 0.005).count == 2)   // 144 pt : séparées
    }

    @Test func spacingFollowsPinSize() {
        // AX5 : épingles plus grosses → regroupement plus tôt.
        let pins = [pin("a"), pin("b", north: 0.0013)]   // 52 pt à ce zoom
        #expect(groups(pins, latitudeDelta: 0.02, spacing: 46).count == 2)
        #expect(groups(pins, latitudeDelta: 0.02, spacing: 76).count == 1)
    }

    @Test func clusteringIgnoresInputOrderAndKeepsItInsideGroups() {
        let pins = [pin("z"), pin("a", east: 0.0001), pin("m", north: 0.01)]
        let shuffled = [pins[2], pins[1], pins[0]]
        #expect(Set(groups(pins, latitudeDelta: 0.02).map(Set.init)) == Set(groups(shuffled, latitudeDelta: 0.02).map(Set.init)))
        // Les membres gardent l'ordre de la liste (du plus proche au plus loin sur la carte).
        #expect(groups(pins, latitudeDelta: 0.02).first == ["z", "a"])
    }

    @Test func clusterCenterAndStableId() throws {
        let clusters = MapClustering.clusters([pin("b", north: 0.0002), pin("a")], coordinate: \.coordinate,
                                              viewport: viewport(latitudeDelta: 0.02), minimumDistance: 46)
        let cluster = try #require(clusters.first)
        #expect(clusters.count == 1)
        #expect(cluster.id == "cluster:a|b")
        #expect(abs(cluster.coordinate.latitude - (Self.base.latitude + 0.0001)) < 1e-9)
        #expect(cluster.contains(id: "a") && !cluster.contains(id: "c") && !cluster.contains(id: nil))
        let single = MapClustering.clusters([pin("solo")], coordinate: \.coordinate, viewport: nil, minimumDistance: 46)
        #expect(single.first?.id == "solo" && single.first?.isSingle == true)
    }

    @Test func viewportOnlyChangesOnNoticeableZoom() {
        let current = viewport(latitudeDelta: 0.02)
        #expect(!viewport(latitudeDelta: 0.0202).differsNoticeably(from: current))
        #expect(viewport(latitudeDelta: 0.015).differsNoticeably(from: current))
        #expect(MapClustering.Viewport(latitudeDelta: 0, longitudeDelta: 0, width: 400, height: 800).pointsPerDegree == nil)
    }

    @Test func zoomRegionFramesMembersOrRefusesSameSpot() throws {
        #expect(MapClustering.zoomRegion(for: [pin("a").coordinate, pin("b").coordinate]) == nil)
        let a = pin("a").coordinate, b = pin("b", north: 0.0009, east: 0.0009).coordinate
        let region = try #require(MapClustering.zoomRegion(for: [a, b]))
        #expect(abs(region.center.latitude - (a.latitude + 0.00045)) < 1e-9)
        #expect(region.latitudeDelta >= 0.0027 - 1e-9 && region.longitudeDelta >= 0.0027 - 1e-9)
        // Au zoom proposé, les deux épingles ne se regroupent plus.
        let zoomed = MapClustering.Viewport(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta,
                                            width: 400, height: 800)
        #expect(MapClustering.clusters([pin("a"), pin("b", north: 0.0009, east: 0.0009)], coordinate: \.coordinate,
                                       viewport: zoomed, minimumDistance: 46).count == 2)
    }

    @Test func voiceOverLabelCountsPlacesByKind() throws {
        let data = FakeData.montreal
        let groups = Array(data.groups.prefix(2))
        let vendor = try #require(data.vendors.first)
        try #require(groups.count == 2)
        let places = groups.map { FamilyMapViewModel.Place(detail: .group($0, isMember: false), coordinate: Self.base) }
            + [FamilyMapViewModel.Place(detail: .producer(vendor, offerId: nil, openOfferCount: 0), coordinate: Self.base)]
        #expect(FamilyMapClusterText.title(count: places.count) == "3 lieux ici")
        #expect(FamilyMapClusterText.accessibilityLabel(for: places) == "3 lieux ici : 2 groupes, 1 producteur")
    }
}
