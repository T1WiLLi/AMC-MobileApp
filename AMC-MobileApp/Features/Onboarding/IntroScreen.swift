import SwiftUI

/// Les 3 pages de la présentation (RQ-011) : le problème, la solution, la solidarité.
enum IntroPage: Int, CaseIterable, Identifiable, Sendable {
    case problem
    case solution
    case solidarity

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .problem: String(localized: "Le problème")
        case .solution: String(localized: "La solution")
        case .solidarity: String(localized: "La solidarité")
        }
    }

    var title: String {
        switch self {
        case .problem: String(localized: "L'épicerie coûte de plus en plus cher")
        case .solution: String(localized: "Ensemble, on paie moins cher")
        case .solidarity: String(localized: "Personne n'est laissé de côté")
        }
    }

    var message: String {
        switch self {
        case .problem:
            String(localized: "Beaucoup de familles qui travaillent n'arrivent plus à remplir le frigo. Et l'aide alimentaire déborde.")
        case .solution:
            String(localized: "Ton quartier achète en gros, directement aux fermes du Québec. À chaque palier franchi, le prix baisse pour tout le monde.")
        case .solidarity:
            String(localized: "Offre un panier suspendu : une famille de ton groupe le reçoit, sans savoir de qui. Avec dignité.")
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
        case .problem: String(localized: "Une balance au rayon des fruits et légumes d'une épicerie")
        case .solution: String(localized: "Du maïs, des pommes de terre et des légumes frais dans un marché")
        case .solidarity: String(localized: "Des bénévoles souriants remettent des denrées à une distribution alimentaire")
        }
    }

    /// Couleur d'accent de la page.
    var accent: Color {
        switch self {
        case .problem: .grenier
        case .solution: .economie
        case .solidarity: .solidarite
        }
    }

    /// Symbole de l'étiquette au-dessus du titre.
    var eyebrowSymbol: String {
        switch self {
        case .problem: "exclamationmark.triangle.fill"
        case .solution: "person.3.fill"
        case .solidarity: GrenierSymbol.solidarity
        }
    }

    /// Les deux pastilles qui flottent sur la photo : la première en haut à gauche, la seconde en bas à droite.
    var chips: [IntroChip] {
        switch self {
        case .problem: [
            IntroChip(id: 0, symbol: "cart.badge.questionmark", value: String(localized: "1,25 million"), caption: String(localized: "demandes d'aide par mois")),
            IntroChip(id: 1, symbol: "refrigerator.fill", value: String(localized: "Frigo vide"), caption: String(localized: "avant la fin du mois"))
        ]
        case .solution: [
            IntroChip(id: 0, symbol: "leaf.fill", value: String(localized: "Fermes du Québec"), caption: String(localized: "sans intermédiaire")),
            IntroChip(id: 1, symbol: GrenierSymbol.savings, value: "−19 %", caption: String(localized: "dès le 2ᵉ palier"))
        ]
        case .solidarity: [
            IntroChip(id: 0, symbol: "eye.slash.fill", value: String(localized: "Anonyme"), caption: String(localized: "personne ne sait qui donne")),
            IntroChip(id: 1, symbol: "eye.slash.fill", value: String(localized: "Anonyme"), caption: String(localized: "personne ne sait qui donne"))
        ]
        }
    }

    var isLast: Bool { self == IntroPage.allCases.last }

    /// Page suivante, nil sur la dernière.
    var next: IntroPage? { IntroPage(rawValue: rawValue + 1) }
}

/// Une pastille flottante : icône dans un rond de couleur, valeur en gras, légende.
struct IntroChip: Identifiable, Hashable, Sendable {
    let id: Int
    let symbol: String
    let value: String
    let caption: String
}

/// Présentation en 3 écrans, avant la connexion, une seule fois.
/// Chaque page raconte une petite histoire animée sur sa photo : le ticket de caisse qui grimpe,
/// les familles qui font baisser le prix palier par palier, le panier qui voyage anonymement.
/// Fond en dégradé maillé qui respire, couleur propre à chaque page.
struct IntroScreen: View {
    /// Appelé par « Commencer » ou « Passer ».
    let onFinish: () -> Void

