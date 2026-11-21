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

    /// Photo plein cadre (Unsplash License, crédits dans docs/credits.md).
    var photo: String {
        switch self {
        case .problem: "IntroProbleme"
        case .solution: "IntroSolution"
        case .solidarity: "IntroSolidarite"
        }
    }

    /// Description de la photo pour VoiceOver.
    var photoDescription: String {
        switch self {
        case .problem: "Une balance au rayon des fruits et légumes d'une épicerie"
        case .solution: "Du maïs, des pommes de terre et des légumes frais dans un marché"
        case .solidarity: "Des bénévoles souriants remettent des denrées à une distribution alimentaire"
        }
    }

    /// Couleur d'accent de la page.
    var accent: Color {
        switch self {
        case .problem, .solution: .grenier
        case .solidarity: .solidarite
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
        .overlay(alignment: .top) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background {
            // Photos plein écran derrière les pages (jusque sous la barre d'état), en fondu enchaîné.
            ZStack {
                Color.black
                ForEach(IntroPage.allCases) { item in
                    IntroPhoto(page: item, isActive: page == item)
                        .opacity(page == item ? 1 : 0)
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: page)
        }
        // Écran immersif : texte blanc sur photo, verre sombre, barre d'état claire.
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    /// « Passer » en verre, en haut à droite, au-dessus des photos.
    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Spacer()
                if !page.isLast {
                    Button("Passer", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 32)
                        .buttonStyle(.glass)
                        .accessibilityHint("Passe la présentation et va à la connexion")
                        .transition(.blurReplace)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        // Barre de contrôle : plafonnée comme une barre système, le contenu dessous suit AX5.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(reduceMotion ? nil : .smooth, value: page)
    }

    private var bottomBar: some View {
        VStack(spacing: 20) {
            PageIndicator(page: $page)
            Button(action: advance) {
                Label(page.isLast ? "Commencer" : "Continuer",
                      systemImage: page.isLast ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(page.accent)
            .animation(reduceMotion ? nil : .smooth, value: page)
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
                    .fill(item == page ? Color.white : Color.white.opacity(0.35))
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

/// Une page immersive : la photo remplit l'écran, un voile sombre monte du bas,
/// et la carte en verre, le titre et le message se posent dessus en bas, au-dessus du bouton.
/// Le contenu défile si le texte est très grand (AX5).
private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer(minLength: proxy.size.height * 0.16)

                    hero
                        .frame(maxWidth: .infinity)
                        .offset(y: shown ? 0 : 28)
                        .opacity(shown ? 1 : 0)

                    VStack(alignment: .leading, spacing: 10) {
                        Label(page.eyebrow.uppercased(), systemImage: eyebrowSymbol)
                            .font(.footnote.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(page.title)
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(page.message)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
                    .accessibilityElement(children: .combine)
                    .offset(y: shown ? 0 : 18)
                    .opacity(shown ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 8)
                .frame(minHeight: proxy.size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            if reduceMotion { appeared = true; return }
            appeared = false
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.15)) { appeared = true }
        }
    }

    private var shown: Bool { appeared || reduceMotion }

    private var eyebrowSymbol: String {
        switch page {
        case .problem: "exclamationmark.triangle.fill"
        case .solution: "person.3.fill"
        case .solidarity: GrenierSymbol.solidarity
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

/// Photo plein écran : léger zoom lent (Ken Burns) tant que la page est visible,
/// voile en haut pour la barre d'état et voile profond en bas pour le texte blanc.
private struct IntroPhoto: View {
    let page: IntroPage
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.black
            .overlay {
                Image(page.photo)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isActive && !reduceMotion ? 1.1 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 9), value: isActive)
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .black.opacity(0), location: 0.18),
                        .init(color: .black.opacity(0.1), location: 0.35),
                        .init(color: .black.opacity(0.82), location: 0.6),
                        .init(color: .black.opacity(0.95), location: 0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel(page.photoDescription)
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Illustrations

/// Grand symbole dans un carré teinté, taille qui suit Dynamic Type.
private struct HeroSymbol: View {
    let systemImage: String
    let tint: Color
    let isActive: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var scaledSide: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grandit avec le texte, sans manger l'écran en AX5.
    private var side: CGFloat { min(scaledSide, 96) }

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(side * 0.22)
            .frame(width: side, height: side)
            .background(tint.opacity(0.22), in: .rect(cornerRadius: side * 0.28))
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isActive)
            .accessibilityHidden(true)
    }
}

/// Le problème : le chiffre de l'aide alimentaire à Montréal.
private struct ProblemHero: View {
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HeroSymbol(systemImage: "cart.badge.questionmark", tint: .grenier, isActive: isActive)
            VStack(alignment: .leading, spacing: 4) {
                Text("1,25 million")
                    .priceStyle(.title.bold())
                    .foregroundStyle(Color.texte)
                Text("de demandes d'aide alimentaire par mois à Montréal")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
                    Text("Légumes de saison")
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
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
        HStack(alignment: .center, spacing: 16) {
                HeroSymbol(systemImage: "basket.fill", tint: .solidarite, isActive: isActive)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: GrenierSymbol.solidarity)
                            .font(.title3)
                            .foregroundStyle(.white, Color.solidarite)
                            .padding(6)
                            .background(Color.solidarite, in: .circle)
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                            .offset(x: 8, y: -8)
                            .symbolEffect(.breathe, isActive: isActive && !reduceMotion)
                            .accessibilityHidden(true)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("12 paniers")
                        .priceStyle(.title.bold())
                        .foregroundStyle(Color.texte)
                    Text("suspendus offerts ce mois-ci à Parc-Extension")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular.tint(Color.solidarite.opacity(0.25)), in: .rect(cornerRadius: 28))
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
