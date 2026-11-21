import MapKit
import SwiftUI

/// RQ-093 (T-114) : classement complet des arrondissements. Carte de Montréal avec les rangs,
/// puces des arrondissements (toucher = aller à la ligne), choix de la mesure, barres animées,
/// ton arrondissement surligné et l'explication du calcul.
struct SolidarityLeaderboardScreen: View {
    @Bindable var viewModel: SolidarityLeaderboardViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedId: String?

    var body: some View {
        let entries = viewModel.entries
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !entries.isEmpty {
                        LeaderboardMap(entries: entries, focusedId: focusedId) { id in
                            focus(id, proxy: proxy)
                        }
                        BoroughChips(entries: entries, focusedId: focusedId) { id in
                            focus(id, proxy: proxy)
                        }
                    }

                    MetricPicker(metric: $viewModel.metric)

                    if let home = viewModel.home {
                        HomeBoroughRow(entry: home, bestScore: entries.first?.score ?? 100)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(entry: entry, metric: viewModel.metric,
                                           bestScore: entries.first?.score ?? 100,
                                           isFocused: focusedId == entry.id, appearDelay: Double(index) * 0.04)
                                .id(entry.id)
                            if index < entries.count - 1 {
                                Divider().overlay(Color.piste)
                            }
                        }
                    }
                    .grenierCard(padding: 8)
                    .animation(reduceMotion ? nil : .smooth, value: viewModel.metric)

                    MethodCard()

                    Label("Chaque panier compte, dans tous les arrondissements. Merci !", systemImage: "heart.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.solidarite)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .grenierBackground()
        .navigationTitle("Classement solidaire")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.selection, trigger: viewModel.metric)
        .sensoryFeedback(.selection, trigger: focusedId)
        .toolbar {
            if let home = viewModel.home {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "\(home.stats.shortName) est \(home.rank)\(home.rank == 1 ? "er" : "e") au classement solidaire de Montréal sur Grenier !") {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func focus(_ id: String, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .smooth) {
            focusedId = id
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Carte

/// Carte de Montréal : une pastille par arrondissement avec son rang (or, argent, bronze ; toi en solidarité).
private struct LeaderboardMap: View {
    let entries: [SolidarityLeaderboard.Entry]
    let focusedId: String?
    let select: (String) -> Void

    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 220

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.52, longitude: -73.61),
            latitudinalMeters: 24_000, longitudinalMeters: 24_000
        ))) {
            ForEach(entries) { entry in
                Annotation(entry.stats.shortName, coordinate: GroupGeohash.center(of: entry.stats.centerGeohash)) {
                    Button {
                        select(entry.id)
                    } label: {
                        pin(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.stats.name), rang \(entry.rank)")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: min(height, 320))
        .clipShape(.rect(cornerRadius: 24))
        .overlay(alignment: .bottomLeading) {
            Label("Montréal", systemImage: "map.fill")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(12)
        }
    }

    private func pin(_ entry: SolidarityLeaderboard.Entry) -> some View {
        let tint: Color = entry.isHome ? .solidarite : (entry.isPodium ? Medal.tint(for: entry.rank) : .grenier)
        let isFocused = focusedId == entry.id
        return Text("\(entry.rank)")
            .font(.caption.bold())
            .fontDesign(.rounded)
            .foregroundStyle(Color.onAccent)
            .frame(minWidth: 28, minHeight: 28)
            .background(tint, in: .circle)
            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
            .scaleEffect(isFocused ? 1.35 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.25 : 0.1), radius: isFocused ? 6 : 2, y: 1)
    }
}

/// Puces des arrondissements, par rang ; toucher une puce amène à sa ligne.
private struct BoroughChips: View {
    let entries: [SolidarityLeaderboard.Entry]
    let focusedId: String?
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        Button {
                            select(entry.id)
                        } label: {
                            Label(entry.stats.shortName, systemImage: entry.isHome ? "house.fill" : "mappin.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(entry.isHome ? Color.solidarite : Color.texte)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(focusedId == entry.id ? .regular.tint(Color.grenier.opacity(0.25)).interactive() : .regular.interactive(),
                                     in: .capsule)
                        .accessibilityHint("Aller à \(entry.stats.name) dans le classement.")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .contentMargins(.horizontal, 2, for: .scrollContent)
    }
}

// MARK: - Mesure

private struct MetricPicker: View {
    @Binding var metric: SolidarityLeaderboard.Metric?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, title: "Score global", systemImage: "trophy.fill")
                ForEach(SolidarityLeaderboard.Metric.allCases) { item in
                    chip(item, title: item.title, systemImage: item.systemImage)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mesure du classement")
    }

    private func chip(_ value: SolidarityLeaderboard.Metric?, title: String, systemImage: String) -> some View {
        let isSelected = metric == value
        return Button {
            withAnimation(.snappy) { metric = value }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.onAccent : Color.texte)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.grenier : Color.surface, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Ligne

private struct LeaderboardRow: View {
    let entry: SolidarityLeaderboard.Entry
    let metric: SolidarityLeaderboard.Metric?
    let bestScore: Double
    let isFocused: Bool
    let appearDelay: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RankBadge(rank: entry.rank, isHome: entry.isHome)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.stats.name)
                        .font(.headline)
                        .foregroundStyle(.texte)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.isHome {
                        Text("Toi")
                            .font(.caption.bold())
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.solidarite, in: .capsule)
                    }
                    Spacer(minLength: 4)
                    ScoreText(score: entry.score, compact: true)
                }
                AnimatedScoreBar(fraction: bestScore > 0 ? entry.score / bestScore : 0,
                                 tint: entry.isHome ? .solidarite : (entry.isPodium ? Medal.tint(for: entry.rank) : .grenier),
                                 delay: appearDelay)
                Label(detail, systemImage: (metric ?? entry.strength).systemImage)
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
                    .contentTransition(.numericText())
                if let champion = entry.championOf.first, metric == nil {
                    Label(champion.championTitle, systemImage: "rosette")
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Medal.tint(for: 1))
                }
            }
        }
        .padding(10)
        .background(background, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(entry.score.rounded())) points")
    }

    private var background: Color {
        if isFocused { return Color.grenier.opacity(0.12) }
        return entry.isHome ? Color.solidarite.opacity(0.08) : .clear
    }

    private var detail: String {
        let shown = metric ?? entry.strength
        let value = entry.perHousehold[shown] ?? 0
        let locale = Locale(identifier: "fr_CA")
        let groups = "\(entry.stats.groupCount) \(entry.stats.groupCount > 1 ? "groupes" : "groupe")"
        let text: String = switch shown {
        case .baskets:
            "\((value * 100).formatted(.number.precision(.fractionLength(0)).locale(locale))) paniers offerts pour 100 ménages"
        case .familiesHelped:
            "\((value * 100).formatted(.number.precision(.fractionLength(0)).locale(locale))) familles aidées pour 100 ménages"
        case .savings:
            "\(Money.formatRounded(Cents(value.rounded()))) économisés par ménage"
        case .participation:
            "\(value.formatted(.percent.precision(.fractionLength(0)).locale(locale))) des ménages participent"
        }
        return metric == nil ? "\(text) · \(groups)" : text
    }
}