    @State private var page: IntroPage = .problem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $page) {
            ForEach(IntroPage.allCases) { item in
                IntroPageView(page: item, isActive: page == item)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background { IntroMeshBackground(accent: page.accent).ignoresSafeArea() }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            // Toujours dans la mise en page (opacité 0 sur la dernière page) pour que rien ne saute.
            Button("Passer", action: onFinish)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.texteSecondaire)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(page.isLast ? 0 : 1)
                .disabled(page.isLast)
                .accessibilityHidden(page.isLast)
                .accessibilityHint("Passe la présentation et va à la connexion")
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(reduceMotion ? nil : .smooth, value: page)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            Button(action: advance) {
                Label(page.isLast ? String(localized: "Commencer") : String(localized: "Continuer"),
                      systemImage: page.isLast ? "checkmark" : "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(page.accent)
            .accessibilityHint(page.isLast ? String(localized: "Va à la connexion") : String(localized: "Page suivante"))

            PageIndicator(page: $page)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth, value: page)
    }

    private func advance() {
        guard let next = page.next else {
            onFinish()
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) { page = next }
    }
}

/// Texte puis icône (flèche à droite du libellé).
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

/// Dégradé maillé qui ondule lentement dans la couleur de la page ; figé avec Réduire les animations.
private struct IntroMeshBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [Float(0.5 + 0.12 * sin(t * 0.5)), 0], [1, 0],
                    [0, Float(0.45 + 0.1 * cos(t * 0.4))],
                    [Float(0.5 + 0.15 * cos(t * 0.35)), Float(0.42 + 0.12 * sin(t * 0.45))],
                    [1, Float(0.5 + 0.1 * sin(t * 0.3))],
                    [0, 1], [Float(0.5 + 0.1 * sin(t * 0.25)), 1], [1, 1]
                ],
                colors: [
                    accent.opacity(0.32), accent.opacity(0.18), Color.economie.opacity(0.14),
                    accent.opacity(0.12), Color.fond, accent.opacity(0.10),
                    Color.fond, Color.fond, Color.fond
                ]
            )
            .background(Color.fond)
        }
        .animation(.smooth(duration: 0.6), value: accent)
        .accessibilityHidden(true)
    }
}

/// Points de pagination sous le bouton : la page courante s'allonge dans la couleur de la page.
private struct PageIndicator: View {
    @Binding var page: IntroPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(IntroPage.allCases) { item in
                Capsule()
                    .fill(item == page ? page.accent : Color.texteSecondaire.opacity(0.25))
                    .frame(width: item == page ? 24 : 8, height: 8)
            }
        }
        .frame(minHeight: 20)
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

/// Une page : la photo, la scène animée qui la chevauche, puis l'étiquette, le titre et la phrase.
/// Défilable pour les grandes tailles de texte.
private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: -64) {
                    IntroPhotoCard(page: page, isActive: isActive, appeared: shown)
                    scene
                        .padding(.horizontal, 14)
                        .offset(y: shown ? 0 : 30)
                        .opacity(shown ? 1 : 0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(page.eyebrow, systemImage: page.eyebrowSymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(page.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(page.accent.opacity(0.14), in: .capsule)
                    Text(page.title)
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(.body)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .offset(y: shown ? 0 : 16)
                .opacity(shown ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            if reduceMotion { appeared = true; return }
            appeared = false
            withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.1)) { appeared = true }
        }
    }

    private var shown: Bool { appeared || reduceMotion }

    @ViewBuilder
    private var scene: some View {
        switch page {
        case .problem: ReceiptScene(isActive: isActive)
        case .solution: TierScene(isActive: isActive)
        case .solidarity: BasketScene(isActive: isActive)
        }
    }
}

/// La photo dans une carte aux grands coins, zoom lent tant que la page est visible,
/// et la pastille du chiffre clé qui flotte en haut à gauche.
private struct IntroPhotoCard: View {
    let page: IntroPage
    let isActive: Bool
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.40 }
            .overlay {
                Image(page.photo)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isActive && !reduceMotion ? 1.1 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 8), value: isActive)
                    .accessibilityLabel(page.photoDescription)
            }
            .clipShape(.rect(cornerRadius: 36))
            .overlay(alignment: .topLeading) {
                IntroChipView(chip: page.chips[0], accent: page.accent, isActive: isActive)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.4).delay(0.2), value: appeared)
                    .offset(x: -10, y: 22)
            }
    }
}

