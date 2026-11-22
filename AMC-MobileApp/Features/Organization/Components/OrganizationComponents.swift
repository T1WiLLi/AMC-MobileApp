import SwiftUI

// Petits composants du portail Organismes (T-116) : indicateur de besoin, barre de couverture,
// tuile de chiffre, avis « simulation », titre de section, squelette de chargement, carte de groupe.

// MARK: - Besoin

extension OrganizationLedger.NeedLevel {
    /// Couleur du badge : Solidarite pour l'urgence, Grenier pour le besoin modéré, Economie quand c'est couvert.
    var tint: Color {
        switch self {
        case .urgent: .solidarite
        case .moderate: .grenier
        case .covered: .economie
        }
    }
}

/// Pastille « Besoin urgent » / « Besoin modéré » / « Couvert ».
struct NeedBadge: View {
    let level: OrganizationLedger.NeedLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(level.label, systemImage: level.systemImage)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.pulse, options: .repeating, isActive: level == .urgent && !reduceMotion)
            .foregroundStyle(level.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(level.tint.opacity(0.14), in: .capsule)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel("Besoin : \(level.label)")
    }
}

/// Barre « paniers en réserve / ménages subventionnés ».
struct CoverageBar: View {
    let profile: GroupSolidarityProfile
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 8

    private var coverage: Double { OrganizationLedger.coverage(of: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.piste)
                    Capsule()
                        .fill(profile.needLevel.tint.gradient)
                        .frame(width: max(height, proxy.size.width * coverage))
                }
            }
            .frame(height: height)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .grenierAnimation(.smooth, value: coverage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Couverture du fonds")
        .accessibilityValue(caption)
    }

    private var caption: String {
        guard profile.subsidizedHouseholds > 0 else {
            return String(localized: "\(FrenchPlural.count(profile.basketsFundable, "panier")) en réserve · aucun ménage en attente")
        }
        return String(localized: "\(FrenchPlural.count(profile.basketsFundable, "panier")) en réserve pour \(FrenchPlural.count(profile.subsidizedHouseholds, "ménage aidé", plural: "ménages aidés"))")
    }
}

// MARK: - Mise en page

/// Titre de section avec icône.
struct OrganizationSectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .grenier

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color = .grenier) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.title3.bold())
        .foregroundStyle(Color.texte)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Squelette du portail pendant le premier chargement.
struct OrganizationSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 120)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 130)
                    }
                }
                RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 200)
            }
            .padding(16)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Chargement")
        .grenierBackground()
    }
}

/// Affiche le contenu du portail selon l'état du modèle partagé (chargement, erreur, contenu).
struct OrganizationStateContainer<Content: View>: View {
    let model: OrganizationPortalModel?
    @ViewBuilder let content: (OrganizationPortalModel, OrganizationPortalModel.Snapshot) -> Content

    var body: some View {
        if let model {
            switch model.state {
            case .idle, .loading:
                OrganizationSkeleton()
            case .loaded(let snapshot):
                content(model, snapshot)
            case .empty, .failed:
                StateView(state: model.state, retry: { await model.load() }) { snapshot in
                    content(model, snapshot)
                }
            }
        } else {
            OrganizationSkeleton()
        }
    }
}

// MARK: - Carte de groupe

/// Carte d'un groupe : bannière et photo (comme dans la recherche de groupes du portail Famille), nom, quartier,
/// distance, besoin, couverture, et ses actions. T-208 : toucher la carte ouvre la fiche publique du groupe
/// (`OrganizationGroupRoute`, enregistrée par `.organizationGroupDestination(model:)` dans chaque onglet).
struct GroupNeedCard<Actions: View>: View {
    let profile: GroupSolidarityProfile
    var distance: String?
    var isSponsored = false
    @ViewBuilder let actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 52
    @ScaledMetric(relativeTo: .headline) private var bannerHeight: CGFloat = 88

    private var route: OrganizationGroupRoute { OrganizationGroupRoute(groupId: profile.groupId) }
    private var avatarSide: CGFloat { min(photoSize, 76) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: 0) {
                    if let group = profile.group {
                        banner(group)
                    }
                    summary
                        .padding(.horizontal, 16)
                        .padding(.top, profile.group == nil ? 16 : avatarSide / 2 + 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ouvre la fiche du groupe.")
            VStack(alignment: .leading, spacing: 12) {
                CoverageBar(profile: profile)
                HStack(spacing: 6) {
                    Label(FrenchPlural.count(profile.householdCount, "ménage"), systemImage: "house.fill")
                    Text("·")
                    Label("\(Money.formatRounded(profile.basketPriceCents)) le panier", systemImage: "basket.fill")
                }
                .font(.caption)
                .foregroundStyle(Color.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
                .accessibilityElement(children: .combine)
                actions()
            }
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 12)
        }
        .background(Color.surface)
        .clipShape(.rect(cornerRadius: theme.cornerRadius))
        .grenierZoomSource(route)
    }

    /// Bannière du groupe (dégradé Grenier s'il n'en a pas), sa photo qui la chevauche et le badge de besoin.
    private func banner(_ group: NeighborhoodGroup) -> some View {
        GroupBannerImage(group: group)
            .frame(maxWidth: .infinity)
            .frame(height: min(bannerHeight, 130))
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
            }
            .overlay(alignment: .topTrailing) {
                NeedBadge(level: profile.needLevel)
                    .background(.thinMaterial, in: .capsule)
                    .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                GroupAvatarView(group: group, size: avatarSide, showsRing: true)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .offset(x: 16, y: avatarSide / 2)
            }
            .accessibilityHidden(true)
    }

    private var summary: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            if profile.group == nil {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(profile.needLevel.tint)
                    .frame(width: 44, height: 44)
                    .background(profile.needLevel.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.groupName)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Label(MontrealNeighborhood.displayName(for: profile.neighborhood), systemImage: "mappin.and.ellipse")
                    if let distance {
                        Label(distance, systemImage: "location.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.texteSecondaire)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
            }
            Spacer(minLength: 0)
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                if profile.group == nil {
                    NeedBadge(level: profile.needLevel)
                }
                if isSponsored {
                    Label("Parrainé", systemImage: "hands.and.sparkles.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.texteSecondaire)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
