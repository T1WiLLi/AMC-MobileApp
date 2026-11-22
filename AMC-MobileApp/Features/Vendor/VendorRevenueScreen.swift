import Charts
import SwiftUI

/// Onglet Revenus du portail Vendeur (T-037) : revenus prévus, par lot, par quartier, familles servies
/// et prochaines livraisons. Lit `VendorDashboardViewModel` via `VendorRevenueModel`.
///
/// T-085 : SF Symbols partout (en-tête illustré, chiffres clés, titres de section, lots, quartiers, livraisons),
/// squelette de chargement et état vide illustrés. Les effets de symbole sont coupés sous Reduce Motion.
struct VendorRevenueScreen: View {
    @State private var model: VendorRevenueModel

    init(repositories: AppRepositories, vendorId: String) {
        _model = State(initialValue: VendorRevenueModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .grenierBackground()
                .navigationTitle("Revenus")
                .profileToolbar()
        }
        .task {
            if case .idle = model.state { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            VendorRevenueSkeleton()
        case .empty:
            VendorRevenueEmptyState()
        case .failed, .loaded:
            StateView(state: model.state, retry: { await model.load() }) { revenue in
                ScrollView {
                    VendorRevenueContent(revenue: revenue)
                }
                .refreshable { await model.refresh() }
            }
        }
    }
}

// MARK: - Contenu

struct VendorRevenueContent: View {
    let revenue: VendorRevenueSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TotalCard(revenue: revenue)
            KeyFigures(revenue: revenue)
            ProductStatsLink() // T-119 : statistiques de ventes par produit

            SectionTitle("Par lot", systemImage: "chart.bar.xaxis", tint: .grenier)
            OfferRevenueChart(offers: revenue.offers)
                .grenierCard()

            if !revenue.neighborhoods.isEmpty {
                SectionTitle("Par quartier", systemImage: GrenierSymbol.map, tint: .solidarite)
                NeighborhoodList(neighborhoods: revenue.neighborhoods)
            }

            SectionTitle("Prochaines livraisons", systemImage: "truck.box.fill", tint: .economie)
            DeliveryList(deliveries: revenue.deliveries)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.title2.bold())
        .foregroundStyle(.texte)
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

/// En-tête : composition de symboles et grand montant des revenus prévus.
private struct TotalCard: View {
    let revenue: VendorRevenueSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                Label("Revenus prévus", systemImage: "banknote.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                Text(Money.format(revenue.totalCents))
                    .priceStyle(.largeTitle.bold())
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(revenue.totalCents)))
                    .grenierAnimation(.smooth, value: revenue.totalCents)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Label {
                    Text(caption)
                } icon: {
                    Image(systemName: revenue.topOffer == nil ? "hourglass" : "star.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.grenier)
                .symbolRenderingMode(.hierarchical)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VendorRevenueHeroArt()
        }
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let count = revenue.offers.count
        let lots = count == 1 ? String(localized: "1 lot ouvert") : String(localized: "\(count) lots ouverts")
        if let top = revenue.topOffer {
            return String(localized: "\(lots) · surtout \(top.title.lowercased())")
        }
        return String(localized: "\(lots) · aucun palier atteint pour l'instant")
    }
}

/// Composition de symboles : billets au centre, entourés de la courbe, des familles et des caisses.
private struct VendorRevenueHeroArt: View {
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.economie.opacity(0.12))
            Image(systemName: "banknote.fill")
                .font(.system(size: side * 0.36))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
            satellite("chart.line.uptrend.xyaxis", tint: .grenier, angle: -45)
            satellite(GrenierSymbol.groups, tint: .solidarite, angle: 75)
            satellite(GrenierSymbol.offers, tint: .grenier, angle: 195)
        }
        .frame(width: side, height: side)
        .padding(8)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func satellite(_ symbol: String, tint: Color, angle: Double) -> some View {
        let radius = side * 0.5
        let radians = angle * .pi / 180
        return Image(systemName: symbol)
            .font(.system(size: side * 0.15))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: side * 0.3, height: side * 0.3)
            .background(Color.surface, in: .circle)
            .offset(x: cos(radians) * radius, y: sin(radians) * radius)
    }
}

/// Familles servies et parts engagées, côte à côte (empilées aux grandes tailles de texte).
private struct KeyFigures: View {
    let revenue: VendorRevenueSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            FigureTile(
                title: String(localized: "Familles servies"),
                value: revenue.familiesServed,
                detail: neighborhoodsDetail,
                detailImage: GrenierSymbol.map,
                systemImage: GrenierSymbol.groups,
                tint: .solidarite
            )
            FigureTile(
                title: String(localized: "Parts engagées"),
                value: revenue.committedShares,
                detail: String(localized: "sur \(revenue.totalShares.formatted()) offertes"),
                detailImage: "chart.pie.fill",
                systemImage: GrenierSymbol.offers,
                tint: .grenier
            )
        }
    }

    private var neighborhoodsDetail: String {
        switch revenue.neighborhoods.count {
        case 0: String(localized: "aucun quartier encore")
        case 1: String(localized: "dans 1 quartier")
        case let count: String(localized: "dans \(count) quartiers")
        }
    }
}