/// Pastille blanche flottante (ombre douce, léger va-et-vient vertical).
private struct IntroChipView: View {
    let chip: IntroChip
    let accent: Color
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chip.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 36, height: 36)
                .background(accent, in: .circle)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isActive)
            VStack(alignment: .leading, spacing: 0) {
                Text(chip.value)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                Text(chip.caption)
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Color.surface, in: .capsule)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // Un seul calque (fond, ombre et texte) qui flotte ensemble : l'ancienne animation implicite
        // ne déplaçait que le texte dans le paging, la capsule restait sur place.
        .compositingGroup()
        .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, up in
            content.offset(y: up ? -4 : 4)
        } animation: { _ in
            .easeInOut(duration: 2.4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scènes animées

/// Carte blanche commune aux scènes, posée sur le bas de la photo.
private struct SceneCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Le problème : un ticket de caisse qui s'imprime ligne par ligne, et le total qui grimpe.
private struct ReceiptScene: View {
    let isActive: Bool

    private static let items: [(name: String, symbol: String, cents: Cents)] = [
        (String(localized: "Lait 2 L"), "waterbottle.fill", 589),
        (String(localized: "Riz 2 kg"), "takeoutbag.and.cup.and.straw.fill", 899),
        (String(localized: "Œufs ×12"), "oval.portrait.fill", 529),
        (String(localized: "Poulet entier"), "fork.knife", 1499)
    ]

    @State private var printed = Self.items.count
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalCents: Cents {
        Self.items.prefix(printed).reduce(0) { $0 + $1.cents }
    }

    var body: some View {
        SceneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Ticket de la semaine", systemImage: "receipt.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.texte)
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.grenier)
                        .symbolEffect(.bounce, value: printed)
                        .accessibilityHidden(true)
                }
                ForEach(Array(Self.items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.caption)
                            .foregroundStyle(Color.texteSecondaire)
                            .frame(width: 18)
                        Text(item.name)
                            .font(.footnote)
                            .foregroundStyle(Color.texte)
                        Spacer()
                        Text(Money.format(item.cents))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.texteSecondaire)
                    }
                    // Place réservée : la carte ne change pas de taille pendant l'impression.
                    .opacity(index < printed ? 1 : 0)
                    .offset(y: index < printed ? 0 : -6)
                }
                Divider().overlay(Color.texteSecondaire.opacity(0.3))
                HStack {
                    Text("Total")
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Spacer()
                    Text(Money.format(totalCents))
                        .font(.title3.bold().monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.grenier)
                        .contentTransition(.numericText(value: Double(totalCents)))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ticket de la semaine : lait, riz, œufs et poulet, total \(Money.format(Self.items.reduce(0) { $0 + $1.cents }))")
        .task(id: isActive) { await play() }
    }

    private func play() async {
        guard isActive, !reduceMotion else {
            printed = Self.items.count
            return
        }
        while !Task.isCancelled {
            withAnimation(.smooth(duration: 0.3)) { printed = 0 }
            try? await Task.sleep(for: .seconds(0.6))
            for count in 1...Self.items.count {
                if Task.isCancelled { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) { printed = count }
                try? await Task.sleep(for: .seconds(0.55))
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

/// La solution : des familles rejoignent le lot, le prix descend palier par palier, confettis au palier.
private struct TierScene: View {
    let isActive: Bool

    private static let tiers = [
        PriceTier(minShares: 1, priceCents: 320),
        PriceTier(minShares: 11, priceCents: 260),
        PriceTier(minShares: 26, priceCents: 210)
    ]
    private static let steps = [3, 8, 12, 18, 23, 28]
    private static let initials = ["AM", "JT", "FL", "SR", "KB", "MN"]

    @State private var families = 28
    @State private var confettiStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tierIndex: Int {
        Self.tiers.lastIndex { families >= $0.minShares } ?? 0
    }

    private var priceCents: Cents { Self.tiers[tierIndex].priceCents }

    var body: some View {
        SceneCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    avatars
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(families) familles")
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                            .contentTransition(.numericText(value: Double(families)))
                            .monospacedDigit()
                        Text("Légumes de saison · Parc-Ex")
                            .font(.caption)
                            .foregroundStyle(Color.texteSecondaire)
                    }
                    Spacer(minLength: 4)
                    if tierIndex > 0 {
                        Label("Palier \(tierIndex + 1)", systemImage: "lock.open.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.economie, in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                            .id(tierIndex)
                    }
                }
                PriceTag(priceCents: priceCents, unit: "kg", referenceCents: 410)
                    .contentTransition(.numericText(value: Double(priceCents)))
                TierProgressBar(
                    tiers: Self.tiers,
                    committedShares: families,
                    totalShares: 32,
                    unitSingular: "famille",
                    unitPlural: "familles"
                )
            }
        }
        .overlay {
            if let confettiStart {
                ConfettiRain(start: confettiStart)
                    .clipShape(.rect(cornerRadius: 28))
            }
        }
        .sensoryFeedback(.success, trigger: tierIndex) { old, new in new > old }
        .task(id: isActive) { await play() }
    }

    private var avatars: some View {
        let shown = Self.initials.prefix(min(Self.initials.count, max(1, families / 5)))
        return HStack(spacing: -10) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, initials in
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 30, height: 30)
                    .background([Color.grenier, .economie, .solidarite][index % 3], in: .circle)
                    .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private func play() async {
        guard isActive, !reduceMotion else {
            families = 28
            return
        }
        while !Task.isCancelled {
            for value in Self.steps {
                if Task.isCancelled { return }
                let before = Self.tiers.lastIndex { families >= $0.minShares } ?? 0
                withAnimation(.spring(duration: 0.6, bounce: 0.35)) { families = value }
                let after = Self.tiers.lastIndex { value >= $0.minShares } ?? 0
                if after > before { confettiStart = .now }
                try? await Task.sleep(for: .seconds(1.2))
            }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.smooth) { families = 3; confettiStart = nil }
            try? await Task.sleep(for: .seconds(0.8))
        }
    }
}

