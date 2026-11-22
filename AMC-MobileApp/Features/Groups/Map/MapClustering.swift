// MapClustering.swift
// T-176 (retour samuel) : sur la carte, les lieux au même endroit ou trop proches à l'écran se regroupent en
// une seule épingle « pile ». Le regroupement se fait en points d'écran : il dépend du zoom (la zone visible et
// la taille de la carte), pas d'une distance fixe en mètres. En zoomant, les groupes se séparent ; deux lieux
// exactement au même endroit restent toujours ensemble (la feuille permet de choisir).
//
// Usage :
//   let viewport = MapClustering.Viewport(latitudeDelta: region.span.latitudeDelta,
//                                         longitudeDelta: region.span.longitudeDelta, width: size.width, height: size.height)
//   MapClustering.clusters(places, coordinate: \.coordinate, viewport: viewport, minimumDistance: 46)
//   → [MapCluster<Place>] ; `cluster.isSingle` → épingle normale, sinon épingle pile + feuille.

import Foundation

/// Un ou plusieurs éléments affichés à un même point de la carte.
nonisolated struct MapCluster<Element: Identifiable & Sendable>: Identifiable, Sendable where Element.ID == String {
    /// Dans l'ordre d'entrée (pour la carte : du plus proche au plus loin).
    let members: [Element]
    /// Centre des membres (moyenne des positions).
    let coordinate: Geohash.Coordinate

    /// L'id du lieu seul, ou « cluster: » + les ids triés : stable tant que le groupe ne change pas.
    var id: String {
        members.count == 1 ? members[0].id : "cluster:" + members.map(\.id).sorted().joined(separator: "|")
    }

    var isSingle: Bool { members.count == 1 }
    var count: Int { members.count }

    func contains(id: String?) -> Bool {
        guard let id else { return false }
        return members.contains { $0.id == id }
    }
}

nonisolated enum MapClustering {
    /// Ce que montre la carte : l'étendue de la zone visible (degrés) et la taille de la carte (points).
    struct Viewport: Sendable, Hashable {
        var latitudeDelta: Double
        var longitudeDelta: Double
        var width: Double
        var height: Double

        /// Points d'écran par degré, ou nil si la zone est dégénérée.
        var pointsPerDegree: (latitude: Double, longitude: Double)? {
            guard latitudeDelta > 0, longitudeDelta > 0, width > 0, height > 0,
                  latitudeDelta.isFinite, longitudeDelta.isFinite else { return nil }
            return (height / latitudeDelta, width / longitudeDelta)
        }

        /// Vrai si l'autre zone est assez différente pour refaire les groupes (évite de tout recalculer à
        /// chaque image d'un déplacement : seul le zoom compte, pas le centre).
        func differsNoticeably(from other: Viewport, tolerance: Double = 0.04) -> Bool {
            func far(_ a: Double, _ b: Double) -> Bool {
                guard a > 0, b > 0 else { return a != b }
                return abs(a - b) / max(a, b) > tolerance
            }
            return far(latitudeDelta, other.latitudeDelta) || far(longitudeDelta, other.longitudeDelta)
                || far(width, other.width) || far(height, other.height)
        }
    }

    /// Sous cette dispersion, les membres sont « au même endroit » : zoomer ne les séparerait pas.
    static let sameSpotMeters = 15.0

    /// Regroupe les éléments à moins de `minimumDistance` points d'écran les uns des autres.
    /// Glouton et déterministe : les éléments sont parcourus par id (le groupe ne dépend pas du tri de la
    /// liste), chacun rejoint le premier groupe dont l'ancre (son premier élément) est assez proche.
    /// Sans `viewport` exploitable, seuls les éléments exactement au même endroit sont regroupés.
    static func clusters<Element>(
        _ elements: [Element],
        coordinate: (Element) -> Geohash.Coordinate,
        viewport: Viewport?,
        minimumDistance: Double
    ) -> [MapCluster<Element>] {
        let scale = viewport?.pointsPerDegree
        func point(_ c: Geohash.Coordinate) -> (x: Double, y: Double) {
            guard let scale else { return (c.longitude, c.latitude) }
            return (c.longitude * scale.longitude, c.latitude * scale.latitude)
        }
        let threshold = scale == nil ? 1e-9 : max(0, minimumDistance)

        let order = elements.indices.sorted { elements[$0].id < elements[$1].id }
        var groups: [(anchor: (x: Double, y: Double), indices: [Int])] = []
        for index in order {
            let p = point(coordinate(elements[index]))
            if let g = groups.firstIndex(where: { hypot($0.anchor.x - p.x, $0.anchor.y - p.y) < threshold }) {
                groups[g].indices.append(index)
            } else {
                groups.append((p, [index]))
            }
        }

        return groups
            .map { $0.indices.sorted() }
            .sorted { $0[0] < $1[0] }
            .map { indices in
                let members = indices.map { elements[$0] }
                let coordinates = members.map(coordinate)
                let n = Double(coordinates.count)
                let center = Geohash.Coordinate(
                    latitude: coordinates.map(\.latitude).reduce(0, +) / n,
                    longitude: coordinates.map(\.longitude).reduce(0, +) / n
                )
                return MapCluster(members: members, coordinate: center)
            }
    }

    /// Zone à montrer pour séparer les membres d'un groupe (« Zoomer ici ») : leur rectangle, agrandi pour
    /// laisser de la marge. Nil s'ils sont au même endroit (`sameSpotMeters`) : zoomer ne servirait à rien.
    static func zoomRegion(for coordinates: [Geohash.Coordinate])
        -> (center: Geohash.Coordinate, latitudeDelta: Double, longitudeDelta: Double)? {
        guard let first = coordinates.first else { return nil }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let minC = Geohash.Coordinate(latitude: lats.min() ?? first.latitude, longitude: lons.min() ?? first.longitude)
        let maxC = Geohash.Coordinate(latitude: lats.max() ?? first.latitude, longitude: lons.max() ?? first.longitude)
        guard Geohash.distanceMeters(from: minC, to: maxC) >= sameSpotMeters else { return nil }
        let center = Geohash.Coordinate(latitude: (minC.latitude + maxC.latitude) / 2,
                                        longitude: (minC.longitude + maxC.longitude) / 2)
        // Marge ×3 : les épingles (≈ 46 pt) doivent tenir côte à côte. Au moins ≈ 200 m de côté.
        let minimumDelta = 0.0018
        return (center,
                max((maxC.latitude - minC.latitude) * 3, minimumDelta),
                max((maxC.longitude - minC.longitude) * 3, minimumDelta))
    }
}
