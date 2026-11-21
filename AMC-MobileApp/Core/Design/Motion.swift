import SwiftUI

// Mouvement du design system Grenier : toute l'app bouge de la même façon.
//
// Trois animations nommées, sur les springs natifs d'iOS 26 :
//
// | Animation        | Quand                                                        | Reduce Motion            |
// | ---------------- | ------------------------------------------------------------ | ------------------------ |
// | `.grenierSnappy` | Sélection : choix de part, filtre, onglet interne, appui     | aucune (changement net)  |
// | `.grenierSmooth` | Changement d'état : prix, barre de palier, carte qui s'ouvre | fondu bref (0,2 s)       |
// | `.grenierBouncy` | Célébration : palier débloqué, paiement réussi (rare !)      | fondu bref (0,25 s)      |
//
// Règle : ne pas appeler `withAnimation(.grenierBouncy)` directement dans une vue. Passer par
// `withGrenierAnimation` ou `.grenierAnimation`, qui appliquent la variante Reduce Motion.
//
// Exemples :
//
//     @Environment(\.accessibilityReduceMotion) private var reduceMotion
//
//     Button("10 kg") {
//         withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { share = 10 }
//     }
//
//     PriceTag(priceCents: price)
//         .grenierAnimation(.smooth, value: price)      // lit Reduce Motion tout seul
//
//     if tierUnlocked {
//         UnlockedBanner()
//             .grenierTransition(.celebration)          // `.opacity` seul sous Reduce Motion
//     }
//
//     NavigationLink(value: offer) { OfferCard(...) }
//         .pressable()                                  // carte tapable : léger enfoncement
//
// Haptique assortie : voir `Haptics.swift` (`.grenierHaptic(.success, trigger:)`).

// MARK: - Animations nommées

/// Les trois mouvements de Grenier. Le choix se fait selon le sens, pas selon le goût.
enum GrenierMotion: CaseIterable, Sendable {
    /// Sélection : réponse immédiate, presque sans rebond.
    case snappy
    /// Changement d'état : fluide, sans rebond.
    case smooth
    /// Célébration : rebond visible, réservé aux moments forts.
    case bouncy

    /// Description testable de la courbe réellement jouée.
    enum Curve: Equatable, Sendable {
        case snappy(duration: Double)
        case smooth(duration: Double)
        case bouncy(duration: Double, extraBounce: Double)
        /// Fondu bref, sans déplacement ni rebond (Reduce Motion).
        case fade(duration: Double)
        /// Aucun mouvement : le changement est appliqué tout de suite.
        case none
    }

    /// Courbe à jouer selon le réglage Reduce Motion.
    func curve(reduceMotion: Bool) -> Curve {
        switch (self, reduceMotion) {
        case (.snappy, false): .snappy(duration: 0.3)
        case (.smooth, false): .smooth(duration: 0.4)
        case (.bouncy, false): .bouncy(duration: 0.5, extraBounce: 0.05)
        case (.snappy, true): .none
        case (.smooth, true): .fade(duration: 0.2)
        case (.bouncy, true): .fade(duration: 0.25)
        }
    }

    /// Animation SwiftUI, `nil` quand il ne faut aucun mouvement.
    func animation(reduceMotion: Bool) -> Animation? {
        switch curve(reduceMotion: reduceMotion) {
        case .snappy(let duration): .snappy(duration: duration)
        case .smooth(let duration): .smooth(duration: duration)
        case .bouncy(let duration, let extraBounce): .bouncy(duration: duration, extraBounce: extraBounce)
        case .fade(let duration): .easeInOut(duration: duration)
        case .none: nil
        }
    }
}

extension Animation {
    /// Sélection (sans tenir compte de Reduce Motion : préférer `withGrenierAnimation`).
    static var grenierSnappy: Animation { GrenierMotion.snappy.animation(reduceMotion: false) ?? .default }
    /// Changement d'état (sans tenir compte de Reduce Motion : préférer `withGrenierAnimation`).
    static var grenierSmooth: Animation { GrenierMotion.smooth.animation(reduceMotion: false) ?? .default }
    /// Célébration (sans tenir compte de Reduce Motion : préférer `withGrenierAnimation`).
    static var grenierBouncy: Animation { GrenierMotion.bouncy.animation(reduceMotion: false) ?? .default }

    /// Animation Grenier adaptée à Reduce Motion (`nil` = pas d'animation).
    static func grenier(_ motion: GrenierMotion, reduceMotion: Bool) -> Animation? {
        motion.animation(reduceMotion: reduceMotion)
    }
}

/// `withAnimation` à la mode Grenier : applique la variante Reduce Motion.
///
///     withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { isExpanded.toggle() }
@discardableResult
func withGrenierAnimation<Result>(
    _ motion: GrenierMotion = .smooth,
    reduceMotion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(motion.animation(reduceMotion: reduceMotion), body)
}

private struct GrenierAnimationModifier<Value: Equatable>: ViewModifier {
    let motion: GrenierMotion
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Anime les changements de `value` avec un mouvement Grenier ; lit `accessibilityReduceMotion`.
    func grenierAnimation<Value: Equatable>(_ motion: GrenierMotion, value: Value) -> some View {
        modifier(GrenierAnimationModifier(motion: motion, value: value))
    }
}

// MARK: - Transitions nommées

/// Apparitions et disparitions. Sous Reduce Motion, toutes deviennent `.opacity` seul.
enum GrenierTransition: CaseIterable, Sendable {
    /// Carte qui entre dans une liste : léger zoom (96 %) et fondu.
    case cardAppear
    /// Bandeau ou message qui glisse depuis le haut (ex. « Palier 3 atteint »).
    case banner
    /// Célébration : zoom plus marqué (80 %) et fondu, à jouer avec `.grenierBouncy`.
    case celebration

