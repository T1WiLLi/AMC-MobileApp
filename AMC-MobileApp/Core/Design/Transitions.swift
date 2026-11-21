import SwiftUI

// Transitions d'écran du design system Grenier (T-123), en complément de `Motion.swift`.
//
// | Outil                          | Quand                                                     | Reduce Motion          |
// | ------------------------------ | --------------------------------------------------------- | ---------------------- |
// | `.grenierAppear(index:)`       | cartes d'une liste qui arrivent en cascade au 1er affichage | fondu court, sans délai |
// | `.grenierAppear(index:, .sheet)` | contenu d'une feuille, plus serré                         | fondu court, sans délai |
// | `.grenierTabContent(isSelected:)` | contenu d'un onglet qui revient au premier plan         | fondu seul (inchangé)  |
// | `.grenierZoomDestination(for:)` + `.grenierZoomSource(_:)` | carte → fiche en zoom (iOS 18+) | géré par le système    |
//
// Exemples :
//
//     ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
//         NavigationLink(value: GroupRoute(groupId: item.id)) {
//             GroupRow(item: item)
//                 .grenierZoomSource(GroupRoute(groupId: item.id))   // la fiche sort de la carte
//         }
//         .grenierAppear(index: index)                               // cascade au premier affichage
//     }
//     …
//     .grenierZoomDestination(for: GroupRoute.self) { GroupDetailScreen(groupId: $0.groupId) }
//
// Les effets d'apparition sont purement visuels (opacité, décalage, échelle) : aucun saut de mise en page.

// MARK: - Apparition en cascade

/// Style d'apparition : cartes d'une liste ou contenu d'une feuille.
enum GrenierAppearStyle: CaseIterable, Sendable {
    /// Cartes d'une liste : montent de 16 pt avec un léger zoom.
    case cards
    /// Contenu d'une feuille : plus discret et plus rapide.
    case sheet

    /// Paramètres de l'effet, décrits pour les tests.
    struct Effects: Equatable, Sendable {
        /// Décalage vertical de départ (pt).
        var offsetY: CGFloat
        /// Échelle de départ.
        var scale: CGFloat
        /// Écart entre deux éléments (s).
        var interval: Double
        /// Au-delà de cet index, plus de délai supplémentaire : la cascade ne traîne jamais.
        var maxStaggeredIndex: Int
    }

    func effects(reduceMotion: Bool) -> Effects {
        if reduceMotion { return Effects(offsetY: 0, scale: 1, interval: 0, maxStaggeredIndex: 0) }
        switch self {
        case .cards: return Effects(offsetY: 16, scale: 0.97, interval: 0.05, maxStaggeredIndex: 6)
        case .sheet: return Effects(offsetY: 10, scale: 1, interval: 0.04, maxStaggeredIndex: 5)
        }
    }

    /// Délai avant l'apparition de l'élément `index` (borné, nul sous Reduce Motion).
    func delay(for index: Int, reduceMotion: Bool) -> Double {
        let effects = effects(reduceMotion: reduceMotion)
        return Double(min(max(index, 0), effects.maxStaggeredIndex)) * effects.interval
    }

    func animation(for index: Int, reduceMotion: Bool) -> Animation {
        let base: Animation = reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.45)
        return base.delay(delay(for: index, reduceMotion: reduceMotion))
    }
}

private struct GrenierAppearModifier: ViewModifier {
    let index: Int
    let style: GrenierAppearStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Joué une seule fois : revenir sur l'écran (onglet, retour arrière) ne rejoue pas la cascade.
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let effects = style.effects(reduceMotion: reduceMotion)
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : effects.offsetY)
            .scaleEffect(isVisible ? 1 : effects.scale)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(style.animation(for: index, reduceMotion: reduceMotion)) { isVisible = true }
            }
    }
}

extension View {
    /// Apparition en cascade au premier affichage : `index` = position dans la liste.
    func grenierAppear(index: Int, style: GrenierAppearStyle = .cards) -> some View {
        modifier(GrenierAppearModifier(index: index, style: style))
    }
}

// MARK: - Contenu d'onglet

/// Fondu du contenu d'un onglet quand il revient au premier plan. Ne touche pas à la barre d'onglets
/// (Liquid Glass), seulement à l'écran de l'onglet ; pas de déplacement, donc rien à couper sous Reduce Motion.
enum GrenierTabEntrance {
    /// Opacité de départ du contenu qui arrive.
    static let startOpacity: Double = 0.35
    /// Durée du fondu (s).
    static let duration: Double = 0.24
}

private struct GrenierTabContentModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: isSelected) { view, opacity in
            view.opacity(opacity)
        } keyframes: { _ in
            MoveKeyframe(GrenierTabEntrance.startOpacity)
            CubicKeyframe(1, duration: GrenierTabEntrance.duration)
        }
    }
}