// MARK: - Méthode

private struct MethodCard: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tout est calculé par ménage : un petit arrondissement très engagé peut battre un grand. On ajoute à chacun quelques ménages « moyens » pour qu'un tout petit groupe ne s'envole pas sur un seul mois.")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(SolidarityLeaderboard.Metric.allCases) { metric in
                    HStack {
                        Label(metric.title, systemImage: metric.systemImage)
                            .symbolRenderingMode(.hierarchical)
                        Spacer()
                        Text(metric.weight.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "fr_CA"))))
                            .monospacedDigit()
                            .foregroundStyle(.texte)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .padding(.top, 8)
        } label: {
            Label("Comment on calcule", systemImage: "info.circle.fill")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texte)
        }
        .tint(Color.grenier)
        .grenierCard()
    }
}

#Preview("Classement") {
    @Previewable @State var viewModel = SolidarityLeaderboardViewModel(
        repositories: AppContext.instant.repositories, groupId: FakeData.ID.saintMichel
    )
    NavigationStack {
        SolidarityLeaderboardScreen(viewModel: viewModel)
    }
    .task { await viewModel.load() }
}

#Preview("Classement — sombre") {
    @Previewable @State var viewModel = SolidarityLeaderboardViewModel(
        repositories: AppContext.instant.repositories, groupId: FakeData.ID.saintMichel
    )
    NavigationStack {
        SolidarityLeaderboardScreen(viewModel: viewModel)
    }
    .task { await viewModel.load() }
    .preferredColorScheme(.dark)
}
