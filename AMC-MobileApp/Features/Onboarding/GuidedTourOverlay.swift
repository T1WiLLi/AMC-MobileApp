import SwiftUI

/// Bulle de Noisette pendant la visite guidée (FB-19), posée au-dessus des onglets du portail Familles.
///
/// Comportement :
/// - un voile assombrit l'app et découpe l'élément de l'étape (`.guidedTourAnchor(_:)`) ; sans ancre visible
///   (écran vide, mode aîné, chargement), la bulle se pose au centre, sans découpe : la visite n'est jamais bloquée ;
/// - « Précédent » / « Suivant » (« Terminer » à la fin), « Passer » et le bouton Fermer (les deux arrêtent la visite) ;
/// - glisser la bulle vers la gauche = Suivant, vers la droite = Précédent ;
/// - toucher le voile, à côté de la bulle, ne fait rien : pas de visite perdue par un toucher de travers ;
/// - VoiceOver : chaque étape est annoncée (« Étape 2 sur 5 ») et le focus va sur la bulle ; geste « Z » = Passer ;
/// - Reduce Motion : changements d'étape en fondu, sans ressort ni glissement.
struct GuidedTourOverlay: View {
    @State private var tour = GuidedTour.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let step = tour.currentStep, let index = tour.machine.index {
                GeometryReader { proxy in
                    let spot = spotlight(for: step, in: proxy)
                    ZStack {
                        TourScrim(spotlight: spot)
                        TourBubblePlacement(spotlight: spot, size: proxy.size, safeArea: proxy.safeAreaInsets) {
                            TourBubble(step: step, index: index, count: tour.machine.steps.count, tour: tour)
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: spot)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: tour.currentStep)
    }

    /// Cadre de l'élément à mettre en valeur, dans le repère du voile ; nil s'il n'est pas (assez) à l'écran.
    private func spotlight(for step: TourStep, in proxy: GeometryProxy) -> CGRect? {
        guard let global = tour.anchorFrames[step] else { return nil }
        let origin = proxy.frame(in: .global).origin
        let local = global.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
        let screen = CGRect(origin: .zero, size: proxy.size)
            .inset(by: UIEdgeInsets(top: proxy.safeAreaInsets.top, left: 0, bottom: proxy.safeAreaInsets.bottom + 56, right: 0))
        let visible = local.intersection(screen)
        // Trop peu visible (écran pas encore chargé, élément sous la barre d'onglets) ou presque tout l'écran.
        guard !visible.isNull, visible.height >= 44,
              visible.height < screen.height * 0.6 else { return nil }
        return visible
    }
}

// MARK: - Voile

private struct TourScrim: View {
    let spotlight: CGRect?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.5))
                .overlay {
                    if let spotlight {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .frame(width: spotlight.width, height: spotlight.height)
                            .position(x: spotlight.midX, y: spotlight.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            if let spotlight {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.grenier, lineWidth: 3)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .position(x: spotlight.midX, y: spotlight.midY)
            }
        }
        // Le voile prend les touchers (l'app dessous ne réagit pas) sans rien faire : voir la doc de l'overlay.
        .contentShape(.rect)
        .onTapGesture {}
        .accessibilityHidden(true)
    }
}

// MARK: - Placement

/// Pose la bulle sous l'élément s'il y a la place, sinon au-dessus, sinon en bas de l'écran.
private struct TourBubblePlacement<Bubble: View>: View {
    let spotlight: CGRect?
    let size: CGSize
    let safeArea: EdgeInsets
    @ViewBuilder let bubble: Bubble

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Place minimale pour la bulle ; aux tailles d'accessibilité, elle prend le bas de l'écran.
    private var minimumRoom: CGFloat { dynamicTypeSize.isAccessibilitySize ? .infinity : 280 }