private struct FigureTile: View {
    let title: String
    let value: Int
    let detail: String
    let detailImage: String
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : value)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
            Text(value.formatted())
                .priceStyle()
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: Double(value)))
                .grenierAnimation(.smooth, value: value)
            Label(detail, systemImage: detailImage)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(value.formatted()), \(detail)")
    }
}

// MARK: - Revenus par lot (Swift Charts)

private struct OfferRevenueChart: View {
    let offers: [VendorRevenueSummary.OfferRevenue]

    /// Hauteur d'une barre et de son libellé ; grandit avec Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var barThickness: CGFloat = 16

    var body: some View {
        Chart(offers) { offer in
            // Piste derrière chaque barre, comme les paliers.
            BarMark(
                xStart: .value(String(localized: "Début"), 0),
                xEnd: .value(String(localized: "Maximum"), maxDollars),
                y: .value(String(localized: "Lot"), offer.title),
                height: .fixed(barThickness)
            )
            .foregroundStyle(Color.piste)
            .clipShape(.capsule)

            BarMark(
                xStart: .value(String(localized: "Début"), 0),
                xEnd: .value(String(localized: "Revenu prévu"), Double(offer.revenueCents) / 100),
                y: .value(String(localized: "Lot"), offer.title),
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

/// Libellé d'une barre : sceau du palier atteint (ou caisse), nom du lot et montant.
private struct OfferBarLabel: View {
    let offer: VendorRevenueSummary.OfferRevenue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: offer.tierNumber == nil ? "shippingbox" : "checkmark.seal.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(offer.tierNumber == nil ? Color.texteSecondaire : Color.grenier)
            Text(offer.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texte)
            if let tier = offer.tierNumber {
                Text("P\(tier)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.grenier)
                    .accessibilityLabel("Palier \(tier)")
            }
            Text(Money.format(offer.revenueCents))
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(offer.revenueCents > 0 ? Color.grenier : Color.texteSecondaire)
                .contentTransition(.numericText(value: Double(offer.revenueCents)))
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Graphique audio et description VoiceOver des revenus par lot.
private struct OfferRevenueChartDescriptor: AXChartDescriptorRepresentable {
    let offers: [VendorRevenueSummary.OfferRevenue]

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxDollars = max(Double(offers.map(\.revenueCents).max() ?? 0) / 100, 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Lot"), categoryOrder: offers.map(\.title))
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Revenu prévu"), range: 0...maxDollars, gridlinePositions: []) { value in
            Money.format(Cents((value * 100).rounded()))
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Revenus prévus par lot"),
            isContinuous: false,
            dataPoints: offers.map { offer in
                AXDataPoint(
                    x: offer.title,
                    y: Double(offer.revenueCents) / 100,
                    label: String(localized: "\(offer.committedShares) parts sur \(offer.totalShares)")
                )
            }
        )
        return AXChartDescriptor(
            title: String(localized: "Revenus prévus par lot"),
            summary: offers.first.map { String(localized: "\($0.title) rapporte le plus : \(Money.format($0.revenueCents)).") },
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Revenus par quartier

private struct NeighborhoodList: View {
    let neighborhoods: [VendorRevenueSummary.NeighborhoodRevenue]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(neighborhoods.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                NeighborhoodRow(entry: entry, rank: index)
            }
        }
        .padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: 24))
    }
}

private struct NeighborhoodRow: View {
    let entry: VendorRevenueSummary.NeighborhoodRevenue
    /// Rang du quartier (0 = celui qui rapporte le plus).
    let rank: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 44

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: rank == 0 && entry.revenueCents > 0 ? "crown.fill" : "mappin.and.ellipse")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.neighborhood)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label(groupsText, systemImage: GrenierSymbol.groups)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                Label(familiesText, systemImage: "house.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, alignment: .leading)
            Label {
                Text(Money.format(entry.revenueCents))
                    .priceStyle(.priceCompact)
                    .foregroundStyle(entry.revenueCents > 0 ? .texte : .texteSecondaire)
                    .contentTransition(.numericText(value: Double(entry.revenueCents)))
            } icon: {
                Image(systemName: "dollarsign.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.neighborhood), \(Money.format(entry.revenueCents)). \(groupsText) · \(familiesText)")
    }

    private var groupsText: String { entry.groupNames.formatted(.list(type: .and).locale(AppLanguage.formattingLocale)) }

    private var familiesText: String {
        entry.households == 1 ? String(localized: "1 famille") : String(localized: "\(entry.households) familles")
    }
}

// MARK: - Prochaines livraisons

private struct DeliveryList: View {
    let deliveries: [VendorRevenueSummary.Delivery]

    var body: some View {
        if deliveries.isEmpty {
            NoDeliveryCard()
        } else {
            VStack(spacing: 12) {
                ForEach(deliveries) { delivery in
                    DeliveryCard(delivery: delivery)
                        .grenierTransition(.cardAppear)
                }
            }
        }
    }
}

/// Aucune livraison dans les 3 jours : petite scène calendrier coché + camion au repos.
private struct NoDeliveryCard: View {
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 56

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "calendar")
                    .font(.system(size: side * 0.5))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
                    .frame(width: side, height: side)
                    .background(Color.economie.opacity(0.12), in: .rect(cornerRadius: 16))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: side * 0.3))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
                    .background(Color.surface, in: .circle)
                    .offset(x: 6, y: 6)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rien à livrer d'ici 3 jours")
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("Aucun lot ne ferme dans les 3 prochains jours.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

private struct DeliveryCard: View {
    let delivery: VendorRevenueSummary.Delivery
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: delivery.groupName == nil ? "shippingbox" : "truck.box.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .frame(width: iconSize, height: iconSize)
                        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(delivery.offerTitle)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    orderLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(closesText)
                } icon: {
                    Image(systemName: "clock.fill")
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                }
                .foregroundStyle(Color.grenier)
                .font(.subheadline.weight(.semibold))
                Label(pickupText, systemImage: delivery.pickupPointName == nil ? "mappin.slash" : "mappin.and.ellipse")
                    .foregroundStyle(delivery.pickupPointName == nil ? .texteSecondaire : .texte)
                    .font(.subheadline)
                if let start = delivery.pickupStart {
                    Label("Cueillette \(start.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(AppLanguage.formattingLocale)))",
                          systemImage: "calendar.badge.clock")
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

    @ViewBuilder
    private var orderLabel: some View {
        if let group = delivery.groupName {
            let shares = delivery.shares == 1 ? String(localized: "1 part") : "\(delivery.shares) parts"
            Label("\(group) · \(shares) · \(Money.format(delivery.revenueCents))", systemImage: GrenierSymbol.groups)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .symbolRenderingMode(.hierarchical)
        } else {
            Label {
                Text("Aucune commande pour l'instant")
            } icon: {
                Image(systemName: "hourglass")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
        }
    }

    private var closesText: String {
        String(localized: "Ferme \(delivery.deadline.formatted(.relative(presentation: .named).locale(AppLanguage.formattingLocale)))")
    }

    private var pickupText: String {
        delivery.pickupPointName ?? String(localized: "Point de cueillette à choisir")
    }
}

// MARK: - Chargement, état vide

/// Squelette de chargement : grand montant, deux tuiles et le graphique en `.placeholder`.
private struct VendorRevenueSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Revenus prévus", systemImage: "banknote.fill")
                        .font(.subheadline)
                    Text("1 234,56 $")
                        .priceStyle(.largeTitle.bold())
                    Text("3 lots ouverts · surtout les pommes")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard(padding: 20)
                HStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Familles servies", systemImage: GrenierSymbol.groups)
                                .font(.subheadline)
                            Text("42").priceStyle()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .grenierCard()
                    }
                }
                Label("Par lot", systemImage: "chart.bar.xaxis")
                    .font(.title2.bold())
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        Text("Pommes Cortland · 480 $").font(.subheadline)
                        Capsule().fill(Color.piste).frame(height: 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
            }
            .padding(.horizontal, 16)
        }
        .redacted(reason: .placeholder)
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des revenus")
    }
}

