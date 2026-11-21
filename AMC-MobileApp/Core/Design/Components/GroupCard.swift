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

    /// Membres en plus des initiales affichées, pour que la pile annonce exactement `householdCount`.
    var extraMembers: Int { max(group.householdCount - memberInitials.prefix(3).count, 0) }

    var body: some View {
        let layout = rowLayout
        layout {
            // Le nombre de familles est déjà lu dans le détail : la pile d'avatars ne le répète pas.
            AvatarStack(initials: memberInitials, extraCount: extraMembers)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.name), \(detailText)")
            .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if isMember {
                Label("Membre", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(Color.economie)
                    .accessibilityLabel("Tu es membre de \(group.name)")
            } else if let onJoin {
                Button("Rejoindre", action: onJoin)
                    .buttonStyle(.glass)
                    .tint(.grenier)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Rejoindre \(group.name)")
                    .accessibilityHint("Ajoute ta famille à ce groupe d'achat")
            }
        }
        .grenierCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    /// Ligne horizontale, empilée aux tailles d'accessibilité.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
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
        return (Double(meters) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CA"))) + " km"
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
