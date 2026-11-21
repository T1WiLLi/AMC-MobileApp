// NeighborhoodMap.swift
// Carte d'un groupe de quartier (maquette F2) : zone du groupe, point de cueillette,
// membres en points anonymes. Mode aperçu (non interactif, dans une carte ou un en-tête)
// ou plein écran (interactif, contrôles en verre).
//
// Usage :
//   NeighborhoodMap(group: group, pickupPoint: point, pickupCoordinate: coord, memberGeohashes: households.map(\.geohash))
//       .frame(height: 280)
//   NeighborhoodMap(group: group, …, mode: .interactive)   // dans une sheet ou un écran poussé

import MapKit
import SwiftUI

struct NeighborhoodMap: View {
    enum Mode: Sendable {
        /// Aperçu figé : pas de geste, pas de contrôle, un seul élément VoiceOver.
        case preview
        /// Plein écran : gestes, position de l'utilisateur, boussole et échelle.
        case interactive
    }

    let center: CLLocationCoordinate2D
    let radiusMeters: Int
    let pickupCoordinate: CLLocationCoordinate2D?
    /// Positions approximatives (jamais d'adresse exacte) ; voir `NeighborhoodMapLayout.anonymousPositions`.
    let memberPositions: [CLLocationCoordinate2D]
    let mode: Mode
    let accessibilitySummary: String

    @ScaledMetric(relativeTo: .title3) private var pinSize: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var memberDotSize: CGFloat = 9
    @State private var position: MapCameraPosition

    init(center: CLLocationCoordinate2D, radiusMeters: Int, pickupCoordinate: CLLocationCoordinate2D?,
         memberPositions: [CLLocationCoordinate2D] = [], mode: Mode = .preview, accessibilitySummary: String) {
        self.center = center
        self.radiusMeters = radiusMeters
        self.pickupCoordinate = pickupCoordinate
        self.memberPositions = memberPositions
        self.mode = mode
        self.accessibilitySummary = accessibilitySummary
        _position = State(initialValue: NeighborhoodMapLayout.camera(center: center, radiusMeters: radiusMeters))
    }

    /// À partir des modèles : centre décodé du geohash du groupe (ou `centerOverride`), membres anonymisés.
    init(group: NeighborhoodGroup, pickupPoint: PickupPoint?, pickupCoordinate: CLLocationCoordinate2D?,
         memberGeohashes: [String] = [], centerOverride: CLLocationCoordinate2D? = nil, mode: Mode = .preview) {
        let center = centerOverride
            ?? GeohashDecoder.coordinate(for: group.centerGeohash)
            ?? pickupCoordinate
            ?? NeighborhoodMapLayout.montreal
        self.init(
            center: center,
            radiusMeters: group.radiusMeters,
            pickupCoordinate: pickupCoordinate,
            memberPositions: NeighborhoodMapLayout.anonymousPositions(
                memberGeohashes: memberGeohashes, center: center, radiusMeters: group.radiusMeters),
            mode: mode,
            accessibilitySummary: NeighborhoodMapLayout.summary(group: group, pickupAddress: pickupPoint?.address)
        )
    }

    var body: some View {
        map
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                if mode == .interactive {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
            }
            .modifier(MapAccessibility(mode: mode, summary: accessibilitySummary))
    }

    @ViewBuilder private var map: some View {
        switch mode {
        case .preview:
            Map(initialPosition: position, interactionModes: []) { content }
                .allowsHitTesting(false)
        case .interactive:
            Map(position: $position, interactionModes: .all) {
                content
                UserAnnotation()
            }
        }
    }

