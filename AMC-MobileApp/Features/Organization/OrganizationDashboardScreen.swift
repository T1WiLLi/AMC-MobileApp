import Charts
import SwiftUI

/// Onglet Tableau du portail Organismes (T-116) : qui on est, chiffres d'impact, financement par mois
/// et les groupes qui ont le plus besoin d'aide maintenant.
struct OrganizationDashboardScreen: View {
    let model: OrganizationPortalModel?
    /// Ouvre l'onglet Financer.
    var onShowAllGroups: () -> Void = {}

    @State private var donationTarget: GroupSolidarityProfile?

    var body: some View {
        NavigationStack {
            OrganizationStateContainer(model: model) { model, snapshot in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        OrganizationHeroCard(organization: snapshot.organization)
                            .grenierAppear(index: 0)
                        OrganizationKPIGrid(impact: model.impact)
                            .grenierAppear(index: 1)
                        MonthlyFundingChart(months: model.impact.months)
                            .grenierAppear(index: 2)

                        OrganizationSectionTitle("Ils ont besoin de toi", systemImage: "exclamationmark.triangle.fill",
                                                 tint: .solidarite)
                        let needs = Array(model.groupsInNeed.prefix(3))
                        if needs.isEmpty {
                            Label("Tous les groupes ont de quoi couvrir leurs familles aidées. Bravo !",
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Color.economie)
                                .symbolRenderingMode(.hierarchical)
                                .grenierCard()
                        }
                        ForEach(Array(needs.enumerated()), id: \.element.id) { index, profile in
                            GroupNeedCard(
                                profile: profile,
                                distance: model.distanceText(for: profile),
                                isSponsored: profile.isSponsored(by: model.organizationId)
                            ) {
                                Button {
                                    donationTarget = profile
                                } label: {
                                    Label("Financer des paniers", systemImage: "heart.fill")
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.glass)
                                .tint(.grenier)
                            }
                            .grenierAppear(index: 3 + index)
                        }
                        Button(action: onShowAllGroups) {
                            Label("Voir tous les groupes", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .tint(.grenier)
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
            .navigationTitle("Tableau")
            .profileToolbar()
            .portalContentReady(.organization, when: isContentReady)
        }
    }
}

private extension OrganizationDashboardScreen {
    /// Le tableau montre autre chose que le squelette (sans modèle : rien à attendre).
    var isContentReady: Bool {
        guard let model else { return true }
        switch model.state {
        case .idle, .loading: return false
        default: return true
        }
    }
}

/// Carte d'en-tête : icône du type d'organisme, nom, mission.
struct OrganizationHeroCard: View {
    let organization: Organization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// L'icône grandit avec le texte : un cadre fixe de 56 pt la coupait aux très grandes tailles.
    @ScaledMetric(relativeTo: .title) private var badgeSize: CGFloat = 56
    @State private var appeared = false

    var body: some View {
        // Aux tailles d'accessibilité, l'icône passe au-dessus du nom au lieu de lui voler la largeur.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                Image(systemName: organization.kind.systemImage)
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.onAccent)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Color.grenier.gradient, in: .rect(cornerRadius: 16))
                    .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(organization.name)
                        .font(.title3.bold())
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("\(organization.kind.label) · \(organization.neighborhood)", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            Text(organization.mission)
                .font(.subheadline)
                .foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
    }
}

/// Grille des quatre chiffres clés.
struct OrganizationKPIGrid: View {
    let impact: OrganizationLedger.ImpactSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            OrganizationKPITile(title: "Paniers financés", value: "\(impact.basketsFunded)",
                                systemImage: "basket.fill", tint: .grenier, numericValue: impact.basketsFunded)
            OrganizationKPITile(title: "Familles aidées", value: "\(impact.familiesHelped)",
                                systemImage: "figure.2.and.child.holdinghands", tint: .solidarite,
                                numericValue: impact.familiesHelped)
            OrganizationKPITile(title: "Groupes parrainés", value: "\(impact.groupsSponsored)",
                                systemImage: "hands.and.sparkles.fill", tint: .grenier,
                                numericValue: impact.groupsSponsored)
            OrganizationKPITile(title: "Valeur d'épicerie pour les familles",
                                value: Money.formatRounded(impact.groceryValueCents / 100 * 100),
                                systemImage: "cart.fill", tint: .economie, numericValue: impact.groceryValueCents)
        }
    }
}

/// Barres « financement par mois » (Swift Charts), mois courant en Grenier plein.
struct MonthlyFundingChart: View {
    let months: [OrganizationLedger.ImpactSummary.Month]
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 160
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var total: Cents { months.reduce(0) { $0 + $1.amountCents } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Financement par mois")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Text("\(Money.formatRounded(total)) sur \(FrenchPlural.count(months.count, "mois", plural: "mois"))")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .contentTransition(.numericText(value: Double(total)))
                }
            } icon: {
                Image(systemName: "chart.bar.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            Chart(months) { month in
                BarMark(
                    x: .value("Mois", month.start, unit: .month),
                    y: .value("Montant", grown || reduceMotion ? Double(month.amountCents) / 100 : 0)
                )
                .foregroundStyle(month.id == months.last?.id ? Color.grenier : Color.grenier.opacity(0.35))
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).year()))
                .accessibilityValue("\(Money.formatRounded(month.amountCents)), \(FrenchPlural.count(month.baskets, "panier"))")
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text("\(Int(amount)) $") }
                    }
                }
            }
            .frame(height: chartHeight)
        }
        .grenierCard()
        .task {
            guard !reduceMotion, !grown else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.8)) { grown = true }
        }
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationDashboardScreen(model: model)
        .task { await model.load() }
}

#Preview("Sombre") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationDashboardScreen(model: model)
        .task { await model.load() }
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationDashboardScreen(model: model)
        .task { await model.load() }
        .dynamicTypeSize(.accessibility5)
}
