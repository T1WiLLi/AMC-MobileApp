// FamilyMapComponents.swift
// Morceaux de la carte des familles (T-091, refonte T-172) : épingles avec photo, repère du quartier,
// explication de la position et fiche opaque du lieu touché (seulement quand une épingle est choisie).

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

extension FamilyMapViewModel.Place {
    /// Ligne d'info de la fiche du lieu : « 27 familles · Hochelaga », « Jeudi, 17 h – 18 h », « Ferme · 3 lots ouverts ».
    var subtitle: String {
        switch detail {
        case .group(let group, let isMember):
            let families = FrenchPlural.count(group.householdCount, "famille")
            if isMember { return String(localized: "\(families) · tu en fais partie") }
            guard let neighborhood = NeighborhoodName.display(group.neighborhood) else { return families }
            return "\(families) · \(neighborhood)"
        case .pickupPoint(let point):
            if let slot = point.slots.first { return PickupPointFormatting.slotText(slot) }
            let street = PickupPointFormatting.firstLine(of: point.address)
            return street.isEmpty ? String(localized: "Jusqu'à \(point.capacity) parts") : street
        case .producer(let vendor, _, let openOfferCount):
            let kind = FamilyMapPlaceTile.kindText(vendor.kind)
            return openOfferCount == 0
                ? String(localized: "\(kind) · pas de lot ouvert")
                : "\(kind) · \(FrenchPlural.count(openOfferCount, "lot ouvert", plural: "lots ouverts"))"
        }
    }

    /// Écran ouvert en touchant la carte du lieu ; nil pour un point de cueillette (itinéraire dans Plans).
    var destination: FamilyMapDestination? {
        switch detail {
        case .group(let group, _): .group(group.id)
        case .producer(let vendor, _, _): .vendor(vendor.id)
        case .pickupPoint: nil
        }
    }

    /// Itinéraire à pied vers un point de cueillette (Plans).
    func openWalkingDirections() {
        guard case .pickupPoint(let point) = detail else { return }
        PickupPointFormatting.mapItem(name: point.name, address: point.address, coordinate: coordinate.location)
            .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - Vignette (photo ou symbole)

/// Photo du groupe ou du producteur ; à défaut (ou pendant le chargement), le symbole de la sorte sur un dégradé.
struct FamilyMapThumbnail: View {
    let kind: FamilyMapViewModel.Kind
    let photoURL: URL?
    var symbolScale: CGFloat = 0.42

    var body: some View {
        GeometryReader { proxy in
            MediaImage(url: photoURL) {
                LinearGradient(colors: [kind.color, kind.color.opacity(0.75)], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: proxy.size.width * symbolScale, weight: .semibold))
                            .foregroundStyle(Color.onAccent)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Épingle

/// Médaillon (photo ou symbole) cerclé de la couleur de la sorte, avec sa pointe ; quand il est choisi,
/// il grossit, rebondit et affiche le nom du lieu au-dessus.
struct FamilyMapPin: View {
    let kind: FamilyMapViewModel.Kind
    var photoURL: URL? = nil
    var name: String = ""
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 40
    private var size: CGFloat { min(scaledSize, 60) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    FamilyMapThumbnail(kind: kind, photoURL: photoURL)
                        .frame(width: size, height: size)
                        .clipShape(.circle)
                        .padding(2.5)
                        .background(kind.color, in: .circle)
                        .padding(2)
                        .background(Color.surface, in: .circle)
                        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.14), radius: isSelected ? 10 : 5, y: 3)
                        .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    if photoURL != nil {
                        // Photo : le symbole de la sorte reste lisible en pastille.
                        Image(systemName: kind.systemImage)
                            .font(.system(size: size * 0.26, weight: .bold))
                            .foregroundStyle(Color.onAccent)
                            .frame(width: size * 0.46, height: size * 0.46)
                            .background(kind.color, in: .circle)
                            .overlay(Circle().strokeBorder(Color.surface, lineWidth: 1.5))
                            .offset(x: 4, y: 2)
                    }
                }
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(kind.color)
                    .offset(y: -2)
            }
            .overlay(alignment: .top) {
                if isSelected && !name.isEmpty {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.texte)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        // T-182 : étiquette sur la carte, plafonnée comme les autres surcouches (#223) ; à AX5 elle
                        // sortait de l'écran. Le nom complet reste lisible dans la carte du lieu, en bas.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] + 6 }
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.22 : 1, anchor: .bottom)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: isSelected)
        .zIndex(isSelected ? 1 : 0)
    }
}

