import SwiftUI

/// Onglet Financer du portail Organismes (T-116, RQ-081) : tous les groupes, du besoin le plus urgent au moins
/// urgent ; chaque carte ouvre la feuille de financement (paniers suspendus ou don au fonds, simulés).
struct OrganizationFundScreen: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case inNeed
        case sponsored

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: String(localized: "Tous")
            case .inNeed: String(localized: "En besoin")
            case .sponsored: String(localized: "Parrainés")
            }
        }
    }

    let model: OrganizationPortalModel?

    @State private var filter: Filter = .all
    @State private var donationTarget: GroupSolidarityProfile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            OrganizationStateContainer(model: model) { model, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        NeedSummaryCard(groups: model.groupsInNeed)
                        Picker("Filtre", selection: $filter.animation(.grenier(.snappy, reduceMotion: reduceMotion))) {
                            ForEach(Filter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        let groups = filtered(model)
                        if groups.isEmpty {
                            EmptyStateView(
                                title: "Aucun groupe ici",
                                systemImage: filter == .sponsored ? "hands.and.sparkles" : "checkmark.seal",
                                message: filter == .sponsored
                                    ? "Les groupes que ton organisme parraine apparaissent ici. Parraine un premier groupe dans l'onglet Parrainages."
                                    : "Ici apparaissent les groupes qui ont besoin d'aide. Tous sont couverts pour l'instant : merci !"
                            )
                        }
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, profile in
                            GroupNeedCard(
                                profile: profile,
                                distance: model.distanceText(for: profile),
                                isSponsored: profile.isSponsored(by: model.organizationId)
                            ) {
                                Button {
                                    donationTarget = profile
                                } label: {
                                    Label("Financer", systemImage: "heart.fill")
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.glass)
                                .tint(.grenier)
                            }
                            .contextMenu {
                                Button("Financer des paniers", systemImage: "basket.fill") { donationTarget = profile }
                            }
                            .grenierAppear(index: index)
                        }
                        SimulationNotice()
                            .padding(.top, 8)
                    }
                    .padding(16)
                }
                .refreshable { await model.load() }
                .sheet(item: $donationTarget) { profile in
                    DonationSheet(model: model, groupId: profile.groupId)
                }
            }
            .grenierBackground()
            .navigationTitle("Financer")
            .profileToolbar()
        }
        .grenierHaptic(.selection, trigger: filter)
    }

    private func filtered(_ model: OrganizationPortalModel) -> [GroupSolidarityProfile] {
        switch filter {
        case .all: model.prioritizedGroups
        case .inNeed: model.groupsInNeed
        case .sponsored: model.sponsoredGroups
        }
    }
}

/// Bandeau « 3 groupes attendent 32 paniers ».
struct NeedSummaryCard: View {
    let groups: [GroupSolidarityProfile]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var missing: Int { groups.reduce(0) { $0 + $1.basketsMissing } }

    /// Accord du verbe : « 1 panier manque », « 2 paniers manquent ».
    private var missingTitle: String {
        let count = FrenchPlural.count(missing, "panier")
        return missing == 1 ? String(localized: "\(count) manque") : String(localized: "\(count) manquent")
    }

    /// « 1 groupe n'a pas assez… », « 2 groupes n'ont pas assez… ».
    private var missingMessage: String {
        let count = FrenchPlural.count(groups.count, "groupe")
        return groups.count == 1
            ? String(localized: "\(count) n'a pas assez dans son fonds pour ses familles aidées.")
            : String(localized: "\(count) n'ont pas assez dans leur fonds pour leurs familles aidées.")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: missing > 0 ? "basket.fill" : "checkmark.seal.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(missing > 0 ? Color.solidarite : Color.economie)
                .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? 0 : missing)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(missing > 0 ? missingTitle : String(localized: "Tout est couvert"))
                    .font(.title3.bold())
                    .foregroundStyle(Color.texte)
                    .contentTransition(.numericText(value: Double(missing)))
                Text(missing > 0
                     ? missingMessage
                     : String(localized: "Chaque famille aidée a son panier réservé. Merci !"))
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .grenierAnimation(.smooth, value: missing)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationFundScreen(model: model)
        .task { await model.load() }
}

#Preview("Sombre") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationFundScreen(model: model)
        .task { await model.load() }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationFundScreen(model: model)
        .task { await model.load() }
        .dynamicTypeSize(.accessibility5)
}