    @MapContentBuilder private var content: some MapContent {
        MapCircle(center: center, radius: CLLocationDistance(radiusMeters))
            .foregroundStyle(Color.grenier.opacity(0.14))
            .stroke(Color.grenier.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

        ForEach(Array(memberPositions.enumerated()), id: \.offset) { _, coordinate in
            Annotation("", coordinate: coordinate, anchor: .center) {
                Circle()
                    .fill(Color.grenier.opacity(0.75))
                    .frame(width: memberDotSize, height: memberDotSize)
                    .overlay(Circle().stroke(Color.surface, lineWidth: 1.5))
                    .accessibilityHidden(true)
            }
            .annotationTitles(.hidden)
        }

        if let pickupCoordinate {
            Annotation("Point de cueillette", coordinate: pickupCoordinate, anchor: .bottom) {
                PickupPin(size: pinSize)
            }
            .annotationTitles(.hidden)
        }
    }
}

/// Pastille Grenier du point de cueillette, avec sa petite tige (maquette F2).
private struct PickupPin: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "basket.fill")
                .font(.headline)
                .foregroundStyle(Color.onAccent)
                .frame(width: size, height: size)
                .background(Color.grenier, in: .rect(cornerRadius: size * 0.32))
                .padding(3)
                .background(Color.surface, in: .rect(cornerRadius: size * 0.32 + 3))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            Capsule()
                .fill(Color.grenier)
                .frame(width: 3, height: size * 0.22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Point de cueillette")
    }
}

/// Aperçu : un seul élément VoiceOver avec le résumé. Plein écran : le résumé sur le conteneur, contrôles accessibles.
private struct MapAccessibility: ViewModifier {
    let mode: NeighborhoodMap.Mode
    let summary: String

    func body(content: Content) -> some View {
        switch mode {
        case .preview:
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Carte du quartier")
                .accessibilityValue(summary)
                .accessibilityAddTraits(.isImage)
        case .interactive:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Carte du quartier : \(summary)")
        }
    }
}

/// Calculs de la carte, sans vue (testés).
nonisolated enum NeighborhoodMapLayout {
    static let montreal = CLLocationCoordinate2D(latitude: 45.5019, longitude: -73.5674)
    private static let metersPerDegree = 111_320.0

    /// Cadre qui montre tout le cercle avec une marge.
    static func camera(center: CLLocationCoordinate2D, radiusMeters: Int) -> MapCameraPosition {
        let span = Double(max(radiusMeters, 100)) * 2.6
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span))
    }

    /// « Parc-Ex Ouest, 24 familles, rayon de 1,5 km, point de cueillette rue Ogilvy »
    static func summary(group: NeighborhoodGroup, pickupAddress: String?) -> String {
        var parts = [group.name, familiesText(group.householdCount), "rayon de \(distanceText(group.radiusMeters))"]
        if let pickupAddress, let street = streetLabel(from: pickupAddress) {
            parts.append("point de cueillette \(street)")
        }
        return parts.joined(separator: ", ")
    }

    static func familiesText(_ count: Int) -> String {
        "\(count) \(count > 1 ? "familles" : "famille")"
    }

    /// « 450 m », « 1,5 km ».
    static func distanceText(_ meters: Int) -> String {
        if meters < 1_000 { return "\(meters) m" }
        let kilometers = Double(meters) / 1_000
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .locale(Locale(identifier: "fr_CA"))
        return kilometers.formatted(format) + " km"
    }

    /// « 7420 rue Ogilvy, Montréal » → « rue Ogilvy » (sans numéro civique).
    static func streetLabel(from address: String) -> String? {
        let firstLine = address.split(separator: ",").first.map(String.init) ?? address
        let street = firstLine
            .drop { $0.isNumber || $0.isWhitespace || $0 == "-" }
            .trimmingCharacters(in: .whitespaces)
        return street.isEmpty ? nil : street
    }

    /// Positions anonymes des membres : chaque geohash (déjà tronqué) donne une cellule ; les membres
    /// sont répartis en spirale autour du centre de leur cellule, ramené dans le cercle du groupe.
    /// Déterministe (pas d'aléa), toujours à l'intérieur du rayon, jamais une adresse.
    static func anonymousPositions(memberGeohashes: [String], center: CLLocationCoordinate2D,
                                   radiusMeters: Int) -> [CLLocationCoordinate2D] {
        let radius = Double(max(radiusMeters, 50))
        let cells = memberGeohashes.compactMap(GeohashDecoder.cell(for:))
        guard !cells.isEmpty else { return [] }
        let goldenAngle = Double.pi * (3 - 5.squareRoot())
        let spread = radius * 0.4

        return cells.enumerated().map { index, cell in
            // Centre de la cellule, en mètres depuis le centre du groupe, ramené à 45 % du rayon.
            var anchor = offsetMeters(from: center, to: cell.center)
            let anchorDistance = hypot(anchor.east, anchor.north)
            let maxAnchor = radius * 0.45
            if anchorDistance > maxAnchor {
                anchor = (anchor.east * maxAnchor / anchorDistance, anchor.north * maxAnchor / anchorDistance)
            }
            // Spirale de Vogel : répartition régulière, sans superposition.
            let distance = spread * ((Double(index) + 0.5) / Double(cells.count)).squareRoot()
            let angle = Double(index) * goldenAngle
            let east = anchor.east + distance * cos(angle)
            let north = anchor.north + distance * sin(angle)
            return coordinate(from: center, east: east, north: north)
        }
    }

    static func offsetMeters(from origin: CLLocationCoordinate2D,
                             to point: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        let north = (point.latitude - origin.latitude) * metersPerDegree
        let east = (point.longitude - origin.longitude) * metersPerDegree * cos(origin.latitude * .pi / 180)
        return (east, north)
    }

    static func coordinate(from origin: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origin.latitude + north / metersPerDegree,
            longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
        )
    }
}