/// Repère du quartier du ménage quand la position n'est pas utilisée (halo qui respire).
struct FamilyMapHomeMarker: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false

    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: min(size, 48) * 0.45, weight: .bold))
            .foregroundStyle(Color.grenier)
            .frame(width: min(size, 48), height: min(size, 48))
            .background(Color.surface, in: .circle)
            .overlay(Circle().strokeBorder(Color.grenier, lineWidth: 2))
            .background {
                Circle()
                    .fill(Color.grenier.opacity(0.18))
                    .scaleEffect(breathes ? 2.1 : 1.3)
                    .opacity(breathes ? 0 : 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { breathes = true }
            }
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
                    Text("LeGrenier utilise ta position seulement quand la carte est ouverte, pour trouver les groupes, les points de cueillette et les producteurs autour de toi. Elle n'est jamais montrée à tes voisins.")
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
            Text(neighborhood.map { String(localized: "Rester \($0.lowercasedFirst)") } ?? String(localized: "Rester sur mon quartier"))
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

// MARK: - Fiche du lieu choisi

/// Fiche du lieu touché sur la carte, en bas de l'écran. Absente tant qu'aucune épingle n'est touchée, pour que
/// la carte reste libre ; le bouton « fermer » (ou un second toucher de l'épingle) la retire.
struct FamilyMapSelectedPlaceCard: View {
    let place: FamilyMapViewModel.Place
    /// T-182 : hauteur maximale de la fiche aux tailles d'accessibilité ; au-delà, son texte défile.
    var maxTileHeight: CGFloat? = nil
    let onOpen: (FamilyMapDestination) -> Void
    let onClose: () -> Void

    var body: some View {
        FamilyMapPlaceTile(place: place, isSelected: true, maxHeight: maxTileHeight, onOpen: onOpen)
            .overlay(alignment: .topTrailing) {
                Button("Fermer la fiche du lieu", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.texteSecondaire)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                    .buttonStyle(.plain)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .offset(x: 12, y: -14)
            }
    }
}

/// Carte opaque d'un lieu : vignette, sorte, nom, info utile, distance à pied. La toucher ouvre le groupe
/// ou le producteur, ou l'itinéraire vers un point de cueillette ; appui long pour les autres actions.
struct FamilyMapPlaceTile: View {
    let place: FamilyMapViewModel.Place
    let isSelected: Bool
    /// T-182 : aux tailles d'accessibilité, la carte ne dépasse pas cette hauteur et son texte défile.
    var maxHeight: CGFloat? = nil
    let onOpen: (FamilyMapDestination) -> Void

    @ScaledMetric(relativeTo: .headline) private var scaledThumbnail: CGFloat = 68
    private var thumbnail: CGFloat { min(scaledThumbnail, 96) }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Group {
            if isLarge, let maxHeight {
                // Le texte entier, sans troncature : la carte prend la hauteur de son texte, jusqu'à `maxHeight`,
                // puis il défile dedans (le bouton reste dedans).
                ScrollView(.vertical) {
                    card.onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
            } else {
                card
            }
        }
        .background(Color.surface, in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(place.kind.color.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 26))
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.1), radius: isSelected ? 14 : 8, y: 4)
        .contextMenu { menu }
    }

    private var card: some View {
        Button(action: open) {
            Group {
                if isLarge { largeContent } else { regularContent }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place.accessibilityLabel + ", " + place.subtitle)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var regularContent: some View {
        HStack(spacing: 14) {
            FamilyMapThumbnail(kind: place.kind, photoURL: place.photoURL)
                .frame(width: thumbnail, height: thumbnail)
                .clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 3) {
                kindLabel
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .lineLimit(2)
                Text(place.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .lineLimit(1)
                distanceBadge
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionSymbol
        }
    }

    /// Aux tailles d'accessibilité : ni vignette ni symbole d'action (toute la carte se touche), pour laisser toute
    /// la largeur à la sorte, au nom et à l'info, qui passent à la ligne au lieu d'être coupés.
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            kindLabel
            Text(place.name)
                .font(.headline)
                .foregroundStyle(Color.texte)
            Text(place.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
            distanceBadge
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var kindLabel: some View {
        Label(place.kind.title, systemImage: place.kind.systemImage)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(place.kind.color)
    }

    private var distanceBadge: some View {
        Label(place.distanceText, systemImage: "figure.walk")
            .font(.caption.weight(.semibold))
            .foregroundStyle(place.kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(place.kind.color.opacity(0.12), in: .capsule)
    }

    private var actionSymbol: some View {
        Image(systemName: place.destination == nil ? "arrow.triangle.turn.up.right.circle.fill" : "chevron.right.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(place.kind.color)
            .accessibilityHidden(true)
    }

    private var hint: String {
        switch place.kind {
        case .group: String(localized: "Ouvre la fiche du groupe")
        case .pickupPoint: String(localized: "Ouvre l'itinéraire à pied dans Plans")
        case .producer: String(localized: "Ouvre la page du producteur")
        }
    }

    private func open() {
        if let destination = place.destination {
            onOpen(destination)
        } else {
            place.openWalkingDirections()
        }
    }

    @ViewBuilder private var menu: some View {
        switch place.detail {
        case .group(let group, _):
            Button("Voir le groupe", systemImage: "person.3.fill") { onOpen(.group(group.id)) }
        case .pickupPoint:
            Button("Itinéraire à pied", systemImage: "figure.walk") { place.openWalkingDirections() }
        case .producer(let vendor, let offerId, _):
            Button("Voir le producteur", systemImage: "storefront.fill") { onOpen(.vendor(vendor.id)) }
            if let offerId {
                Button("Voir son lot", systemImage: "basket.fill") { onOpen(.offer(offerId)) }
            }
        }
    }

    /// « Ferme », « Boulangerie »…
    static func kindText(_ kind: Vendor.Kind) -> String {
        switch kind {
        case .farm: String(localized: "Ferme")
        case .wholesaler: String(localized: "Grossiste")
        case .cooperative: String(localized: "Coopérative")
        case .bakery: String(localized: "Boulangerie")
        case .other: String(localized: "Producteur")
        }
    }
}
