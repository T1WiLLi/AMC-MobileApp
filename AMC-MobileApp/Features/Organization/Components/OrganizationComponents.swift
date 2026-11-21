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
            return "\(FrenchPlural.count(profile.basketsFundable, "panier")) en réserve · aucun ménage en attente"
        }
        return "\(FrenchPlural.count(profile.basketsFundable, "panier")) en réserve pour "
            + FrenchPlural.count(profile.subsidizedHouseholds, "ménage aidé", plural: "ménages aidés")
    }
}

// MARK: - Chiffres

/// Tuile de chiffre clé : icône, valeur animée, libellé.
struct OrganizationKPITile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    /// Valeur numérique qui déclenche l'animation du chiffre.
    let numericValue: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
                .symbolEffect(.bounce, value: reduceMotion ? 0 : numericValue)
                .accessibilityHidden(true)
            Text(value)
                .priceStyle(.title2.bold())
                .foregroundStyle(Color.texte)
                .contentTransition(.numericText(value: Double(numericValue)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .grenierAnimation(.smooth, value: numericValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Simulation

/// Rappel bien visible : aucun argent réel ne circule.
struct SimulationNotice: View {
    var compact = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Simulation")
                    .font(.subheadline.weight(.semibold))
                if !compact {
                    Text("Aucun argent réel n'est prélevé : les financements servent à la démonstration.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: "testtube.2")
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(Color.texteSecondaire)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.piste.opacity(0.5), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.texteSecondaire.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mise en page

/// Titre de section avec icône.
struct OrganizationSectionTitle: View {
    let title: String
    let systemImage: String
    var tint: Color = .grenier

    init(_ title: String, systemImage: String, tint: Color = .grenier) {
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

/// Carte d'un groupe : nom, quartier, distance, besoin, couverture, et ses actions.
struct GroupNeedCard<Actions: View>: View {
    let profile: GroupSolidarityProfile
    var distance: String?
    var isSponsored = false
    @ViewBuilder let actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(profile.needLevel.tint)
                    .frame(width: 44, height: 44)
                    .background(profile.needLevel.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.groupName)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Label(profile.neighborhood, systemImage: "mappin.and.ellipse")
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
                    NeedBadge(level: profile.needLevel)
                    if isSponsored {
                        Label("Parrainé", systemImage: "hands.and.sparkles.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.grenier)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
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
        .grenierCard()
    }
}