#if DEBUG
/// Groupe Parc-Ex Ouest de la maquette F2.
enum NeighborhoodMapPreviewData {
    static let center = CLLocationCoordinate2D(latitude: 45.5300, longitude: -73.6320)
    static let pickupCoordinate = CLLocationCoordinate2D(latitude: 45.5306, longitude: -73.6296)
    static let group = NeighborhoodGroup(
        id: "parc-ex-ouest", name: "Parc-Ex Ouest", neighborhood: "Parc-Extension", centerGeohash: "f25eh2q",
        radiusMeters: 1_500, coordinatorIds: ["fatima"], householdCount: 24, isPublic: true, inviteCode: "PARCEX"
    )
    static let memberGeohashes = ["f25eh2", "f25eh8", "f25eh3", "f25eh0", "f25eh9", "f25eh2", "f25eh1",
                                  "f25eh8", "f25eh2", "f25eh3", "f25eh0", "f25eh2"]

    static var pickupPoint: PickupPoint {
        let calendar = Calendar(identifier: .gregorian)
        let thursday = calendar.nextDate(after: .now, matching: DateComponents(hour: 17, weekday: 5),
                                         matchingPolicy: .nextTime) ?? .now
        return PickupPoint(
            id: "pickup-ogilvy", hostUserId: "fatima", name: "Chez Fatima", address: "7420 rue Ogilvy, Montréal",
            photoURL: nil, capacity: 30, accessibility: [.stepFree, .nearMetro],
            slots: [PickupSlot(start: thursday, end: thursday.addingTimeInterval(90 * 60))]
        )
    }

    static func map(mode: NeighborhoodMap.Mode = .preview) -> NeighborhoodMap {
        NeighborhoodMap(group: group, pickupPoint: pickupPoint, pickupCoordinate: pickupCoordinate,
                        memberGeohashes: memberGeohashes, mode: mode)
    }
}

#Preview("Aperçu clair") {
    NeighborhoodMapPreviewData.map()
        .frame(height: 280)
        .clipShape(.rect(cornerRadius: 24))
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
}

#Preview("Plein écran sombre") {
    NeighborhoodMapPreviewData.map(mode: .interactive)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NeighborhoodMapPreviewData.map()
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 24))
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}
#endif
