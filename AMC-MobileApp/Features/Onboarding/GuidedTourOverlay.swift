import SwiftUI

/// Bulle de la mascotte pendant une visite guidée (Noisette, FB-19 ; Racoonette), posée au-dessus des onglets du portail.
///
/// Comportement :
/// - un voile assombrit l'app et découpe l'élément de l'étape (`.guidedTourAnchor(_:)`), aux coins de l'élément ;
/// - la bulle se pose sous l'élément, sinon au-dessus, selon la place qu'elle mesure : elle ne le couvre jamais.
///   Quand aucun côté n'a assez de place (très grand texte), elle prend le côté le plus grand et son texte défile ;
/// - le temps que l'écran s'affiche et que l'élément vienne à l'écran, la bulle attend ; si l'élément n'existe pas
///   (écran vide, section masquée), elle se pose au centre avec une note : la visite n'est jamais bloquée ;
/// - « Précédent » / « Suivant » (« Terminer » à la fin), « Passer » et le bouton Fermer (les deux arrêtent la visite) ;
/// - glisser la bulle vers la gauche = Suivant, vers la droite = Précédent ;
/// - toucher le voile, à côté de la bulle, ne fait rien : pas de visite perdue par un toucher de travers ;
/// - VoiceOver : chaque étape est annoncée (« Étape 2 sur 5 ») et le focus va sur la bulle ; geste « Z » = Passer ;
/// - Reduce Motion : changements d'étape en fondu, sans ressort ni glissement.
struct GuidedTourOverlay: View {
    let tour: GuidedTour

