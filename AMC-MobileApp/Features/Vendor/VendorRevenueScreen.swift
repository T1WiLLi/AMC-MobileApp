import Charts
import SwiftUI

/// Onglet Revenus du portail Vendeur (T-037) : revenus prévus, par lot, par quartier, familles servies
/// et prochaines livraisons. Lit `VendorDashboardViewModel` via `VendorRevenueModel`.
struct VendorRevenueScreen: View {
    @State private var model: VendorRevenueModel

    init(repositories: AppRepositories = .fake(), vendorId: String = FakeData.ID.fermeRive) {
        _model = State(initialValue: VendorRevenueModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack {
            StateView(
                state: model.state,
                empty: .init(
                    title: "Aucun revenu prévu",
                    systemImage: "dollarsign.circle",
                    message: "Publie un lot : tes revenus s'afficheront ici dès que des familles s'engagent."
                ),
                retry: { await model.load() }
            ) { revenue in
                ScrollView {
                    VendorRevenueContent(revenue: revenue)
                }
                .refreshable { await model.refresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Revenus")
            .profileToolbar()
        }
        .task {
            if case .idle = model.state { await model.load() }
        }
    }
}

// MARK: - Contenu

struct VendorRevenueContent: View {
    let revenue: VendorRevenue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TotalCard(revenue: revenue)
            KeyFigures(revenue: revenue)

            SectionTitle("Par lot")
            OfferRevenueChart(offers: revenue.offers)
                .grenierCard()

            if !revenue.neighborhoods.isEmpty {
                SectionTitle("Par quartier")
                NeighborhoodList(neighborhoods: revenue.neighborhoods)
            }

            SectionTitle("Prochaines livraisons")
            DeliveryList(deliveries: revenue.deliveries)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.texte)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Grand montant : revenus prévus totaux.
private struct TotalCard: View {
    let revenue: VendorRevenue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Revenus prévus")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Text(Money.format(revenue.totalCents))
                .priceStyle(.largeTitle.bold())
                .foregroundStyle(.texte)
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.grenier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let count = revenue.offers.count
        let lots = count == 1 ? "1 lot ouvert" : "\(count) lots ouverts"
        if let top = revenue.topOffer {
            return "\(lots) · surtout \(top.title.lowercased())"
        }
        return "\(lots) · aucun palier atteint pour l'instant"
    }
}

/// Familles servies et parts engagées, côte à côte (empilées aux grandes tailles de texte).
private struct KeyFigures: View {
    let revenue: VendorRevenue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            FigureTile(
                title: "Familles servies",
                value: revenue.familiesServed.formatted(),
                detail: neighborhoodsDetail,
                systemImage: GrenierSymbol.groups
            )
            FigureTile(
                title: "Parts engagées",
                value: revenue.committedShares.formatted(),
                detail: "sur \(revenue.totalShares.formatted()) offertes",
                systemImage: GrenierSymbol.offers
            )
        }
    }

    private var neighborhoodsDetail: String {
        switch revenue.neighborhoods.count {
        case 0: "aucun quartier encore"
        case 1: "dans 1 quartier"
        case let count: "dans \(count) quartiers"
        }
    }
}

private struct FigureTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .priceStyle()
                .foregroundStyle(.texte)
                .contentTransition(.numericText())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(value), \(detail)")
    }
}

// MARK: - Revenus par lot (Swift Charts)

private struct OfferRevenueChart: View {
    let offers: [VendorRevenue.OfferRevenue]

    /// Hauteur d'une barre et de son libellé ; grandit avec Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var barThickness: CGFloat = 16

