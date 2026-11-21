import SwiftUI

// Célébration « Palier débloqué ! » (maquette F4) : le prix baisse pour tout le groupe.
//
// Usage (écran F3/F4, sans état global) :
//
//     .tierUnlockedCelebration(
//         isPresented: $celebrating,
//         oldPriceCents: 260, newPriceCents: 210, unit: "kg",
//         savingsPercent: 49, groupName: "Parc-Ex Ouest"
//     )
//
// Sceau `checkmark.seal.fill` en Économie qui rebondit, ancien prix qui bascule vers le nouveau
// (`.numericText`), pluie de confettis aux couleurs du thème pendant 2 s, haptique de succès,
// fermeture automatique après 3 s, par tap ou par le bouton « Super ! ».
// Reduce Motion : ni confettis ni rebond, un simple fondu. VoiceOver : annonce du nouveau prix,
// et pas de fermeture automatique (on laisse le temps de lire).

// MARK: - Contenu (logique pure, testée)

/// Textes de la célébration, calculés à partir des prix et du groupe.
struct TierUnlockedCelebrationContent: Equatable, Sendable {
    let oldPriceCents: Cents
    let newPriceCents: Cents
    /// « kg », « L », « caisse »… Affiché « 2,10 $/kg ».
    let unit: String
    /// Économie du nouveau prix par rapport à l'épicerie (49 pour « −49 % vs épicerie ») ; 0 pour ne pas l'afficher.
    let savingsPercent: Int
    let groupName: String

    /// Durée avant la fermeture automatique.
    static let autoDismissDelay: Duration = .seconds(3)

    var title: String { "Palier débloqué !" }

    var oldPriceText: String { Money.format(oldPriceCents) }
    var newPriceText: String { Money.format(newPriceCents) }
    var unitSuffix: String { "/\(unit)" }

    /// « Grâce à Parc-Ex Ouest, tout le monde paie 2,10 $/kg. »
    var message: String {
        "Grâce à \(groupName), tout le monde paie \(newPriceText)\(unitSuffix)."
    }

    /// Pilule d'économie, seulement si le nouveau prix économise vraiment quelque chose.
    var savingsBadge: SavingsBadge.Kind? {
        savingsPercent > 0 ? .percent(savingsPercent) : nil
    }

    /// Annonce VoiceOver : « Palier débloqué, nouveau prix 2 dollars 10 le kilo ».
    var announcement: String {
        "Palier débloqué, nouveau prix \(Money.spoken(newPriceCents, per: unit))"
    }

    /// Lecture du prix pour VoiceOver : « Nouveau prix 2 dollars 10 le kilo, au lieu de 2 dollars 60 ».
    var priceAccessibilityText: String {
        "Nouveau prix \(Money.spoken(newPriceCents, per: unit)), au lieu de \(Money.spoken(oldPriceCents))"
    }

    /// Lecture de l'unité pour VoiceOver (voir `Money.spokenPerUnit`).
    static func spokenUnit(_ unit: String) -> String {
        Money.spokenPerUnit(unit)
    }
}

// MARK: - Confettis (logique pure, testée)

/// Un confetti : position de départ, vitesse, rotation, couleur. Coordonnées relatives (0…1).
struct ConfettiParticle: Equatable, Sendable {
    var startX: Double
    var startY: Double
    var delay: Double
    var speed: Double
    var swayAmplitude: Double
    var swayFrequency: Double
    var phase: Double
    var spin: Double
    var flip: Double
    var scale: Double
    var colorIndex: Int
    var isRound: Bool
}

/// Position d'un confetti à un instant donné.
struct ConfettiFrame: Equatable, Sendable {
    var x: Double
    var y: Double
    var rotation: Double
    /// −1…1 : écrasement horizontal qui simule le retournement du papier.
    var flipScale: Double
    var opacity: Double
}

enum Confetti {
    /// Durée totale de la pluie.
    static let duration: TimeInterval = 2
    static let defaultCount = 64
    /// Nombre de couleurs du thème utilisées (Grenier, Économie, Solidarité).
    static let paletteCount = 3

    private static let gravity = 0.32
    private static let fadeIn = 0.12
    private static let fadeOut = 0.5

    /// Génère des confettis de façon déterministe (même graine, même pluie).
    static func particles(count: Int = defaultCount, seed: UInt64 = 26) -> [ConfettiParticle] {
        var rng = SplitMix64(seed: seed)
        return (0..<max(0, count)).map { index in
            ConfettiParticle(
                startX: Double.random(in: 0.02...0.98, using: &rng),
                startY: Double.random(in: -0.12 ... -0.02, using: &rng),
                delay: Double.random(in: 0...0.45, using: &rng),
                speed: Double.random(in: 0.18...0.4, using: &rng),
                swayAmplitude: Double.random(in: 0.01...0.04, using: &rng),
                swayFrequency: Double.random(in: 3...7, using: &rng),
                phase: Double.random(in: 0...(2 * .pi), using: &rng),
                spin: Double.random(in: -6...6, using: &rng),
                flip: Double.random(in: 4...10, using: &rng),
                scale: Double.random(in: 0.7...1.2, using: &rng),
                colorIndex: index % paletteCount,
                isRound: Double.random(in: 0...1, using: &rng) < 0.25
            )
        }
    }

