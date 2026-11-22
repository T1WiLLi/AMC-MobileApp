import SwiftUI

/// Route vers la fiche publique d'un groupe depuis le portail Organismes (T-208).
struct OrganizationGroupRoute: Hashable, Sendable {
    let groupId: String
}

extension View {
    /// Enregistre la fiche publique d'un groupe dans le `NavigationStack` d'un onglet du portail Organismes.
    func organizationGroupDestination(model: OrganizationPortalModel) -> some View {
        grenierZoomDestination(for: OrganizationGroupRoute.self) { route in
            OrganizationGroupScreen(model: model, groupId: route.groupId)
        }
    }
}

/// T-208 : fiche publique d'un groupe vue par un organisme. C'est celle du portail Famille pour un non-membre
/// (`GroupDetailScreen` → `GroupPublicContent`, #268 : bannière, photo, familles, lots ouverts, avis), avec, à la place
/// de « Pourquoi rejoindre », le fonds de solidarité du groupe, et à la place de « Rejoindre », Financer et Parrainer.
struct OrganizationGroupScreen: View {
    let model: OrganizationPortalModel
    let groupId: String

    @State private var showsDonation = false
    @State private var showsSponsor = false

    var body: some View {
        GroupDetailScreen(groupId: groupId, visitorAddOn: GroupVisitorAddOn {
            OrganizationGroupSolidarityCard(model: model, groupId: groupId)
        } bar: {
            OrganizationGroupActionBar(
                isSponsored: model.sponsorship(ofGroup: groupId) != nil,
                canAct: model.profile(id: groupId) != nil,
                onFund: { showsDonation = true },
                onSponsor: { showsSponsor = true }
            )
        })
        .sheet(isPresented: $showsDonation) {
            DonationSheet(model: model, groupId: groupId)
        }
        .sheet(isPresented: $showsSponsor) {
            SponsorSheet(model: model, groupId: groupId)
        }
        .grenierHaptic(.success, trigger: model.completedActions)
    }
}

/// Fonds de solidarité du groupe, besoin et parrainage de l'organisme connecté.
struct OrganizationGroupSolidarityCard: View {
    let model: OrganizationPortalModel
    let groupId: String

    var body: some View {
        if let profile = model.profile(id: groupId) {
            VStack(alignment: .leading, spacing: 12) {
                OrganizationSectionTitle("Solidarité dans ce groupe", systemImage: "heart.circle.fill", tint: .solidarite)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(Money.formatRounded(profile.fund.balanceCents), systemImage: "banknote.fill")
                            .font(.title3.bold())
                            .foregroundStyle(Color.texte)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.numericText(value: Double(profile.fund.balanceCents)))
                        Text("dans le fonds")
                            .font(.subheadline)
                            .foregroundStyle(Color.texteSecondaire)
                        Spacer(minLength: 8)
                        NeedBadge(level: profile.needLevel)
                    }
                    CoverageBar(profile: profile)
                    if let sponsorship = model.sponsorship(ofGroup: groupId) {
                        Label("Ton organisme parraine ce groupe : \(FrenchPlural.count(sponsorship.monthlyBasketGoal, "panier")) par mois",
                              systemImage: "hands.and.sparkles.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.grenier)
                            .symbolRenderingMode(.hierarchical)
                    } else if profile.basketsMissing > 0 {
                        Label("\(FrenchPlural.count(profile.basketsMissing, "panier manque", plural: "paniers manquent")) pour couvrir chaque famille aidée une fois.",
                              systemImage: "basket.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.texteSecondaire)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text("Les familles aidées restent anonymes : tu vois des totaux, jamais qui reçoit un panier.")
                        .font(.caption)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .grenierCard()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// « Financer des paniers » (action principale) et « Parrainer » en bas de la fiche publique.
struct OrganizationGroupActionBar: View {
    let isSponsored: Bool
    let canAct: Bool
    let onFund: () -> Void
    let onSponsor: () -> Void

    @Environment(\.groupTheme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .disabled(!canAct)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onFund) {
            Label("Financer des paniers", systemImage: "basket.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(theme.accent)
        .controlSize(.large)
        .accessibilityHint("Offre des paniers suspendus ou un don au fonds du groupe.")
        Button(action: onSponsor) {
            Label(isSponsored ? String(localized: "Mon parrainage") : String(localized: "Parrainer"),
                  systemImage: "hands.and.sparkles.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityHint("Promets au groupe des paniers chaque mois.")
    }
}

#if DEBUG
#Preview("Fiche publique, organisme") {
    let repositories = AppContext.instant.repositories
    let model = OrganizationPortalModel(repository: repositories.organizations, groups: repositories.groups,
                                        organizationId: FakeData.ID.laRuche)
    NavigationStack {
        OrganizationGroupScreen(model: model, groupId: FakeData.ID.hochelaga)
    }
    .environment(\.appContext, .instant)
    .task { await model.load() }
}
#endif
