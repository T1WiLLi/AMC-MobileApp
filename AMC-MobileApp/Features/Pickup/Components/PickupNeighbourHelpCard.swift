import SwiftUI

/// Point d'entrée de l'entraide dans la Cueillette (F5) : « Se faire livrer par un voisin » (RQ-069)
/// et, plus tard, le covoiturage (RQ-070). Une seule ligne dans `PickupScreen` :
/// `PickupNeighbourHelpCard(pickupPoint: content.pickupPoint, slot: content.slot)`.
/// À poser dans un `NavigationStack` (les lignes poussent leur écran).
struct PickupNeighbourHelpCard: View {
    let pickupPoint: PickupPoint
    let slot: PickupSlot?

    @Environment(\.appContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NeighbourSectionHeader(title: "Pas besoin d'y aller seul", systemImage: "person.2.fill", tint: .solidarite)
                .padding(.bottom, 6)
            if let groupId = context.groupId {
                NavigationLink {
                    VolunteerDeliveryScreen(viewModel: VolunteerDeliveryViewModel(
                        repositories: context.repositories, userId: context.userId,
                        householdId: context.householdId, groupId: groupId
                    ))
                } label: {
                    NeighbourHelpRow(
                        title: "Livraison par un voisin",
                        subtitle: "Aîné ou mobilité réduite ? Un voisin t'apporte ta part. Ou deviens bénévole.",
                        systemImage: "figure.walk.cane"
                    )
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

/// Ligne d'entrée : symbole dans une pastille, titre, sous-titre, chevron.
struct NeighbourHelpRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .solidarite
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.texte)
                Text(subtitle).font(.subheadline).foregroundStyle(.texteSecondaire)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