/// État vide illustré : billets en attente, entourés d'une caisse et des familles.
private struct VendorRevenueEmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.economie.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "banknote")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.economie)
                    Image(systemName: GrenierSymbol.offers)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .padding(6)
                        .background(Color.fond, in: .circle)
                        .offset(x: 44, y: 38)
                    Image(systemName: "hourglass")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.solidarite)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                        .offset(x: -46, y: -38)
                }
                .accessibilityHidden(true)
                Text("Aucun revenu prévu")
            }
        } description: {
            Text("Cet écran suit l'argent de tes lots : ce que les familles ont réservé et ce qui te sera payé. Publie un lot depuis l'onglet Lots pour voir tes premiers revenus.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
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
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo), vendorId: FakeData.ID.fermeRive)
}

#Preview("Sombre") {
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo), vendorId: FakeData.ID.fermeRive)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorRevenueScreen(repositories: .fake(data: .vendorRevenueDemo), vendorId: FakeData.ID.fermeRive)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Données de base") {
    VendorRevenueScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
}

#Preview("Vide") {
    VendorRevenueScreen(repositories: .fake(), vendorId: "vendor-inconnu")
}

#Preview("Hors ligne") {
    VendorRevenueScreen(repositories: .fake(behavior: .failing(.offline)), vendorId: FakeData.ID.fermeRive)
}

#Preview("Chargement") {
    VendorRevenueSkeleton()
        .grenierBackground()
}