    var body: some View {
        let top = safeArea.top + 8
        let bottom = safeArea.bottom + 8
        Group {
            if let spotlight, size.height - spotlight.maxY - bottom >= minimumRoom {
                bubble.frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, spotlight.maxY + 12)
                    .padding(.bottom, bottom)
            } else if let spotlight, spotlight.minY - top >= minimumRoom {
                bubble.frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, top)
                    .padding(.bottom, size.height - spotlight.minY + 12)
            } else if spotlight != nil {
                bubble.frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, top)
                    .padding(.bottom, bottom)
            } else {
                bubble.frame(maxHeight: .infinity, alignment: .center)
                    .padding(.top, top)
                    .padding(.bottom, bottom)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Bulle

private struct TourBubble: View {
    let step: TourStep
    let index: Int
    let count: Int
    let tour: GuidedTour

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var mascotSize: CGFloat = 52

    private var isLast: Bool { index == count - 1 }
    private var progress: String { String(localized: "Étape \(index + 1) sur \(count)") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(step.title)
                    } icon: {
                        Image(systemName: step.systemImage)
                            .foregroundStyle(Color.grenier)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isFocused)
                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                dots
                controls
            }
            .padding(18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 520)
        .background(Color.surface, in: .rect(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.grenier.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .gesture(swipe)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { tour.skip() }
        .grenierHaptic(.selection, trigger: index)
        .onChange(of: index, initial: true) { _, _ in announce() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MascotView(size: mascotSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MascotView.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.texte)
                Text(progress)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.texteSecondaire)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Fermer la visite", systemImage: "xmark", role: .close) {
                tour.skip()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHint("Arrête le tutoriel. Tu peux le revoir dans le Profil.")
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Color.grenier : Color.texteSecondaire.opacity(0.3))
                    .frame(width: dot == index ? 22 : 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                skipButton
                Spacer(minLength: 0)
                backButton
                nextButton
            }
            VStack(spacing: 10) {
                nextButton.frame(maxWidth: .infinity)
                backButton.frame(maxWidth: .infinity)
                skipButton.frame(maxWidth: .infinity)
            }
        }
    }

    private var skipButton: some View {
        Button("Passer") { tour.skip() }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.texteSecondaire)
            .frame(minHeight: 44)
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
            .accessibilityHidden(isLast)
            .accessibilityHint("Arrête le tutoriel. Tu peux le revoir dans le Profil.")
    }

    @ViewBuilder
    private var backButton: some View {
        if index > 0 {
            Button {
                move { tour.back() }
            } label: {
                Label("Précédent", systemImage: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
        }
    }

    private var nextButton: some View {
        Button {
            move { tour.next() }
        } label: {
            Label(isLast ? "Terminer" : "Suivant", systemImage: isLast ? "checkmark" : "chevron.forward")
                .labelStyle(TrailingIconLabelStyle(isTrailing: !isLast))
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                move { dx < 0 ? tour.next() : tour.back() }
            }
    }

    private func move(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth) { change() }
    }

    /// VoiceOver : annonce l'étape, puis met le focus sur son titre.
    private func announce() {
        let title = String(localized: step.title)
        AccessibilityNotification.Announcement("\(progress). \(title)").post()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            isFocused = true
        }
    }
}

/// « Suivant › » : l'icône après le texte.
private struct TrailingIconLabelStyle: LabelStyle {
    let isTrailing: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if !isTrailing { configuration.icon }
            configuration.title
            if isTrailing { configuration.icon }
        }
    }
}

#Preview("Visite, étape 1") {
    let tour = GuidedTour(store: GuidedTourStore(defaults: UserDefaults(suiteName: "preview.tour")!), isEnabled: true)
    TourBubble(step: .nearbyOffers, index: 0, count: TourStep.allCases.count, tour: tour)
        .padding()
        .grenierBackground()
}

#Preview("Dernière étape, sombre") {
    let tour = GuidedTour(store: GuidedTourStore(defaults: UserDefaults(suiteName: "preview.tour")!), isEnabled: true)
    TourBubble(step: .impact, index: 4, count: TourStep.allCases.count, tour: tour)
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
