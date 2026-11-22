import SwiftUI

/// T-187 : route vers un lot d'un groupe dont le ménage n'est pas membre (fiche publique du groupe).
/// Enregistrée par `GroupDetailScreen` (qui garde le modèle du groupe pour l'action « Rejoindre ») :
///
///     NavigationLink(value: GroupOfferRoute(offerId: offer.id, groupId: group.id)) { OfferCard(…) }
struct GroupOfferRoute: Hashable, Sendable {
    let offerId: String
    let groupId: String
}

/// T-187 : fiche d'un lot en consultation. Le visiteur voit le produit, le producteur, les paliers et l'avancement
/// du groupe visité ; à la place du choix de part, une note et l'action du groupe (« Rejoindre » ou « Demander
/// une invitation »). Une fois membre, `isActive` repasse à false et la fiche redevient réservable.
@MainActor
struct OfferConsultation {
    let groupId: String
    let groupModel: GroupDetailViewModel

    /// Le ménage n'est (toujours) pas membre du groupe visité.
    var isActive: Bool { Self.isActive(isMember: groupModel.state.value?.isMember) }

    /// Tant que l'adhésion n'est pas connue comme acquise, on reste en consultation.
    nonisolated static func isActive(isMember: Bool?) -> Bool { isMember != true }

    var group: NeighborhoodGroup? { groupModel.state.value?.group }
}

/// T-187 : remplace « Ta part » sur la fiche d'un lot en consultation.
struct OfferConsultationNote: View {
    let groupName: String

    @Environment(\.groupTheme) private var theme

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rejoins ce groupe pour réserver ta part")
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("Tu vois le lot de \(groupName) en consultation : les parts se réservent entre familles du groupe, qui partagent la commande et la cueillette.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lock.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Action principale d'un visiteur (fiche publique du groupe et lot en consultation) :
/// « Rejoindre le groupe » (public), ou « Demander une invitation » et « J'ai déjà une invitation » (privé).
struct GroupJoinBar: View {
    let group: NeighborhoodGroup
    let viewModel: GroupDetailViewModel

    @Environment(\.groupTheme) private var theme
    @Environment(\.appContext) private var context
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Groupe privé : feuille « Rejoindre avec un code ».
    @State private var isJoiningWithCode = false

    var body: some View {
        VStack(spacing: 8) {
            if group.isPublic {
                Button {
                    Task {
                        await viewModel.join()
                        await contextStore?.reload(preferring: group.id)
                    }
                } label: {
                    Group {
                        if viewModel.isUpdatingMembership {
                            ProgressView()
                        } else {
                            Label("Rejoindre le groupe", systemImage: "person.badge.plus")
                                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3)), isActive: !reduceMotion)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .disabled(viewModel.isUpdatingMembership)
                .accessibilityHint("Ton ménage rejoint \(group.name) et voit tous ses lots.")
            } else {
                // Groupe privé : on demande une invitation à un voisin qui en fait partie, ou on entre son code.
                ShareLink(item: GroupPublicContent.invitationRequest(for: group)) {
                    Label("Demander une invitation", systemImage: "envelope.badge.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .accessibilityHint("Envoie une demande à un voisin qui fait partie du groupe.")
                Button {
                    isJoiningWithCode = true
                } label: {
                    Label("J'ai déjà une invitation", systemImage: "ticket.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $isJoiningWithCode) {
            JoinWithCodeSheet(repositories: context.repositories, householdId: context.householdId) { joined in
                Task {
                    await viewModel.load()
                    await contextStore?.reload(preferring: joined.id)
                }
            }
        }
    }
}
