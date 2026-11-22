import MapKit
import SwiftUI

// T-208 : carte du portail Organismes, pour une vue d'ensemble : les groupes de quartier (épingles rondes, comme la
// carte du portail Famille, T-091) et les organismes (médaillons carrés, couleur Solidarité ; le tien est cerclé de
// Grenier). Ouverte en plein écran depuis le Tableau (la barre d'onglets a déjà 4 onglets + Recherche).
// Réutilise l'épingle et la vignette de la carte Famille (`FamilyMapPin`, `FamilyMapThumbnail`).

extension OrganizationMapPlace.Kind {
    var title: String {
        switch self {
        case .group: String(localized: "Groupes")
        case .organization: String(localized: "Organismes")
        }
    }

    var systemImage: String {
        switch self {
        case .group: FamilyMapViewModel.Kind.group.systemImage
        case .organization: "building.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .group: FamilyMapViewModel.Kind.group.color
        case .organization: .solidarite
        }
    }
}

extension OrganizationMapPlace {
    /// Symbole de l'épingle : le type d'organisme, ou celui des groupes.
    var systemImage: String {
        switch detail {
        case .group: Kind.group.systemImage
        case .organization(let entry, _): entry.kind.systemImage
        }
    }

    var tint: Color { isMine ? .grenier : kind.tint }

    /// « Groupe de quartier · Hochelaga », « Fondation · Verdun ».
    var subtitle: String {
        switch detail {
        case .group(let profile):
            String(localized: "Groupe de quartier · \(MontrealNeighborhood.displayName(for: profile.neighborhood))")
        case .organization(let entry, _):
            "\(entry.kind.label) · \(MontrealNeighborhood.displayName(for: entry.neighborhood))"
        }
    }
}

/// Carte en plein écran, dans sa propre pile de navigation (la fiche d'un groupe s'y pousse).
struct OrganizationMapScreen: View {
    let model: OrganizationPortalModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var visibleKinds = Set(OrganizationMapPlace.Kind.allCases)

    private var places: [OrganizationMapPlace] {
        model.mapPlaces.filter { visibleKinds.contains($0.kind) }
    }