/// La solidarité : un panier part d'une maison, voyage sur un arc semé de cœurs
/// et arrive chez une autre famille, sans nom.
private struct BasketScene: View {
    let isActive: Bool

    @State private var progress: CGFloat = 1
    @State private var arrived = true
    @State private var delivered = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SceneCard {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    ZStack {
                        ArcPath()
                            .stroke(Color.solidarite.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
                        ArcPath()
                            .trim(from: 0, to: progress)
                            .stroke(Color.solidarite, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        house(symbol: "house.fill", label: String(localized: "Toi"))
                            .position(x: 22, y: height - 18)
                        house(symbol: "house.lodge.fill", label: String(localized: "Une famille"))
                            .position(x: width - 22, y: height - 18)
                        Image(systemName: "basket.fill")
                            .font(.title3)
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 40, height: 40)
                            .background(Color.solidarite, in: .circle)
                            .shadow(color: Color.solidarite.opacity(0.4), radius: 8, y: 4)
                            .position(ArcPath.point(at: progress, in: CGRect(origin: .zero, size: proxy.size)))
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.solidarite.opacity(0.7))
                            .position(ArcPath.point(at: max(0, progress - 0.18), in: CGRect(origin: .zero, size: proxy.size)))
                            .opacity(progress > 0.2 && !arrived ? 1 : 0)
                    }
                }
                .frame(height: 96)

                HStack(spacing: 10) {
                    Image(systemName: arrived ? "checkmark.seal.fill" : "shippingbox.and.arrow.backward.fill")
                        .font(.title3)
                        .foregroundStyle(Color.solidarite)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(delivered) paniers suspendus")
                            .font(.headline)
                            .foregroundStyle(Color.texte)
                            .contentTransition(.numericText(value: Double(delivered)))
                            .monospacedDigit()
                        Text(arrived ? String(localized: "Remis ce mois-ci, sans nom") : String(localized: "En route, de façon anonyme"))
                            .font(.caption)
                            .foregroundStyle(Color.texteSecondaire)
                            .id(arrived)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Un panier suspendu voyage de ta maison à une famille du groupe, de façon anonyme. \(delivered) paniers offerts ce mois-ci.")
        .sensoryFeedback(.success, trigger: delivered)
        .task(id: isActive) { await play() }
    }

    private func house(symbol: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.solidarite)
                .symbolRenderingMode(.hierarchical)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize()
        }
    }

    private func play() async {
        guard isActive, !reduceMotion else {
            progress = 1
            arrived = true
            return
        }
        delivered = 12
        while !Task.isCancelled {
            progress = 0
            withAnimation(.smooth(duration: 0.3)) { arrived = false }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeInOut(duration: 2.2)) { progress = 1 }
            try? await Task.sleep(for: .seconds(2.3))
            if Task.isCancelled { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                arrived = true
                delivered += 1
            }
            try? await Task.sleep(for: .seconds(2.5))
        }
    }
}

/// Arc entre deux maisons, en bas à gauche et en bas à droite du cadre.
nonisolated private struct ArcPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: Self.start(in: rect))
        path.addQuadCurve(to: Self.end(in: rect), control: Self.control(in: rect))
        return path
    }

    private static func start(in rect: CGRect) -> CGPoint { CGPoint(x: rect.minX + 22, y: rect.maxY - 40) }
    private static func end(in rect: CGRect) -> CGPoint { CGPoint(x: rect.maxX - 22, y: rect.maxY - 40) }
    private static func control(in rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.minY - 30) }

    /// Point sur l'arc à `t` (0…1), pour poser le panier.
    static func point(at t: CGFloat, in rect: CGRect) -> CGPoint {
        let p0 = start(in: rect), p1 = control(in: rect), p2 = end(in: rect)
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
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
