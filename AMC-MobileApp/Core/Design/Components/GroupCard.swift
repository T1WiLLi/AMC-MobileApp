import SwiftUI

/// Un groupe de quartier (maquette GroupCard) : avatars, nom, familles, point de cueillette, distance, Rejoindre.
/// Carte opaque ; Rejoindre reste secondaire (`.glass`) pour garder une seule action principale par écran.
struct GroupCard: View {
    let group: NeighborhoodGroup
    /// Initiales de quelques membres pour la pile d'avatars.
    var memberInitials: [String] = []
    /// « rue Ogilvy » ; nil si aucun point de cueillette n'est choisi.
    var pickupLabel: String?
    var distanceMeters: Int?
    var isMember = false
    var onJoin: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 48

    /// Membres en plus des initiales affichées, pour que la pile annonce exactement `householdCount`.
    var extraMembers: Int { max(group.householdCount - memberInitials.prefix(3).count, 0) }

    var body: some View {
        let layout = rowLayout
        layout {
            // Le nombre de familles est déjà lu dans le détail : la photo et la pile d'avatars ne le répètent pas.
            // T-122 : la photo du groupe quand il en a une, sinon la pile d'avatars des membres.
            Group {
                if group.photoURL != nil {
                    GroupAvatarView(group: group, size: min(photoSize, 72))
                } else {
                    AvatarStack(initials: memberInitials, extraCount: extraMembers)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label(detailText, systemImage: pickupLabel == nil ? "house.fill" : "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                // T-174 : note moyenne des familles, tirée des agrégats du groupe (aucune lecture de plus).
                RatingSummaryView(summary: group.ratingSummary, font: .footnote)
                    .padding(.top, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if isMember {
                Label("Membre", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: isMember && !reduceMotion)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Tu es membre de \(group.name)")
            } else if let onJoin {
                Button(action: onJoin) {
                    Label("Rejoindre", systemImage: "person.badge.plus")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.glass)
                .tint(.grenier)
                .fontWeight(.semibold)
                .accessibilityLabel("Rejoindre \(group.name)")
                .accessibilityHint("Ajoute ta famille à ce groupe d'achat")
            }
        }
        .grenierCard(padding: 14)
        .grenierAnimation(.smooth, value: isMember)
        .grenierHaptic(.success, trigger: isMember) { _, new in new }
        .accessibilityElement(children: .contain)
    }

    /// Ligne horizontale, empilée aux tailles d'accessibilité.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// Nom, détail et note (si le groupe a des avis).
    private var accessibilityText: String {
        let summary = group.ratingSummary
        guard summary.average != nil else { return "\(group.name), \(detailText)" }
        return "\(group.name), \(detailText). \(RatingSummaryView.accessibilityText(summary))"
    }

    /// « 24 familles · cueillette rue Ogilvy · 450 m »
    var detailText: String {
        var parts = [FrenchPlural.count(group.householdCount, "famille")]
        if let pickupLabel { parts.append("cueillette \(pickupLabel)") }
        if let distanceMeters { parts.append(Self.distanceText(distanceMeters)) }
        return parts.joined(separator: " · ")
    }

    static func distanceText(_ meters: Int) -> String {
        if meters < 1_000 { return "\(meters) m" }
        return (Double(meters) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.formattingLocale)) + " km"
    }
}

#if DEBUG
#Preview("Clair") {
    VStack(spacing: 12) {
        GroupCard(group: CardPreviewData.group, memberInitials: ["FB", "RK"], pickupLabel: "rue Ogilvy", distanceMeters: 450, onJoin: {})
        GroupCard(group: CardPreviewData.group, memberInitials: ["AM", "FB", "RK"], pickupLabel: "rue Ogilvy", distanceMeters: 1_200, isMember: true)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .grenierBackground()
}

#Preview("Sombre") {
    GroupCard(group: CardPreviewData.group, memberInitials: ["FB", "RK"], pickupLabel: "rue Ogilvy", distanceMeters: 450, onJoin: {})
        .padding()
        .frame(maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView {
        GroupCard(group: CardPreviewData.group, memberInitials: ["FB", "RK"], pickupLabel: "rue Ogilvy", distanceMeters: 450, onJoin: {})
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
}

#Preview("AX5 sombre") {
    ScrollView {
        GroupCard(group: CardPreviewData.group, memberInitials: ["AM", "FB", "RK"], pickupLabel: "rue Ogilvy", distanceMeters: 1_200, isMember: true)
            .padding()
    }
    .grenierBackground()
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
#endif