    /// Où est le confetti au temps `time` (secondes depuis le début) ; nil s'il n'est pas visible.
    static func frame(of particle: ConfettiParticle, at time: TimeInterval) -> ConfettiFrame? {
        let local = time - particle.delay
        guard local >= 0, time < duration else { return nil }
        let y = particle.startY + particle.speed * local + 0.5 * gravity * local * local
        let x = particle.startX + particle.swayAmplitude * sin(local * particle.swayFrequency + particle.phase)
        let fadeInOpacity = min(1, local / fadeIn)
        let fadeOutOpacity = min(1, max(0, (duration - time) / fadeOut))
        return ConfettiFrame(
            x: x,
            y: y,
            rotation: particle.phase + particle.spin * local,
            flipScale: cos(particle.phase + particle.flip * local),
            opacity: min(fadeInOpacity, fadeOutOpacity)
        )
    }
}

/// Générateur pseudo-aléatoire à graine, pour des confettis reproductibles (previews, tests).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Pluie de confettis dessinée dans un `Canvas`, légère et non interactive.
struct ConfettiRain: View {
    let start: Date
    private let particles = Confetti.particles()
    private let palette: [Color] = [.grenier, .economie, .solidarite]

    @ScaledMetric private var pieceWidth: CGFloat = 7
    @ScaledMetric private var pieceHeight: CGFloat = 13

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(start)
                // La taille des confettis ne suit pas Dynamic Type au-delà d'un léger agrandissement.
                let width = min(pieceWidth, 10)
                let height = min(pieceHeight, 18)
                for particle in particles {
                    guard let frame = Confetti.frame(of: particle, at: time) else { continue }
                    var piece = context
                    piece.opacity = frame.opacity
                    piece.translateBy(x: frame.x * size.width, y: frame.y * size.height)
                    piece.rotate(by: .radians(frame.rotation))
                    piece.scaleBy(x: max(0.15, abs(frame.flipScale)) * particle.scale, y: particle.scale)
                    let color = palette[particle.colorIndex % palette.count]
                    if particle.isRound {
                        let rect = CGRect(x: -width / 2, y: -width / 2, width: width, height: width)
                        piece.fill(Path(ellipseIn: rect), with: .color(color))
                    } else {
                        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                        piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Vue

/// Overlay plein écran « Palier débloqué ! ». Présenté par `.tierUnlockedCelebration(isPresented:…)`.
struct TierUnlockedCelebration: View {
    let content: TierUnlockedCelebrationContent
    var onDismiss: () -> Void
    /// Affiche directement l'état final, sans animation (rendus statiques, captures).
    var startsSettled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showsNewPrice = false
    @State private var cardVisible = false
    @State private var bounce = 0
    @State private var confettiStart: Date?

    @ScaledMetric(relativeTo: .largeTitle) private var sealDiameter: CGFloat = 112
    @ScaledMetric(relativeTo: .largeTitle) private var sealSymbolSize: CGFloat = 56

    init(
        oldPriceCents: Cents,
        newPriceCents: Cents,
        unit: String = "kg",
        savingsPercent: Int,
        groupName: String,
        onDismiss: @escaping () -> Void
    ) {
        content = TierUnlockedCelebrationContent(
            oldPriceCents: oldPriceCents,
            newPriceCents: newPriceCents,
            unit: unit,
            savingsPercent: savingsPercent,
            groupName: groupName
        )
        self.onDismiss = onDismiss
    }

    /// Copie figée sur l'état final (nouveau prix affiché), pour les rendus statiques.
    func settled() -> TierUnlockedCelebration {
        var copy = self
        copy.startsSettled = true
        copy._showsNewPrice = State(initialValue: true)
        copy._cardVisible = State(initialValue: true)
        return copy
    }

    var body: some View {
        ZStack {
            backdrop
            GeometryReader { proxy in
                ScrollView {
                    card
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if let confettiStart {
                ConfettiRain(start: confettiStart)
                    .ignoresSafeArea()
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .task { await run() }
    }

    // MARK: Parties

    private var backdrop: some View {
        ZStack {
            // Reduce Transparency : fond plein, l'écran du dessous ne transparaît plus.
            Color.fond.opacity(reduceTransparency ? 1 : 0.92)
            LinearGradient(
                colors: [Color.grenier.opacity(0.22), Color.grenier.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(spacing: 20) {
            seal
            VStack(spacing: 8) {
                Text(content.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.texte)
                    .accessibilityAddTraits(.isHeader)
                Text(content.message)
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            priceRow

            if let badge = content.savingsBadge {
                SavingsBadge(kind: badge)
            }

            Button(action: onDismiss) {
                Label("Super !", systemImage: "hand.thumbsup.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(Color.grenier)
            .accessibilityHint("Ferme la célébration")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.surface, in: .rect(cornerRadius: 32))
        .shadow(color: .texte.opacity(0.08), radius: 8, y: 2)
        .scaleEffect(cardVisible || reduceMotion ? 1 : 0.92)
        .opacity(cardVisible || reduceMotion ? 1 : 0)
    }

    private var seal: some View {
        let diameter = min(sealDiameter, 180)
        return Image(systemName: "checkmark.seal.fill")
            .font(.system(size: min(sealSymbolSize, 90), weight: .semibold))
            .foregroundStyle(Color.onAccent)
            .symbolEffect(.bounce, options: .speed(0.8), value: reduceMotion ? 0 : bounce)
            .frame(width: diameter, height: diameter)
            .background(Color.economie, in: .circle)
            .shadow(color: .economie.opacity(0.35), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                oldPrice
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.texteSecondaire)
                    .opacity(showsNewPrice ? 1 : 0)
                newPrice
            }
            VStack(spacing: 4) {
                oldPrice
                newPrice
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.priceAccessibilityText)
    }

    private var oldPrice: some View {
        Text(content.oldPriceText)
            .priceStyle(.title2.bold())
            .strikethrough()
            .foregroundStyle(.texteSecondaire)
            .opacity(showsNewPrice ? 1 : 0)
    }

    private var newPrice: some View {
        let cents = showsNewPrice ? content.newPriceCents : content.oldPriceCents
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(Money.format(cents))
                .priceStyle(.largeTitle.bold())
                .foregroundStyle(Color.grenier)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(cents)))
            Text(content.unitSuffix)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6) // AX5 : le prix rétrécit plutôt que d'être coupé en « … ».
    }

    // MARK: Séquence

    private func run() async {
        guard !startsSettled else { return }
        AccessibilityNotification.Announcement(content.announcement).post()

        if reduceMotion {
            showsNewPrice = true
        } else {
            withAnimation(.smooth(duration: 0.35)) { cardVisible = true }
            confettiStart = .now
            bounce += 1
        }

        do {
            if !reduceMotion {
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.smooth(duration: 0.6)) { showsNewPrice = true }
                bounce += 1
                try await Task.sleep(for: .milliseconds(1_500))
                confettiStart = nil
                try await Task.sleep(for: .seconds(1))
            } else {
                try await Task.sleep(for: TierUnlockedCelebrationContent.autoDismissDelay)
            }
        } catch {
            return // Fermée avant la fin (tap, bouton) : rien d'autre à faire.
        }

        // Avec VoiceOver, on laisse la personne fermer elle-même.
        if !voiceOverEnabled { onDismiss() }
    }
}

// MARK: - Modificateur

private struct TierUnlockedCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let oldPriceCents: Cents
    let newPriceCents: Cents
    let unit: String
    let savingsPercent: Int
    let groupName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    TierUnlockedCelebration(
                        oldPriceCents: oldPriceCents,
                        newPriceCents: newPriceCents,
                        unit: unit,
                        savingsPercent: savingsPercent,
                        groupName: groupName,
                        onDismiss: { isPresented = false }
                    )
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.35), value: isPresented)
            .sensoryFeedback(.success, trigger: isPresented) { _, isNowPresented in isNowPresented }
    }
}

extension View {
    /// Présente la célébration « Palier débloqué ! » par-dessus la vue (maquette F4).
    /// - Parameters:
    ///   - isPresented: passe à `true` quand le palier tombe ; remis à `false` à la fermeture (3 s, tap ou « Super ! »).
    ///   - oldPriceCents: prix du palier précédent (260 pour 2,60 $).
    ///   - newPriceCents: prix du palier débloqué (210 pour 2,10 $).
    ///   - unit: unité de vente (« kg »).
    ///   - savingsPercent: économie du nouveau prix vs l'épicerie ; 0 pour masquer la pilule.
    ///   - groupName: groupe qui a fait tomber le palier (« Parc-Ex Ouest »).
    func tierUnlockedCelebration(
        isPresented: Binding<Bool>,
        oldPriceCents: Cents,
        newPriceCents: Cents,
        unit: String = "kg",
        savingsPercent: Int,
        groupName: String
    ) -> some View {
        modifier(
            TierUnlockedCelebrationModifier(
                isPresented: isPresented,
                oldPriceCents: oldPriceCents,
                newPriceCents: newPriceCents,
                unit: unit,
                savingsPercent: savingsPercent,
                groupName: groupName
            )
        )
    }
}

// MARK: - Previews

private struct TierUnlockedCelebrationPreviewHost: View {
    @State private var celebrating = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PriceTag(priceCents: celebrating ? 260 : 210, unit: "kg", referenceCents: 410)
                Button("Rejouer la célébration") { celebrating = true }
                    .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Riz basmati")
        }
        .tierUnlockedCelebration(
            isPresented: $celebrating,
            oldPriceCents: 260,
            newPriceCents: 210,
            unit: "kg",
            savingsPercent: 49,
            groupName: "Parc-Ex Ouest"
        )
    }
}

#Preview("Clair") {
    TierUnlockedCelebrationPreviewHost()
}

#Preview("Sombre") {
    TierUnlockedCelebrationPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    TierUnlockedCelebrationPreviewHost()
        .dynamicTypeSize(.accessibility5)
}

#Preview("AX5 sombre") {
    TierUnlockedCelebrationPreviewHost()
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}
