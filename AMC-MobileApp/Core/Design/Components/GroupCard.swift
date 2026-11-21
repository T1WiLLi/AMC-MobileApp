import SwiftUI

/// Un groupe de quartier (maquette GroupCard) : avatars, nom, familles, point de cueillette, distance, Rejoindre.
struct GroupCard: View {
    let group: NeighborhoodGroup
    /// Initiales de quelques membres pour la pile d'avatars.
    var memberInitials: [String] = []
    /// « rue Ogilvy » ; nil si aucun point de cueillette n'est choisi.
    var pickupLabel: String?
    var distanceMeters: Int?
    var isMember = false
    var onJoin: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            AvatarStack(initials: memberInitials, extraCount: max(group.householdCount - memberInitials.prefix(3).count, 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 8)
            if isMember {
                Label("Membre", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(Color.economie)
                    .accessibilityLabel("Tu es membre")
            } else if let onJoin {
                Button("Rejoindre", action: onJoin)
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .fontWeight(.semibold)
            }
        }
        .grenierCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    /// « 24 familles · cueillette rue Ogilvy · 450 m »
    var detailText: String {
        var parts = ["\(group.householdCount) \(group.householdCount > 1 ? "familles" : "famille")"]
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
#endif