    /// Effets combinés au fondu, décrits pour les tests.
    struct Effects: Equatable, Sendable {
        /// Échelle de départ (1 = pas de zoom).
        var scale: CGFloat
        /// Bord d'où l'élément glisse, `nil` = sur place.
        var edge: Edge?
    }

    func effects(reduceMotion: Bool) -> Effects {
        if reduceMotion { return Effects(scale: 1, edge: nil) }
        switch self {
        case .cardAppear: return Effects(scale: 0.96, edge: nil)
        case .banner: return Effects(scale: 1, edge: .top)
        case .celebration: return Effects(scale: 0.8, edge: nil)
        }
    }

    func transition(reduceMotion: Bool) -> AnyTransition {
        let effects = effects(reduceMotion: reduceMotion)
        var transition = AnyTransition.opacity
        if effects.scale != 1 { transition = transition.combined(with: .scale(scale: effects.scale)) }
        if let edge = effects.edge { transition = transition.combined(with: .move(edge: edge)) }
        return transition
    }
}

private struct GrenierTransitionModifier: ViewModifier {
    let kind: GrenierTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(kind.transition(reduceMotion: reduceMotion))
    }
}

extension View {
    /// Transition Grenier ; `.opacity` seul sous Reduce Motion. À déclencher dans `withGrenierAnimation`.
    func grenierTransition(_ kind: GrenierTransition) -> some View {
        modifier(GrenierTransitionModifier(kind: kind))
    }
}

// MARK: - Appui sur une carte tapable

/// Style d'appui des cartes tapables : léger enfoncement au toucher.
///
/// Repose sur `Button` / `NavigationLink`, donc :
/// - l'état enfoncé s'affiche tout de suite, l'action part seulement au relâcher ;
/// - glisser hors de la carte ou faire défiler annule l'appui, sans action ;
/// - VoiceOver, clavier et Contrôle de sélection déclenchent la même action.
/// Sous Reduce Motion, pas de changement d'échelle : la carte s'assombrit légèrement.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let pressedScale: CGFloat = 0.97
    static let pressedOpacity: Double = 0.8

    static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? pressedScale : 1
    }

    static func opacity(isPressed: Bool, reduceMotion: Bool) -> Double {
        isPressed && reduceMotion ? pressedOpacity : 1
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect(cornerRadius: 24))
            .scaleEffect(Self.scale(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .opacity(Self.opacity(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .animation(GrenierMotion.snappy.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)` : carte tapable Grenier.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension View {
    /// Carte tapable : à poser sur un `Button` ou un `NavigationLink` qui enveloppe la carte.
    ///
    ///     NavigationLink(value: offer) { OfferCard(...) }.pressable()
    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Démo

private struct MotionDemo: View {
    @State private var simulateReduceMotion = false
    @State private var selection = 10
    @State private var priceCents: Cents = 260
    @State private var showsCard = true
    @State private var celebrates = false
    @State private var taps = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Simuler Reduce Motion", isOn: $simulateReduceMotion)
                    .tint(.grenier)

                Text("Snappy : sélection").font(.headline)
                HStack {
                    ForEach([5, 10, 20], id: \.self) { kg in
                        Button("\(kg) kg") {
                            withGrenierAnimation(.snappy, reduceMotion: simulateReduceMotion) { selection = kg }
                        }
                        .buttonStyle(.glass)
                        .tint(selection == kg ? .grenier : nil)
                        .scaleEffect(selection == kg ? 1.08 : 1)
                    }
                }

                Text("Smooth : changement d'état").font(.headline)
                Button("Changer de palier") {
                    withGrenierAnimation(.smooth, reduceMotion: simulateReduceMotion) {
                        priceCents = priceCents == 260 ? 210 : 260
                        showsCard.toggle()
                    }
                }
                .buttonStyle(.glass)
                Text(Money.format(priceCents)).priceStyle()
                    .contentTransition(.numericText())
                if showsCard {
                    Text("Nouveau lot près de toi")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .grenierCard()
                        .transition(GrenierTransition.cardAppear.transition(reduceMotion: simulateReduceMotion))
                }

                Text("Bouncy : célébration").font(.headline)
                Button("Débloquer le palier") {
                    withGrenierAnimation(.bouncy, reduceMotion: simulateReduceMotion) { celebrates.toggle() }
                }
                .buttonStyle(.glassProminent)
                .grenierHaptic(.success, trigger: celebrates) { _, new in new }
                if celebrates {
                    Label("Palier débloqué !", systemImage: "checkmark.seal.fill")
                        .font(.title2.bold())
                        .foregroundStyle(Color.grenier)
                        .transition(GrenierTransition.celebration.transition(reduceMotion: simulateReduceMotion))
                }

                Text("Pressable : carte tapable").font(.headline)
                Button { taps += 1 } label: {
                    VStack(alignment: .leading) {
                        Text("Riz basmati · 10 kg").font(.headline).foregroundStyle(.texte)
                        Text("Touché \(taps) fois").font(.subheadline).foregroundStyle(.texteSecondaire)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard()
                }
                .pressable()
                .grenierHaptic(.selection, trigger: taps)
            }
            .padding()
        }
        .grenierBackground()
    }
}

#Preview("Mouvement") {
    MotionDemo()
}

#Preview("Mouvement sombre") {
    MotionDemo()
        .preferredColorScheme(.dark)
}