    init(_ tour: TourID) {
        self.tour = GuidedTour.instance(for: tour)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Élément montré : le dernier cadre resté en place (il ne bouge plus), pour ne pas suivre un défilement image par image.
    @State private var settled: TourAnchor?
    /// L'élément ne s'est pas montré à temps : la bulle passe au centre.
    @State private var waitedOut = false
    @State private var scrollAttempts = 0
    @State private var lastScreen: TourScreen?

    var body: some View {
        ZStack {
            if let step = tour.currentStep, let index = tour.machine.index {
                GeometryReader { proxy in
                    let spot = spotlight(settled, in: proxy)
                    let showsBubble = !step.expectsAnchor || settled != nil || waitedOut
                    ZStack {
                        TourScrim(spotlight: spot, cornerRadius: settled?.cornerRadius ?? 22)
                        TourBubbleLayout(spot: spot, insets: proxy.safeAreaInsets) {
                            TourBubble(
                                step: step, index: index, count: tour.machine.steps.count, tour: tour,
                                isEmpty: step.expectsAnchor && spot == nil
                            )
                            .opacity(showsBubble ? 1 : 0)
                            .allowsHitTesting(showsBubble)
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: spot)
                    .animation(.easeInOut(duration: 0.2), value: showsBubble)
                    .task(id: LiveAnchor(step: step, anchor: liveAnchor(for: step))) {
                        await settle(step: step, in: proxy)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .task(id: step) {
                    waitedOut = false
                    scrollAttempts = 0
                    try? await Task.sleep(for: .milliseconds(1500))
                    waitedOut = true
                }
                .onChange(of: step, initial: true) { _, step in
                    // Autre écran : l'ancien cadre ne vaut plus rien ; même écran : on le garde jusqu'au nouveau.
                    if lastScreen != step.screen { settled = nil }
                    lastScreen = step.screen
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: tour.currentStep)
        .onChange(of: tour.currentStep == nil) { _, isOver in
            if isOver { settled = nil; lastScreen = nil }
        }
    }

    private struct LiveAnchor: Equatable {
        let step: TourStep
        let anchor: TourAnchor?
    }

    /// Cadre de l'élément de l'étape, ou de son remplaçant quand l'écran n'a pas l'élément.
    private func liveAnchor(for step: TourStep) -> TourAnchor? {
        tour.anchor(for: step) ?? step.fallback.flatMap { tour.anchor(for: $0) }
    }

    /// Attend que l'élément ne bouge plus, puis le retient ; s'il n'est pas bien visible, redemande le défilement.
    private func settle(step: TourStep, in proxy: GeometryProxy) async {
        let live = liveAnchor(for: step)
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        settled = live
        guard step.expectsAnchor, step.isInContent, let live, scrollAttempts < 3 else { return }
        let area = proxy.size
        let rect = live.frame.insetBy(dx: -live.padding, dy: -live.padding)
        let isComfortable = rect.minY >= proxy.safeAreaInsets.top + 44 && rect.maxY <= area.height - proxy.safeAreaInsets.bottom - 100
        if !isComfortable {
            scrollAttempts += 1
            tour.requestScroll()
        }
    }

    /// Cadre à découper, dans le repère du voile ; nil s'il n'est pas (assez) à l'écran.
    private func spotlight(_ anchor: TourAnchor?, in proxy: GeometryProxy) -> CGRect? {
        guard let anchor else { return nil }
        let origin = proxy.frame(in: .global).origin
        let local = anchor.frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -anchor.padding, dy: -anchor.padding)
        let screen = CGRect(origin: .zero, size: proxy.size)
            .inset(by: UIEdgeInsets(top: proxy.safeAreaInsets.top, left: 0, bottom: proxy.safeAreaInsets.bottom, right: 0))
        let visible = local.intersection(screen)
        // Trop peu visible, ou presque tout l'écran (une découpe qui ne montre plus rien).
        guard !visible.isNull, visible.height >= 30, visible.width >= 30,
              visible.height < screen.height * 0.85 else { return nil }
        return visible
    }
}

extension TourStep {
    /// L'élément est dans un contenu qui défile (et non dans la barre de navigation).
    var isInContent: Bool {
        switch self {
        case .groupsActions, .profile, .vendorShop, .vendorCreate, .vendorProducts, .vendorProfile: false
        default: true
        }
    }
}

// MARK: - Voile

private struct TourScrim: View {
    let spotlight: CGRect?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.5))
                .overlay {
                    if let spotlight {
                        RoundedRectangle(cornerRadius: min(cornerRadius, spotlight.height / 2), style: .continuous)
                            .frame(width: spotlight.width, height: spotlight.height)
                            .position(x: spotlight.midX, y: spotlight.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            if let spotlight {
                RoundedRectangle(cornerRadius: min(cornerRadius, spotlight.height / 2), style: .continuous)
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

/// Pose la bulle sous l'élément s'il y a la place, sinon au-dessus, sinon du côté le plus grand (le texte défile).
/// Sans élément, elle est au centre. La place est mesurée avec la vraie hauteur de la bulle.
private struct TourBubbleLayout: Layout {
    var spot: CGRect?
    var insets: EdgeInsets

    private let gap: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let width = min(bounds.width - 32, 520)
        let ideal = bubble.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let top = bounds.minY + insets.top + 8
        let bottom = bounds.maxY - insets.bottom - 8
        let height: CGFloat
        let originY: CGFloat
        var anchorPoint = UnitPoint.top
        if let spot {
            let below = bottom - (spot.maxY + gap)
            let above = (spot.minY - gap) - top
            if ideal <= below {
                height = ideal
                originY = spot.maxY + gap
            } else if ideal <= above {
                height = ideal
                originY = spot.minY - gap
                anchorPoint = .bottom
            } else if below >= above {
                height = max(below, 160)
                originY = spot.maxY + gap
            } else {
                height = max(above, 160)
                originY = spot.minY - gap
                anchorPoint = .bottom
            }
        } else {
            height = min(ideal, bottom - top)
            originY = top + (bottom - top - height) / 2
        }
        bubble.place(
            at: CGPoint(x: bounds.midX, y: originY),
            anchor: anchorPoint,
            proposal: ProposedViewSize(width: width, height: height)
        )
    }
}

// MARK: - Bulle

private struct TourBubble: View {
    let step: TourStep
    let index: Int
    let count: Int
    let tour: GuidedTour
    /// L'élément de l'étape n'est pas à l'écran (écran vide) : une note l'explique.
    var isEmpty = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var mascotSize: CGFloat = 52

    private var isLast: Bool { index == count - 1 }
    private var progress: String { String(localized: "Étape \(index + 1) sur \(count)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
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
                    if isEmpty {
                        Label("Rien à montrer ici pour l'instant : l'élément apparaîtra dès que cet écran sera rempli.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.texteSecondaire)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            }
            .scrollBounceBehavior(.basedOnSize)
            dots
            controls
        }
        .padding(18)
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
            TourMascotView(tour: tour.tour, size: mascotSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tour.tour.mascotName)
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
        let title = step.title
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

/// La mascotte de la visite : Noisette (écureuil) ou Racoonette (raton laveur).
struct TourMascotView: View {
    let tour: TourID
    var size: CGFloat = 120
    var isAnimated = true

    var body: some View {
        switch tour {
        case .noisette: MascotView(size: size, isAnimated: isAnimated)
        case .racoonette: RacoonetteView(size: size, isAnimated: isAnimated)
        }
    }
}

#Preview("Noisette, étape 1") {
    let tour = GuidedTour(tour: .noisette, store: GuidedTourStore(defaults: UserDefaults(suiteName: "preview.tour")!), isEnabled: true)
    TourBubble(step: .intro, index: 0, count: TourID.noisette.steps.count, tour: tour)
        .padding()
        .grenierBackground()
}

#Preview("Racoonette, sombre") {
    let tour = GuidedTour(tour: .racoonette, store: GuidedTourStore(defaults: UserDefaults(suiteName: "preview.tour")!), isEnabled: true)
    TourBubble(step: .vendorProfile, index: 9, count: TourID.racoonette.steps.count, tour: tour, isEmpty: true)
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