    private var selected: OrganizationMapPlace? {
        places.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: place.coordinate.location, anchor: .bottom) {
                        FamilyMapPin(tint: place.tint, systemImage: place.systemImage, photoURL: place.photoURL,
                                     name: place.name, isSquare: place.kind == .organization,
                                     isSelected: place.id == selectedID, reduceMotion: reduceMotion) {
                            withAnimation(reduceMotion ? nil : .grenierSmooth) {
                                selectedID = place.id == selectedID ? nil : place.id
                            }
                        }
                        .accessibilityLabel("\(place.name), \(place.subtitle)")
                        .accessibilityHint("Affiche les détails")
                        .accessibilityAddTraits(place.id == selectedID ? [.isButton, .isSelected] : .isButton)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) { filters }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let selected {
                        OrganizationMapPlaceCard(place: selected, model: model) { selectedID = nil }
                            .id(selected.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Label("Touche une épingle : un groupe pour voir sa fiche, un organisme pour le découvrir.",
                              systemImage: "hand.tap.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.texte)
                            .symbolRenderingMode(.hierarchical)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .grenierHaptic(.selection, trigger: selectedID)
            .navigationTitle("Carte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .organizationGroupDestination(model: model)
        }
    }

    /// Puces Groupes / Organismes, avec leur nombre : on masque une sorte pour voir l'autre.
    private var filters: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(OrganizationMapPlace.Kind.allCases) { kind in
                    let isOn = visibleKinds.contains(kind)
                    let count = model.mapPlaces.filter { $0.kind == kind }.count
                    Button {
                        withAnimation(reduceMotion ? nil : .grenierSmooth) {
                            if isOn, visibleKinds.count > 1 { visibleKinds.remove(kind) } else { visibleKinds.insert(kind) }
                        }
                    } label: {
                        Label("\(kind.title) · \(count)", systemImage: kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isOn ? kind.tint : Color.texteSecondaire)
                    }
                    .buttonStyle(.glass)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityHint(isOn ? "Masque ces lieux" : "Affiche ces lieux")
                }
                Spacer(minLength: 0)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Carte du lieu choisi : un groupe (besoin, « Voir la fiche ») ou un organisme (bannière, type, quartier, distance).
struct OrganizationMapPlaceCard: View {
    let place: OrganizationMapPlace
    let model: OrganizationPortalModel
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .headline) private var thumbnailSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                FamilyMapThumbnail(tint: place.tint, systemImage: place.systemImage, photoURL: place.photoURL)
                    .frame(width: min(thumbnailSize, 80), height: min(thumbnailSize, 80))
                    .clipShape(place.kind == .organization ? AnyShape(.rect(cornerRadius: 14)) : AnyShape(.circle))
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(place.subtitle, systemImage: place.systemImage)
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                    details
                }
                Spacer(minLength: 0)
                Button("Fermer", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            action
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private var details: some View {
        HStack(spacing: 8) {
            switch place.detail {
            case .group(let profile):
                NeedBadge(level: profile.needLevel)
                if let distance = model.distanceText(for: profile) {
                    Label(distance, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                }
            case .organization(let entry, let isMine):
                if isMine {
                    Label("Ton organisme", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                } else if let distance = model.distanceText(toGeohash: entry.geohash) {
                    Label("À \(distance) de toi", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                }
            }
        }
        .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private var action: some View {
        switch place.detail {
        case .group(let profile):
            NavigationLink(value: OrganizationGroupRoute(groupId: profile.groupId)) {
                Label("Voir la fiche du groupe", systemImage: "chevron.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .controlSize(.large)
        case .organization(let entry, _):
            MediaImage(url: entry.bannerURL) { GroupBannerFallback() }
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityHidden(true)
        }
    }
}

/// Section du Tableau : aperçu de la carte (non interactif) qui ouvre la carte en plein écran.
struct OrganizationMapPreviewCard: View {
    let model: OrganizationPortalModel
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 170

    private var groupCount: Int { model.mapPlaces.filter { $0.kind == .group }.count }
    private var organizationCount: Int { model.mapPlaces.filter { $0.kind == .organization }.count }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .automatic, interactionModes: []) {
                    ForEach(model.mapPlaces) { place in
                        Annotation(place.name, coordinate: place.coordinate.location, anchor: .center) {
                            Image(systemName: place.systemImage)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.onAccent)
                                .frame(width: 22, height: 22)
                                .background(place.tint, in: place.kind == .organization
                                            ? AnyShape(.rect(cornerRadius: 6)) : AnyShape(.circle))
                                .overlay {
                                    (place.kind == .organization ? AnyShape(.rect(cornerRadius: 6)) : AnyShape(.circle))
                                        .stroke(Color.surface, lineWidth: 1.5)
                                }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: min(mapHeight, 240))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Groupes et organismes autour de toi")
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(FrenchPlural.count(groupCount, "groupe")) · \(FrenchPlural.count(organizationCount, "organisme"))")
                            .font(.subheadline)
                            .foregroundStyle(Color.texteSecondaire)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .foregroundStyle(Color.grenier)
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .background(Color.surface)
            .clipShape(.rect(cornerRadius: 24))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Carte des groupes et des organismes")
        .accessibilityHint("Ouvre la carte en plein écran")
    }
}

#if DEBUG
#Preview("Carte") {
    let repositories = AppContext.instant.repositories
    let model = OrganizationPortalModel(repository: repositories.organizations, groups: repositories.groups,
                                        organizationId: FakeData.ID.laRuche)
    OrganizationMapScreen(model: model)
        .environment(\.appContext, .instant)
        .task { await model.load() }
}
#endif
