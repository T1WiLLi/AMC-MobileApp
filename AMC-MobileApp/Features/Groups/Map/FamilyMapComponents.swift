// FamilyMapComponents.swift
// Morceaux de la carte des familles (T-091) : épingles par sorte de lieu, repère du quartier,
// explication de la position et carte en verre du lieu touché.

import MapKit
import SwiftUI

extension FamilyMapViewModel.Kind {
    /// Groupe = Grenier, point de cueillette = Solidarité, producteur = Économie.
    var color: Color {
        switch self {
        case .group: .grenier
        case .pickupPoint: .solidarite
        case .producer: .economie
        }
    }
}

// MARK: - Épingle

/// Pastille colorée avec le symbole de la sorte et sa petite tige ; grossit et rebondit quand elle est choisie.
struct FamilyMapPin: View {
    let kind: FamilyMapViewModel.Kind
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: min(size, 64) * 0.45, weight: .semibold))
                    .foregroundStyle(Color.onAccent)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    .frame(width: min(size, 64), height: min(size, 64))
                    .background(kind.color, in: .circle)
                    .padding(3)
                    .background(Color.surface, in: .circle)
                    .overlay {
                        if isSelected { Circle().strokeBorder(Color.texte, lineWidth: 2) }
                    }
                    .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 10 : 5, y: 2)
                Capsule()
                    .fill(kind.color)
                    .frame(width: 3, height: 8)
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.18 : 1, anchor: .bottom)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.35), value: isSelected)
    }
}

/// Repère du quartier du ménage quand la position n'est pas utilisée.
struct FamilyMapHomeMarker: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: min(size, 48) * 0.45, weight: .bold))
            .foregroundStyle(Color.grenier)
            .frame(width: min(size, 48), height: min(size, 48))
            .background(Color.surface, in: .circle)
            .overlay(Circle().strokeBorder(Color.grenier, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .accessibilityLabel("Ton quartier")
    }
}

// MARK: - Explication de la position

/// Montrée une fois, avant la feuille système : pourquoi la position, et ce qui se passe sans.
struct FamilyMapLocationExplainer: View {
    /// « Autour de Saint-Michel » : là où la carte reste sans la position.
    let neighborhood: String?
    let onAllow: () -> Void
    let onDecline: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.bounce, value: appeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voir ce qui est près de toi")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Text("Grenier utilise ta position seulement quand la carte est ouverte, pour trouver les groupes, les points de cueillette et les producteurs autour de toi. Elle n'est jamais montrée à tes voisins.")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 10) { buttons }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .onAppear { appeared = true }
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onAllow) {
            Label("Utiliser ma position", systemImage: "location.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)

        Button(action: onDecline) {
            Text(neighborhood.map { "Rester \($0.lowercasedFirst)" } ?? "Rester sur mon quartier")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

private extension String {
    /// « Autour de Saint-Michel » → « autour de Saint-Michel ».
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - Carte du lieu touché

/// Détails du lieu et une action : voir le groupe, l'itinéraire vers le point, ou le lot du producteur.
struct FamilyMapPlaceCard: View {
    let place: FamilyMapViewModel.Place
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 8) { details }
            action
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: place.kind.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .frame(width: min(badgeSize, 72), height: min(badgeSize, 72))
                .background(place.kind.color, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .accessibilityAddTraits(.isHeader)
                Text("\(place.kind.title) · \(place.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Fermer", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Fermer les détails")
        }
    }

    @ViewBuilder private var details: some View {
        switch place.detail {
        case .group(let group, let isMember):
            row("person.2.fill", "\(group.householdCount) \(group.householdCount > 1 ? "familles" : "famille")")
            row("circle.dashed", "Rayon de \(NeighborhoodMapLayout.distanceText(group.radiusMeters)) · \(group.neighborhood)")
            if isMember {
                row("checkmark.seal.fill", "Tu en fais partie", tint: .economie)
            }
        case .pickupPoint(let point):
            if let slot = point.slots.first {
                row("clock.fill", PickupPointFormatting.slotText(slot))
            }
            let street = PickupPointFormatting.firstLine(of: point.address)
            if !street.isEmpty { row("mappin.and.ellipse", street) }
            if !point.accessibility.isEmpty {
                row("figure.roll", PickupPointFormatting.accessibilityText(point.accessibility))
            }
            row("shippingbox.fill", "Jusqu'à \(point.capacity) parts")
        case .producer(let vendor, _, let openOfferCount):
            row("storefront.fill", Self.kindText(vendor.kind) + (vendor.isVerified ? " · vérifié" : ""))
            if let rating = vendor.averageRating {
                row("star.fill", rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CA"))) + " sur 5")
            }
            if !vendor.description.isEmpty {
                Text(vendor.description)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .lineLimit(3)
            }
            row("tag.fill", openOfferCount == 0
                ? "Pas de lot ouvert en ce moment"
                : "\(openOfferCount) \(openOfferCount > 1 ? "lots ouverts" : "lot ouvert")")
        }
    }

    @ViewBuilder private var action: some View {
        switch place.detail {
        case .group(let group, _):
            NavigationLink(value: GroupRoute(groupId: group.id)) {
                actionLabel("Voir le groupe", systemImage: "person.3.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .controlSize(.large)
        case .pickupPoint(let point):
            Button {
                PickupPointFormatting.mapItem(name: point.name, address: point.address, coordinate: place.coordinate.location)
                    .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: {
                actionLabel("Itinéraire à pied", systemImage: "figure.walk")
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .controlSize(.large)
            .accessibilityHint("Ouvre Plans")
        case .producer(_, let offerId?, _):
            NavigationLink(value: OfferRoute(offerId: offerId)) {
                actionLabel("Voir son lot", systemImage: "basket.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .controlSize(.large)
        case .producer(_, nil, _):
            EmptyView()
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
    }

    private func row(_ symbol: String, _ text: String, tint: Color = .grenier) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// « Ferme », « Boulangerie »…
    static func kindText(_ kind: Vendor.Kind) -> String {
        switch kind {
        case .farm: "Ferme"
        case .wholesaler: "Grossiste"
        case .cooperative: "Coopérative"
        case .bakery: "Boulangerie"
        case .other: "Producteur"
        }
    }
}
