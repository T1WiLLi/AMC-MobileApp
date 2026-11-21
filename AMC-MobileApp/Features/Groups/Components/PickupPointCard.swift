// PickupPointCard.swift
// Carte du point de cueillette d'un groupe (maquette F2) : hôte et adresse, distance à pied,
// créneau, accessibilité, et bouton verre « Itinéraire » qui ouvre Plans.
//
// Usage :
//   PickupPointCard(point: point, hostName: "Fatima", distanceMeters: 450, coordinate: coord)

import MapKit
import SwiftUI

struct PickupPointCard: View {
    let point: PickupPoint
    /// Prénom de l'hôte (« Fatima ») ; nil = le nom du point.
    var hostName: String?
    var distanceMeters: Int?
    /// Coordonnée du point ; nil = Plans cherche l'adresse.
    var coordinate: CLLocationCoordinate2D?

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(symbol: "mappin.and.ellipse", title: title, subtitle: placeSubtitle)
            Divider().overlay(Color.piste)
            if let slot = point.slots.first {
                row(symbol: "clock", title: PickupPointFormatting.slotText(slot), subtitle: slotSubtitle)
                Divider().overlay(Color.piste)
            }
            if !point.accessibility.isEmpty {
                row(symbol: "figure.roll", title: PickupPointFormatting.accessibilityText(point.accessibility),
                    subtitle: String(localized: "Accessibilité"))
            }
            Button(action: openDirections) {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.grenier)
            .accessibilityHint("Ouvre Plans avec l'itinéraire à pied")
        }
        .grenierCard()
    }

    private func row(symbol: String, title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.grenier)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.texte)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// « Chez Fatima, 7420 rue Ogilvy »
    var title: String {
        let street = PickupPointFormatting.firstLine(of: point.address)
        let place = hostName.map { String(localized: "Chez \($0)") } ?? point.name
        return street.isEmpty ? place : "\(place), \(street)"
    }

    /// « Point de cueillette · 450 m à pied »
    var placeSubtitle: String {
        var parts = ["Point de cueillette"]
        if let distanceMeters { parts.append(String(localized: "\(NeighborhoodMapLayout.distanceText(distanceMeters)) à pied")) }
        return parts.joined(separator: " · ")
    }

    private var slotSubtitle: String {
        point.slots.count > 1 ? String(localized: "Prochain créneau · \(point.slots.count - 1) autre\(point.slots.count > 2 ? "s" : "")")
                              : String(localized: "Prochain créneau")
    }

    /// Plans en mode à pied : sur la coordonnée si on l'a, sinon Plans cherche l'adresse.
    private func openDirections() {
        if let coordinate {
            PickupPointFormatting.mapItem(name: title, address: point.address, coordinate: coordinate)
                .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        } else if let url = PickupPointFormatting.directionsURL(address: point.address) {
            openURL(url)
        }
    }
}

/// Textes et lieu du point de cueillette (testés).
enum PickupPointFormatting {
    private static let locale = Locale(identifier: "fr_CA")

    /// « Jeudi, 17 h – 18 h 30 »
    static func slotText(_ slot: PickupSlot, calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let weekdayIndex = calendar.component(.weekday, from: slot.start) - 1
        let weekday = calendar.standaloneWeekdaySymbols[weekdayIndex]
        let capitalized = weekday.prefix(1).uppercased() + weekday.dropFirst()
        return "\(capitalized), \(timeText(slot.start, calendar: calendar)) – \(timeText(slot.end, calendar: calendar))"
    }

    /// « 17 h », « 18 h 30 »
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }

    /// « Sans marches · Près du métro »
    static func accessibilityText(_ features: [PickupPoint.Accessibility]) -> String {
        features.map(label(for:)).joined(separator: " · ")
    }

    static func label(for feature: PickupPoint.Accessibility) -> String {
        switch feature {
        case .wheelchair: String(localized: "Accessible en fauteuil roulant")
        case .stepFree: String(localized: "Sans marches")
        case .elevator: String(localized: "Ascenseur")
        case .nearMetro: String(localized: "Près du métro")
        case .parking: String(localized: "Stationnement")
        }
    }

    /// « 7420 rue Ogilvy, Montréal » → « 7420 rue Ogilvy »
    static func firstLine(of address: String) -> String {
        (address.split(separator: ",").first.map(String.init) ?? address).trimmingCharacters(in: .whitespaces)
    }

    /// Lieu pour Plans à partir de la coordonnée du point.
    static func mapItem(name: String, address: String, coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: MKAddress(fullAddress: address, shortAddress: firstLine(of: address)))
        item.name = name
        return item
    }

    /// Itinéraire à pied vers une adresse dans Plans, quand on n'a pas de coordonnée.
    static func directionsURL(address: String) -> URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: "w")]
        return components?.url
    }
}

#if DEBUG
#Preview("Clair") {
    ScrollView {
        VStack(spacing: 12) {
            PickupPointCard(point: NeighborhoodMapPreviewData.pickupPoint, hostName: "Fatima", distanceMeters: 450,
                            coordinate: NeighborhoodMapPreviewData.pickupCoordinate)
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Sombre") {
    PickupPointCard(point: NeighborhoodMapPreviewData.pickupPoint, hostName: "Fatima", distanceMeters: 450,
                    coordinate: NeighborhoodMapPreviewData.pickupCoordinate)
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView {
        PickupPointCard(point: NeighborhoodMapPreviewData.pickupPoint, hostName: "Fatima", distanceMeters: 450,
                        coordinate: NeighborhoodMapPreviewData.pickupCoordinate)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}
#endif
