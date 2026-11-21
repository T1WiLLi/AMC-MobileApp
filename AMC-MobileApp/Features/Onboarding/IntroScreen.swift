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
            IntroChip(id: 0, symbol: "cart.badge.questionmark", value: "1,25 million", caption: "demandes d'aide par mois"),
            IntroChip(id: 1, symbol: "refrigerator.fill", value: "Frigo vide", caption: "avant la fin du mois")
        ]
        case .solution: [
            IntroChip(id: 0, symbol: "person.3.fill", value: "32 familles", caption: "Parc-Ex Ouest"),
            IntroChip(id: 1, symbol: GrenierSymbol.savings, value: "−19 %", caption: "dès le 2ᵉ palier")
        ]
        case .solidarity: [
            IntroChip(id: 0, symbol: "basket.fill", value: "12 paniers", caption: "offerts ce mois-ci"),
            IntroChip(id: 1, symbol: "eye.slash.fill", value: "Anonyme", caption: "personne ne sait qui donne")
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
/// Inspirée des onboardings d'épicerie actuels : fond clair teinté par page, photo dans une grande carte arrondie,
/// pastilles blanches qui chevauchent la photo, gros titre, une phrase, puis le bouton et les points dessous.
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
        .background {
            LinearGradient(
                colors: [page.accent.opacity(0.18), page.accent.opacity(0.06), Color.fond],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: page)
        }
        .background(Color.fond.ignoresSafeArea())
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
                Label(page.isLast ? "Commencer" : "Continuer",
                      systemImage: page.isLast ? "checkmark" : "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .foregroundStyle(Color.onAccent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(page.accent)
            .accessibilityHint(page.isLast ? "Va à la connexion" : "Page suivante")

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

/// Une page : la photo dans une grande carte arrondie avec ses pastilles, puis l'étiquette, le titre et la phrase.
/// Défilable pour les grandes tailles de texte.
private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                IntroPhotoCard(page: page, isActive: isActive, appeared: shown)

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
}

/// La photo de la page dans une carte aux grands coins, avec un zoom lent tant que la page est visible,
/// et deux pastilles qui débordent de la carte et flottent doucement.
private struct IntroPhotoCard: View {
    let page: IntroPage
    let isActive: Bool
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.48 }
            .overlay {
                Image(page.photo)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isActive && !reduceMotion ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 8), value: isActive)
                    .accessibilityLabel(page.photoDescription)
            }
            .clipShape(.rect(cornerRadius: 36))
            .overlay(alignment: .topLeading) {
                chip(page.chips[0], delay: 0.2)
                    .offset(x: -10, y: 24)
            }
            .overlay(alignment: .bottomTrailing) {
                chip(page.chips[1], delay: 0.35)
                    .offset(x: 10, y: 20)
            }
            .padding(.bottom, 20)
    }

    private func chip(_ chip: IntroChip, delay: Double) -> some View {
        IntroChipView(chip: chip, accent: page.accent, isActive: isActive)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.4).delay(delay), value: appeared)
    }
}

/// Pastille blanche flottante (ombre douce, léger va-et-vient vertical).
private struct IntroChipView: View {
    let chip: IntroChip
    let accent: Color
    let isActive: Bool
    @State private var floating = false
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
        .offset(y: floating ? -4 : 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
        .onAppear { if !reduceMotion { floating = true } }
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
