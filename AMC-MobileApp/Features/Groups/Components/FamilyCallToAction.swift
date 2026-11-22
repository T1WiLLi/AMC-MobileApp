import SwiftUI

/// Action principale des états vides côté famille : plutôt qu'un écran inerte (ou du contenu inventé),
/// on propose la prochaine étape réelle. La destination s'ouvre en feuille, avec les vraies données de `appContext`.
struct FamilyCallToAction: View {
    enum Destination: Identifiable {
        /// Pas encore de groupe : la liste des groupes de quartier, pour en rejoindre un.
        case findGroup
        /// Groupe rejoint, aucune part : les lots actifs, pour réserver une première part.
        case browseOffers

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .findGroup: "Trouver un groupe"
            case .browseOffers: "Voir les lots"
            }
        }

        var systemImage: String {
            switch self {
            case .findGroup: GrenierSymbol.groups
            case .browseOffers: GrenierSymbol.offers
            }
        }

        var hint: LocalizedStringKey {
            switch self {
            case .findGroup: "Ouvre les groupes de ton quartier"
            case .browseOffers: "Ouvre les lots actifs près de chez toi"
            }
        }
    }

    let destination: Destination
    @State private var presented: Destination?

    var body: some View {
        Button {
            presented = destination
        } label: {
            Label(destination.title, systemImage: destination.systemImage)
                .fontWeight(.semibold)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)
        .accessibilityHint(destination.hint)
        .sheet(item: $presented) { destination in
            switch destination {
            case .findGroup:
                // FB-15 : la feuille se ferme avec « Fermer » ou en glissant vers le bas.
                GroupsScreen(showsCloseButton: true)
                    .presentationDragIndicator(.visible)
            case .browseOffers:
                SearchScreen(prompt: "Riz, pommes, producteur…", linksToOffers: true)
            }
        }
    }
}

#Preview("Trouver un groupe") {
    FamilyCallToAction(destination: .findGroup)
        .environment(\.appContext, .instant)
}

#Preview("Voir les lots") {
    FamilyCallToAction(destination: .browseOffers)
        .environment(\.appContext, .instant)
}