    var body: some View {
        Chart(offers) { offer in
            // Piste derrière chaque barre, comme les paliers.
            BarMark(
                xStart: .value("Début", 0),
                xEnd: .value("Maximum", maxDollars),
                y: .value("Lot", offer.title),
                height: .fixed(barThickness)
            )
            .foregroundStyle(Color.piste)
            .clipShape(.capsule)

            BarMark(
                xStart: .value("Début", 0),
                xEnd: .value("Revenu prévu", Double(offer.revenueCents) / 100),
                y: .value("Lot", offer.title),
                height: .fixed(barThickness)
            )
            .foregroundStyle(Color.grenier)
            .clipShape(.capsule)
            .annotation(position: .top, alignment: .leading, spacing: 6) {
                OfferBarLabel(offer: offer)
            }
        }
        .chartXScale(domain: 0...maxDollars)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: rowHeight * CGFloat(max(offers.count, 1)))
        .accessibilityChartDescriptor(OfferRevenueChartDescriptor(offers: offers))
    }

    /// Évite une échelle nulle quand aucun lot n'a encore de revenu.
    private var maxDollars: Double {
        max(Double(offers.map(\.revenueCents).max() ?? 0) / 100, 1)
    }
}

private struct OfferBarLabel: View {
    let offer: VendorRevenue.OfferRevenue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(offer.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texte)
            Text(Money.format(offer.revenueCents))
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(offer.revenueCents > 0 ? Color.grenier : Color.texteSecondaire)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Graphique audio et description VoiceOver des revenus par lot.
private struct OfferRevenueChartDescriptor: AXChartDescriptorRepresentable {
    let offers: [VendorRevenue.OfferRevenue]

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxDollars = max(Double(offers.map(\.revenueCents).max() ?? 0) / 100, 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Lot", categoryOrder: offers.map(\.title))
        let yAxis = AXNumericDataAxisDescriptor(title: "Revenu prévu", range: 0...maxDollars, gridlinePositions: []) { value in
            Money.format(Cents((value * 100).rounded()))
        }
        let series = AXDataSeriesDescriptor(
            name: "Revenus prévus par lot",
            isContinuous: false,
            dataPoints: offers.map { offer in
                AXDataPoint(
                    x: offer.title,
                    y: Double(offer.revenueCents) / 100,
                    label: "\(offer.committedShares) parts sur \(offer.totalShares)"
                )
            }
        )
        return AXChartDescriptor(
            title: "Revenus prévus par lot",
            summary: offers.first.map { "\($0.title) rapporte le plus : \(Money.format($0.revenueCents))." },
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Revenus par quartier

private struct NeighborhoodList: View {
    let neighborhoods: [VendorRevenue.NeighborhoodRevenue]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(neighborhoods.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                NeighborhoodRow(entry: entry)
            }
        }
        .padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: 24))
    }
}

private struct NeighborhoodRow: View {
    let entry: VendorRevenue.NeighborhoodRevenue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 44

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: GrenierSymbol.map)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.neighborhood)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Money.format(entry.revenueCents))
                .priceStyle(.priceCompact)
                .foregroundStyle(entry.revenueCents > 0 ? .texte : .texteSecondaire)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.neighborhood), \(Money.format(entry.revenueCents)). \(detail)")
    }

    private var detail: String {
        let families = entry.households == 1 ? "1 famille" : "\(entry.households) familles"
        return "\(entry.groupNames.formatted(.list(type: .and))) · \(families)"
    }
}

// MARK: - Prochaines livraisons

private struct DeliveryList: View {
    let deliveries: [VendorRevenue.Delivery]

    var body: some View {
        if deliveries.isEmpty {
            Label("Aucun lot ne ferme dans les 3 prochains jours.", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
        } else {
            VStack(spacing: 12) {
                ForEach(deliveries) { delivery in
                    DeliveryCard(delivery: delivery)
                }
            }
        }
    }
}

private struct DeliveryCard: View {
    let delivery: VendorRevenue.Delivery
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: GrenierSymbol.offers)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .frame(width: iconSize, height: iconSize)
                        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(delivery.offerTitle)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(closesText, systemImage: "clock.fill")
                    .foregroundStyle(Color.grenier)
                    .font(.subheadline.weight(.semibold))
                Label(pickupText, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(delivery.pickupPointName == nil ? .texteSecondaire : .texte)
                    .font(.subheadline)
                if let start = delivery.pickupStart {
                    Label("Cueillette \(start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))",
                          systemImage: "calendar")
                        .foregroundStyle(.texteSecondaire)
                        .font(.subheadline)
                }
            }
            .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let group = delivery.groupName else { return "Aucune commande pour l'instant" }
        let shares = delivery.shares == 1 ? "1 part" : "\(delivery.shares) parts"
        return "\(group) · \(shares) · \(Money.format(delivery.revenueCents))"
    }

    private var closesText: String {
        "Ferme \(delivery.deadline.formatted(.relative(presentation: .named)))"
    }

    private var pickupText: String {
        delivery.pickupPointName ?? "Point de cueillette à choisir"
    }
}

