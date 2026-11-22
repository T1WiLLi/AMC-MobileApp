import SwiftUI

/// RQ-093 (T-114) : section « Classement solidaire » de l'onglet Impact.
/// Autonome (charge son propre ViewModel depuis `appContext`) pour rester un ajout d'une ligne dans `ImpactScreen` :
/// podium des trois premiers arrondissements, le tien mis en avant, et un lien vers le classement complet.
struct SolidarityLeaderboardSection: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: SolidarityLeaderboardViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LeaderboardSectionTitle()
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    LeaderboardCardSkeleton()
                }
            }
            .animation(.smooth, value: viewModel?.state.value)
        }
        .task {
            guard viewModel == nil else { return }
            let model = SolidarityLeaderboardViewModel(repositories: context.repositories, groupId: context.groupId)
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SolidarityLeaderboardViewModel) -> some View {
        switch viewModel.state {
        case .idle, .loading:
            LeaderboardCardSkeleton()
        case .empty:
            LeaderboardMessageCard(
                systemImage: "trophy",
                title: String(localized: "Le classement arrive bientôt"),
                message: String(localized: "Dès que les arrondissements auront leurs premiers paniers, on verra qui se serre le plus les coudes.")
            )
        case .failed(let error):
            LeaderboardMessageCard(systemImage: error.systemImage, title: error.title, message: error.message) {
                await viewModel.load()
            }
        case .loaded:
            LeaderboardSummaryCard(viewModel: viewModel)
        }
    }
}

// MARK: - Carte résumé

private struct LeaderboardSummaryCard: View {
    let viewModel: SolidarityLeaderboardViewModel

    var body: some View {
        let entries = viewModel.entries
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Paniers offerts, familles aidées, économies et participation, rapportés au nombre de ménages : petit ou grand, chaque arrondissement a sa chance.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "scalemass.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.solidarite)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)

            LeaderboardPodium(entries: Array(entries.prefix(3)))

            if let home = viewModel.home {
                HomeBoroughRow(entry: home, bestScore: entries.first?.score ?? 100)
            }

            NavigationLink {
                SolidarityLeaderboardScreen(viewModel: viewModel)
            } label: {
                Label("Voir tout le classement", systemImage: "list.number")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityHint("Ouvre le classement des \(entries.count) arrondissements.")
        }
        .grenierCard()
    }
}

