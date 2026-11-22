import SwiftUI

/// Onglet Impact du portail Organismes (T-116) : récit d'impact à partager et fil des financements et parrainages.
struct OrganizationImpactScreen: View {
    let model: OrganizationPortalModel?

    var body: some View {
        NavigationStack {
            OrganizationStateContainer(model: model) { model, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notre impact", systemImage: "leaf.fill")
                                .font(.headline)
                                .foregroundStyle(Color.economie)
                                .symbolRenderingMode(.hierarchical)
                            Text(model.impactStory)
                                .font(.title3.bold())
                                .foregroundStyle(Color.texte)
                                .fixedSize(horizontal: false, vertical: true)
                            ShareLink(item: model.impactStory) {
                                Label("Partager", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.glass)
                            .tint(.grenier)
                        }
                        .grenierCard()
                        .grenierAppear(index: 0)

                        OrganizationKPIGrid(impact: model.impact)
                            .grenierAppear(index: 1)

                        OrganizationSectionTitle("Notre histoire", systemImage: "clock.arrow.circlepath")
                        if model.timeline.isEmpty {
                            EmptyStateView(title: "Pas encore d'histoire", systemImage: "leaf",
                                           message: "Chaque panier financé par ton organisme laisse une trace ici. Finance un premier panier pour commencer l'histoire.")
                        }
                        ForEach(Array(model.timeline.enumerated()), id: \.element.id) { index, event in
                            TimelineRow(event: event)
                                .grenierAppear(index: 2 + index)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await model.load() }
            }
            .grenierBackground()
            .navigationTitle("Impact")
            .profileToolbar()
        }
    }
}

/// Une ligne du fil d'impact.
struct TimelineRow: View {
    let event: OrganizationPortalModel.TimelineEvent

    private var tint: Color {
        switch event.kind {
        case .baskets: .grenier
        case .fund: .solidarite
        case .sponsorship: .economie
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.formattingLocale)))
                    .font(.caption2)
                    .foregroundStyle(Color.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationImpactScreen(model: model)
        .task { await model.load() }
}

#Preview("Sombre") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationImpactScreen(model: model)
        .task { await model.load() }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationImpactScreen(model: model)
        .task { await model.load() }
        .dynamicTypeSize(.accessibility5)
}