extension View {
    /// Fondu d'entrée du contenu d'un onglet ; à poser sur chaque `Tab` d'un `TabView`.
    ///
    ///     Tab("Accueil", systemImage: "house.fill", value: .home) {
    ///         FamilyHomeScreen().grenierTabContent(isSelected: selection == .home)
    ///     }
    func grenierTabContent(isSelected: Bool) -> some View {
        modifier(GrenierTabContentModifier(isSelected: isSelected))
    }
}

// MARK: - Zoom carte → fiche

/// Sources de zoom actuellement à l'écran. La fiche ne zoome que si sa carte est là ; sinon
/// (lien depuis une carte, un bouton, une notification) elle arrive par la poussée standard.
@MainActor
final class GrenierZoomRegistry {
    private var counts: [AnyHashable: Int] = [:]

    func register(_ id: AnyHashable) { counts[id, default: 0] += 1 }

    func unregister(_ id: AnyHashable) {
        guard let count = counts[id] else { return }
        counts[id] = count > 1 ? count - 1 : nil
    }

    func contains(_ id: AnyHashable) -> Bool { counts[id] != nil }
}

/// Espace de zoom partagé par un `NavigationStack` : toutes les destinations de la pile l'utilisent.
struct GrenierZoomScope {
    let namespace: Namespace.ID
    let registry: GrenierZoomRegistry
}

extension EnvironmentValues {
    @Entry var grenierZoomScope: GrenierZoomScope? = nil
}

private struct GrenierZoomSourceModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.grenierZoomScope) private var scope

    func body(content: Content) -> some View {
        if let scope {
            content
                .matchedTransitionSource(id: id, in: scope.namespace)
                .onAppear { scope.registry.register(id) }
                .onDisappear { scope.registry.unregister(id) }
        } else {
            content
        }
    }
}

/// Fiche poussée : choisit une fois pour toutes (à la poussée) entre zoom et poussée standard,
/// pour ne jamais changer l'identité de la vue (et perdre son état) ensuite.
private struct GrenierZoomDestinationView<Destination: View>: View {
    let id: AnyHashable
    let namespace: Namespace.ID
    let destination: Destination
    @State private var zooms: Bool

    init(id: AnyHashable, scope: GrenierZoomScope, destination: Destination) {
        self.id = id
        self.namespace = scope.namespace
        self.destination = destination
        _zooms = State(initialValue: scope.registry.contains(id))
    }

    var body: some View {
        if zooms {
            destination.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            destination
        }
    }
}

private struct GrenierZoomDestinationModifier<Route: Hashable, Destination: View>: ViewModifier {
    let destination: (Route) -> Destination

    @Environment(\.grenierZoomScope) private var inherited
    @Namespace private var namespace
    @State private var registry = GrenierZoomRegistry()

    func body(content: Content) -> some View {
        // Une seule portée par pile : la première destination enregistrée la crée, les autres la réutilisent.
        let scope = inherited ?? GrenierZoomScope(namespace: namespace, registry: registry)
        content
            .navigationDestination(for: Route.self) { route in
                GrenierZoomDestinationView(id: AnyHashable(route), scope: scope, destination: destination(route))
            }
            .environment(\.grenierZoomScope, scope)
    }
}

extension View {
    /// `navigationDestination(for:)` dont la fiche sort en zoom de la carte marquée `.grenierZoomSource(route)`.
    func grenierZoomDestination<Route: Hashable, Destination: View>(
        for route: Route.Type,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) -> some View {
        modifier(GrenierZoomDestinationModifier(destination: destination))
    }

    /// Carte d'où sort la fiche de `route` (même valeur que celle du `NavigationLink`).
    func grenierZoomSource(_ route: some Hashable) -> some View {
        modifier(GrenierZoomSourceModifier(id: AnyHashable(route)))
    }
}

// MARK: - Démo

private struct TransitionsDemo: View {
    struct Route: Hashable { let index: Int }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(0..<8, id: \.self) { index in
                        NavigationLink(value: Route(index: index)) {
                            Label("Lot n° \(index + 1)", systemImage: "shippingbox.fill")
                                .font(.headline)
                                .foregroundStyle(.texte)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .grenierCard()
                                .grenierZoomSource(Route(index: index))
                        }
                        .pressable()
                        .grenierAppear(index: index)
                    }
                }
                .padding()
            }
            .grenierBackground()
            .navigationTitle("Transitions")
            .grenierZoomDestination(for: Route.self) { route in
                Label("Lot n° \(route.index + 1)", systemImage: "shippingbox.fill")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
            }
        }
    }
}

#Preview("Transitions") {
    TransitionsDemo()
}

#Preview("Transitions sombre") {
    TransitionsDemo()
        .preferredColorScheme(.dark)
}