/// Ton arrondissement, avec sa barre de score et un encouragement.
struct HomeBoroughRow: View {
    let entry: SolidarityLeaderboard.Entry
    let bestScore: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RankBadge(rank: entry.rank, isHome: true)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ton arrondissement", systemImage: "house.fill")
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.solidarite)
                    Text(entry.stats.shortName)
                        .font(.headline)
                        .foregroundStyle(.texte)
                }
                Spacer(minLength: 8)
                ScoreText(score: entry.score)
            }
            AnimatedScoreBar(fraction: bestScore > 0 ? entry.score / bestScore : 0, tint: .solidarite)
            Label(SolidarityLeaderboard.cheer(for: entry), systemImage: "sparkles")
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texteSecondaire)
        }
        .padding(14)
        .background(Color.solidarite.opacity(0.10), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Podium

/// Les trois premiers : 2e à gauche, 1er au centre (plus haut, couronné), 3e à droite. Les marches poussent à l'apparition.
struct LeaderboardPodium: View {
    let entries: [SolidarityLeaderboard.Entry]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var tallest: CGFloat = 112
    @State private var grown = false

    /// Ordre visuel du podium : 2, 1, 3.
    private var arranged: [SolidarityLeaderboard.Entry] {
        let order = [1, 0, 2]
        return order.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        LeaderboardRowCompact(entry: entry)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(arranged) { entry in
                        step(entry)
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.bouncy(duration: 0.7, extraBounce: 0.05).delay(0.15)) { grown = true } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Podium")
    }

    private func height(for rank: Int) -> CGFloat {
        let ratio: CGFloat = switch rank {
        case 1: 1
        case 2: 0.74
        default: 0.56
        }
        return min(tallest, 160) * ratio
    }

    private func podiumAccessibilityLabel(for entry: SolidarityLeaderboard.Entry) -> String {
        let name = entry.stats.name
        let points = Int(entry.score.rounded())
        switch (entry.rank == 1, entry.isHome) {
        case (true, true): return String(localized: "\(entry.rank)er : \(name), \(points) points, ton arrondissement")
        case (true, false): return String(localized: "\(entry.rank)er : \(name), \(points) points")
        case (false, true): return String(localized: "\(entry.rank)e : \(name), \(points) points, ton arrondissement")
        case (false, false): return String(localized: "\(entry.rank)e : \(name), \(points) points")
        }
    }

    private func step(_ entry: SolidarityLeaderboard.Entry) -> some View {
        VStack(spacing: 6) {
            MedalView(rank: entry.rank, celebrate: grown)
            Text(entry.stats.shortName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texte)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            ScoreText(score: entry.score, compact: true)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
                    .fill(entry.isHome ? Color.solidarite.gradient : Medal.tint(for: entry.rank).opacity(0.85).gradient)
                Text("\(entry.rank)")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.onAccent)
                    .padding(.top, 8)
                    .opacity(grown ? 1 : 0)
            }
            .frame(height: grown ? height(for: entry.rank) : 8)
            .overlay(alignment: .topTrailing) {
                if entry.isHome {
                    Image(systemName: "house.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.onAccent, Color.solidarite)
                        .offset(x: 6, y: -10)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podiumAccessibilityLabel(for: entry))
    }
}

/// Médaille or / argent / bronze ; la couronne du premier rebondit quand le podium a poussé.
struct MedalView: View {
    let rank: Int
    var celebrate = false

    var body: some View {
        Image(systemName: rank == 1 ? "crown.fill" : "medal.fill")
            .font(rank == 1 ? .title : .title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Medal.tint(for: rank))
            .symbolEffect(.bounce, value: celebrate)
            .accessibilityHidden(true)
    }
}

enum Medal {
    static func tint(for rank: Int) -> Color {
        switch rank {
        case 1: Color(.systemYellow)
        case 2: Color(.systemGray)
        case 3: Color(.systemBrown)
        default: .grenier
        }
    }
}

/// Rang dans une pastille ; médaille pour le podium.
struct RankBadge: View {
    let rank: Int
    var isHome = false
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill((rank <= 3 ? Medal.tint(for: rank) : (isHome ? Color.solidarite : Color.grenier)).opacity(0.16))
            if rank <= 3 {
                Image(systemName: rank == 1 ? "crown.fill" : "medal.fill")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Medal.tint(for: rank))
            } else {
                Text("\(rank)")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(isHome ? Color.solidarite : Color.grenier)
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Rang \(rank)")
    }
}

/// « 87,4 pts », chiffres animés.
struct ScoreText: View {
    let score: Double
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(score, format: .number.precision(.fractionLength(0)))
                .font(compact ? .headline : .title3.bold())
                .contentTransition(.numericText(value: score))
            Text("pts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
        }
        .fontDesign(.rounded)
        .monospacedDigit()
        .foregroundStyle(.texte)
    }
}

/// Barre de score qui se remplit à l'apparition et suit les changements (mesure, rafraîchissement).
struct AnimatedScoreBar: View {
    let fraction: Double
    var tint: Color = .grenier
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @ScaledMetric(relativeTo: .body) private var thickness: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.piste)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(thickness, proxy.size.width * CGFloat(shown ? min(max(fraction, 0), 1) : 0)))
            }
        }
        .frame(height: thickness)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: fraction)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.smooth(duration: 0.8).delay(delay)) { shown = true } }
        }
        .accessibilityHidden(true)
    }
}

/// Ligne compacte (podium en très grande taille de texte).
private struct LeaderboardRowCompact: View {
    let entry: SolidarityLeaderboard.Entry

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: entry.rank, isHome: entry.isHome)
            Text(entry.stats.shortName)
                .font(.headline)
                .foregroundStyle(.texte)
            Spacer(minLength: 4)
            ScoreText(score: entry.score, compact: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Titre, squelette, messages

private struct LeaderboardSectionTitle: View {
    var body: some View {
        Label {
            Text("Classement solidaire")
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: "trophy.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Medal.tint(for: 1))
        }
        .font(.title2.bold())
        .padding(.top, 12)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct LeaderboardCardSkeleton: View {
    var body: some View {
        LeaderboardSummaryPlaceholder()
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chargement du classement")
    }
}

/// Même mise en page que la carte chargée (masquée par `.redacted`).
private struct LeaderboardSummaryPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paniers offerts, familles aidées, économies et participation, rapportés au nombre de ménages.")
                .font(.subheadline)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array([96.0, 128, 72].enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 14).fill(Color.piste).frame(height: height)
                }
            }
            Text("Voir tout le classement")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .grenierCard()
    }
}

private struct LeaderboardMessageCard: View {
    let systemImage: String
    let title: String
    let message: String
    var retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(.texte)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
            if let retry {
                Button {
                    Task { await retry() }
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Section") {
    NavigationStack {
        ScrollView {
            SolidarityLeaderboardSection()
                .padding(16)
        }
        .grenierBackground()
    }
    .environment(\.appContext, .instant)
}

#Preview("Section — sombre") {
    NavigationStack {
        ScrollView {
            SolidarityLeaderboardSection()
                .padding(16)
        }
        .grenierBackground()
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
