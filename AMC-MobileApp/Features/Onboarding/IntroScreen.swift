import SwiftUI

/// Les 3 pages de la présentation (RQ-011) : le problème, la solution, la solidarité.
enum IntroPage: Int, CaseIterable, Identifiable, Sendable {
    case problem
    case solution
    case solidarity

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .problem: "Le problème"
        case .solution: "La solution"
        case .solidarity: "La solidarité"
        }
    }

    var title: String {
        switch self {
        case .problem: "L'épicerie coûte de plus en plus cher"
        case .solution: "Ensemble, on paie moins cher"
        case .solidarity: "Personne n'est laissé de côté"
        }
    }

    var message: String {
        switch self {
        case .problem:
            "Beaucoup de familles qui travaillent n'arrivent plus à remplir le frigo. Et l'aide alimentaire déborde."
        case .solution:
            "Ton quartier achète en gros, directement aux fermes du Québec. À chaque palier franchi, le prix baisse pour tout le monde."
        case .solidarity:
            "Offre un panier suspendu : une famille de ton groupe le reçoit, sans savoir de qui. Avec dignité."
        }
    }

    var isLast: Bool { self == IntroPage.allCases.last }

    /// Page suivante, nil sur la dernière.
    var next: IntroPage? { IntroPage(rawValue: rawValue + 1) }
}

/// Présentation en 3 écrans, avant la connexion, une seule fois.
struct IntroScreen: View {
    /// Appelé par « Commencer » ou « Passer ».
    let onFinish: () -> Void

    @State private var page: IntroPage = .problem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $page) {
            ForEach(IntroPage.allCases) { page in
                IntroPageView(page: page, isActive: self.page == page)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .grenierBackground()
        .sensoryFeedback(.selection, trigger: page)
    }

    private var topBar: some View {
        HStack {
            Label("Grenier", systemImage: "basket.fill")
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(Color.grenier)
                .symbolRenderingMode(.hierarchical)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Toujours dans la mise en page (opacité 0 sur la dernière page) pour que rien ne saute.
            Button("Passer", action: onFinish)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.texteSecondaire)
                .frame(minHeight: 44)
                .opacity(page.isLast ? 0 : 1)
                .disabled(page.isLast)
                .accessibilityHidden(page.isLast)
                .accessibilityHint("Passe la présentation et va à la connexion")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        // Barre de contrôle : plafonnée comme une barre système, le contenu dessous suit AX5.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(.smooth, value: page)
    }

    private var bottomBar: some View {
        VStack(spacing: 20) {
            PageIndicator(page: $page)
            Button(action: advance) {
                Text(page.isLast ? "Commencer" : "Continuer")
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .contentTransition(.interpolate)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.grenier)
            .accessibilityHint(page.isLast ? "Va à la connexion" : "Page suivante")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    private func advance() {
        guard let next = page.next else {
            onFinish()
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) { page = next }
    }
}

/// Points de pagination : la page courante s'allonge en Grenier.
private struct PageIndicator: View {
    @Binding var page: IntroPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(IntroPage.allCases) { item in
                Capsule()
                    .fill(item == page ? Color.grenier : Color.texteSecondaire.opacity(0.3))
                    .frame(width: item == page ? 24 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.rawValue + 1) sur \(IntroPage.allCases.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let next = page.next { page = next }
            case .decrement: if let previous = IntroPage(rawValue: page.rawValue - 1) { page = previous }
            @unknown default: break
            }
        }
    }
}

/// Une page : illustration en haut, texte en dessous, défilable pour les grandes tailles de texte.
private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text(page.eyebrow.uppercased())
                        .font(.footnote.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Text(page.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(.body)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var accent: Color {
        switch page {
        case .problem, .solution: .grenier
        case .solidarity: .solidarite
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch page {
        case .problem: ProblemHero(isActive: isActive)
        case .solution: SolutionHero(isActive: isActive)
        case .solidarity: SolidarityHero(isActive: isActive)
        }
    }
}

// MARK: - Illustrations

/// Grand symbole dans un carré teinté, taille qui suit Dynamic Type.
private struct HeroSymbol: View {
    let systemImage: String
    let tint: Color
    let isActive: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var scaledSide: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grandit avec le texte, sans manger l'écran en AX5.
    private var side: CGFloat { min(scaledSide, 120) }

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(side * 0.22)
            .frame(width: side, height: side)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: side * 0.28))
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isActive)
            .accessibilityHidden(true)
    }
}

/// Le problème : le chiffre de l'aide alimentaire à Montréal.
private struct ProblemHero: View {
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroSymbol(systemImage: "cart.badge.questionmark", tint: .grenier, isActive: isActive)
            VStack(alignment: .leading, spacing: 4) {
                Text("1,25 million")
                    .priceStyle(.largeTitle.bold())
                    .foregroundStyle(Color.texte)
                Text("de demandes d'aide alimentaire par mois à Montréal")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

/// La solution : un mini lot dont les paliers se remplissent et le prix baisse.
private struct SolutionHero: View {
    let isActive: Bool

    private static let tiers = [
        PriceTier(minShares: 1, priceCents: 320),
        PriceTier(minShares: 11, priceCents: 260),
        PriceTier(minShares: 26, priceCents: 210)
    ]
    private static let steps = [4, 12, 19, 28]

    @State private var families = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var priceCents: Cents {
        Self.tiers.last { families >= $0.minShares }?.priceCents ?? Self.tiers[0].priceCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: GrenierSymbol.offers)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Riz basmati")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Text("\(families) familles · Parc-Ex Ouest")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .contentTransition(.numericText(value: Double(families)))
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Image(systemName: GrenierSymbol.savings)
                    .font(.title3)
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: priceCents)
                    .accessibilityHidden(true)
            }

            PriceTag(priceCents: priceCents, unit: "kg", referenceCents: 410)

            TierProgressBar(
                tiers: Self.tiers,
                committedShares: families,
                totalShares: 32,
                unitSingular: "famille",
                unitPlural: "familles"
            )
        }
        .grenierCard(padding: 20)
        .task(id: isActive) { await play() }
    }

    /// Rejoue la montée des familles tant que la page est visible ; fixe sans animation si Reduce Motion.
    private func play() async {
        guard isActive, !reduceMotion else {
            families = 24
            return
        }
        while !Task.isCancelled {
            for value in Self.steps {
                withAnimation(.smooth(duration: 0.6)) { families = value }
                try? await Task.sleep(for: .seconds(1.3))
                if Task.isCancelled { return }
            }
        }
    }
}

/// La solidarité : un panier suspendu offert, en couleur Solidarite.
private struct SolidarityHero: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                HeroSymbol(systemImage: "basket.fill", tint: .solidarite, isActive: isActive)
                Image(systemName: GrenierSymbol.solidarity)
                    .font(.largeTitle)
                    .foregroundStyle(Color.solidarite)
                    .symbolEffect(.breathe, isActive: isActive && !reduceMotion)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Panier suspendu")
                    .font(.headline)
                    .foregroundStyle(Color.solidarite)
                Text("12 paniers offerts ce mois-ci à Parc-Extension")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.solidarite.opacity(0.12), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Clair") {
    IntroScreen {}
}

#Preview("Sombre") {
    IntroScreen {}
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    IntroScreen {}
        .dynamicTypeSize(.accessibility5)
}
