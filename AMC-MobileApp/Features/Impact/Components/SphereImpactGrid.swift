import SwiftUI

/// Présentation des 7 sphères (`ImpactSphere`, défini dans `ImpactMetrics.swift`) : icône, teinte et mesure d'un `ImpactSnapshot`.
extension ImpactSphere {
    var systemImage: String {
        switch self {
        case .foodSecurity: "basket.fill"
        case .localEconomy: "storefront.fill"
        case .neighborhoodLife: GrenierSymbol.groups
        case .environment: GrenierSymbol.impact
        case .mobility: "figure.walk"
        case .inclusion: GrenierSymbol.solidarity
        case .health: "carrot.fill"
        }
    }

    /// Economie pour l'argent économisé, Solidarite pour l'aide, Grenier pour le reste.
    var tint: Color {
        switch self {
        case .foodSecurity: .economie
        case .inclusion: .solidarite
        default: .grenier
        }
    }

    /// Valeur mise en avant et phrase qui l'explique, tirées de l'instantané.
    func metric(in snapshot: ImpactSnapshot) -> SphereMetric {
        let s = snapshot
        switch self {
        case .foodSecurity:
            return SphereMetric(
                value: Double(s.neighborhoodSavedCents), format: .money,
                sentence: "économisés par \(ImpactFormat.plural(s.households, "famille")), et \(ImpactFormat.plural(s.suspendedBasketsOffered, "panier suspendu offert", "paniers suspendus offerts"))"
            )
        case .localEconomy:
            return SphereMetric(
                value: Double(s.paidToProducersCents), format: .money,
                sentence: "versés en direct à \(ImpactFormat.plural(s.producers, "ferme")) du Québec pour \(ImpactFormat.decimal(s.kilogramsBought / 1_000))\(ImpactFormat.nbsp)t de produits"
            )
        case .neighborhoodLife:
            return SphereMetric(
                value: Double(s.households), format: .integer(),
                sentence: "ménages qui se retrouvent chaque semaine grâce à \(ImpactFormat.plural(s.hosts, "hôte")) de cueillette"
            )
        case .environment:
            return SphereMetric(
                value: Double(s.packagingAvoided), format: .integer(),
                sentence: "emballages évités grâce au vrac, et \(ImpactFormat.plural(s.deliveryTripsAvoided, "trajet")) de livraison en moins"
            )
        case .mobility:
            return SphereMetric(
                value: s.groceryKilometersAvoided, format: .reduction(unit: "km"),
                sentence: "de trajets vers l'épicerie : \(ImpactFormat.plural(s.groceryTripsAvoided, "trajet")) évités, la cueillette se fait à pied"
            )
        case .inclusion:
            return SphereMetric(
                value: Double(s.householdsHelped), format: .integer(),
                sentence: "ménages aidés par un panier suspendu, sans savoir de qui"
            )
        case .health:
            return SphereMetric(
                value: s.freshProduceShare, format: .percent,
                sentence: "des achats en fruits, légumes et légumineuses"
            )
        }
    }
}

/// Valeur d'une sphère : nombre animé + phrase.
struct SphereMetric: Sendable, Hashable {
    let value: Double
    let format: CounterFormat
    let sentence: String

    var valueText: String { format.string(for: value) }
}

/// Grille « Ton quartier » (maquette F6) : une tuile par sphère de Montréal bonifiée par Grenier.
/// 2 colonnes, 1 seule en tailles d'accessibilité (AX1 à AX5). La 7e tuile prend toute la largeur.
struct SphereImpactGrid: View {
    let snapshot: ImpactSnapshot
    var spheres: [ImpactSphere] = ImpactSphere.allCases

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(snapshot: ImpactSnapshot, spheres: [ImpactSphere] = ImpactSphere.allCases) {
        self.snapshot = snapshot
        self.spheres = spheres
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(spheres) { tile($0) }
            }
        } else {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Self.rows(of: spheres), id: \.first) { row in
                    GridRow {
                        ForEach(row) { sphere in
                            tile(sphere).gridCellColumns(row.count == 1 ? 2 : 1)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ sphere: ImpactSphere) -> some View {
        SphereTile(sphere: sphere, metric: sphere.metric(in: snapshot))
    }

    /// Paires de sphères ; la dernière ligne peut n'en contenir qu'une.
    static func rows(of spheres: [ImpactSphere]) -> [[ImpactSphere]] {
        stride(from: 0, to: spheres.count, by: 2).map { Array(spheres[$0..<min($0 + 2, spheres.count)]) }
    }
}

/// Une tuile de sphère : symbole et nom de la sphère, valeur animée, phrase.
struct SphereTile: View {
    let sphere: ImpactSphere
    let metric: SphereMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(sphere.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sphere.tint)
            } icon: {
                Image(systemName: sphere.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sphere.tint)
            }
            .padding(.bottom, 4)

            AnimatedCounter(value: metric.value, format: metric.format)
                .priceStyle()
                .foregroundStyle(.texte)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(metric.sentence)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .grenierCard(padding: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sphere.title). \(metric.format.accessibilityString(for: metric.value)) \(metric.sentence)")
    }
}

#Preview("Clair") {
    ScrollView { SphereImpactGrid(snapshot: .demo).padding() }
        .grenierBackground()
}

#Preview("Sombre") {
    ScrollView { SphereImpactGrid(snapshot: .demo).padding() }
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView { SphereImpactGrid(snapshot: .demo).padding() }
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}