// MARK: - Données de démo

#if DEBUG
extension FakeData {
    /// Jeu plus riche pour les previews Revenus : Ferme Bio-Rive livre trois quartiers.
    static let vendorRevenueDemo: FakeData = {
        var data = FakeData.montreal
        let day: TimeInterval = 86_400
        let thursday = Date.now.addingTimeInterval(2 * day + 4 * 3_600)
        let slot = PickupSlot(start: thursday, end: thursday.addingTimeInterval(90 * 60))

        data.groups += [
            NeighborhoodGroup(id: "group-parc-ex-ouest", name: "Parc-Ex Ouest", neighborhood: "Parc-Extension",
                              centerGeohash: "f25du", radiusMeters: 800, coordinatorIds: [], householdCount: 24,
                              isPublic: true, inviteCode: "PX-2026"),
            NeighborhoodGroup(id: "group-villeray", name: "Villeray en commun", neighborhood: "Villeray",
                              centerGeohash: "f25dt", radiusMeters: 900, coordinatorIds: [], householdCount: 15,
                              isPublic: true, inviteCode: "VI-2026"),
        ]
        data.pickupPoints += [
            PickupPoint(id: "pickup-ogilvy", hostUserId: "user-fatima", name: "Chez Fatima, 7420 rue Ogilvy",
                        address: "7420 rue Ogilvy, Parc-Extension, Montréal", photoURL: nil, capacity: 30,
                        accessibility: [.stepFree], slots: [slot]),
            PickupPoint(id: "pickup-hochelaga", hostUserId: "user-luc", name: "Centre communautaire Hochelaga",
                        address: "1700 rue Davidson, Montréal", photoURL: nil, capacity: 40,
                        accessibility: [.wheelchair, .nearMetro], slots: [slot]),
        ]
        data.groupOrders += [
            GroupOrder(id: "order-hochelaga-pommes-de-terre", groupId: FakeData.ID.hochelaga,
                       offerId: FakeData.ID.potatoOffer, status: .open, currentTierIndex: 0, committedShares: 14,
                       committedHouseholds: 9, pickupPointId: "pickup-hochelaga", pickupSlots: [slot]),
            GroupOrder(id: "order-parc-ex-pommes", groupId: "group-parc-ex-ouest", offerId: FakeData.ID.appleOffer,
                       status: .reached, currentTierIndex: 1, committedShares: 16, committedHouseholds: 13,
                       pickupPointId: "pickup-ogilvy", pickupSlots: [slot]),
            GroupOrder(id: "order-villeray-pommes", groupId: "group-villeray", offerId: FakeData.ID.appleOffer,
                       status: .open, currentTierIndex: 0, committedShares: 7, committedHouseholds: 6,
                       pickupPointId: nil, pickupSlots: []),
        ]
        return data
    }()
}
#endif

#Preview("Clair") {
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo))
}

#Preview("Sombre") {
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo))
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo))
        .dynamicTypeSize(.accessibility5)
}

#Preview("Données de base") {
    VendorRevenueScreen()
}

#Preview("Vide") {
    VendorRevenueScreen(vendorId: "vendor-inconnu")
}

#Preview("Hors ligne") {
    VendorRevenueScreen(repositories: .fake(behavior: .failing(.offline)))
}
