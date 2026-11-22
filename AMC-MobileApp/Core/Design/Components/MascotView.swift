import SwiftUI

/// Noisette, l'écureuil du quartier : la mascotte du Grenier (FB-19).
/// Dessinée uniquement avec des SF Symbols composés (aucune image) : une feuille retournée pour la queue en panache,
/// des disques pour le corps, la tête et le ventre, des triangles pour les oreilles et une goutte pour la noisette.
///
///     MascotView(size: 132)
///
/// - Elle sautille à l'apparition et quand on la touche ; sa queue s'agite de temps en temps (`.wiggle`).
/// - Sous Reduce Motion (ou `isAnimated: false`), elle reste immobile.
/// - Un seul élément VoiceOver : « Noisette, l'écureuil du quartier ».
struct MascotView: View {
    /// Nom de la mascotte, repris dans la visite guidée.
    static let name = "Noisette"

    var size: CGFloat = 120
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hops = 0

    private var animates: Bool { isAnimated && !reduceMotion }
    /// Pelage : couleur système, lisible en clair comme en sombre, indépendante du thème choisi.
    private let fur = Color.brown

    var body: some View {
        ZStack {
            tail
            bodyShape
            head
            hazelnut
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: hops) { content, lift in
            content.offset(y: lift)
        } keyframes: { _ in
            SpringKeyframe(-size * 0.12, duration: 0.18, spring: .snappy)
            SpringKeyframe(0, duration: 0.4, spring: .bouncy)
        }
        .contentShape(.rect)
        .onTapGesture { hop() }
        .onAppear { hop() }
        .sensoryFeedback(.impact(weight: .light), trigger: hops)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Self.name), l'écureuil du quartier"))
        .accessibilityAddTraits(.isImage)
    }

    private func hop() {
        guard animates else { return }
        hops += 1
    }

    // MARK: Parties

    /// Queue en panache : une grande feuille retournée, derrière le corps.
    private var tail: some View {
        symbol("leaf.fill", width: size * 0.5, height: size * 0.72)
            .foregroundStyle(fur.opacity(0.8))
            .scaleEffect(x: -1)
            .rotationEffect(.degrees(-20))
            .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 2.5)), isActive: animates)
            .offset(x: size * 0.27, y: -size * 0.04)
    }

    private var bodyShape: some View {
        ZStack {
            symbol("circle.fill", side: size * 0.58)
                .foregroundStyle(fur)
            symbol("circle.fill", side: size * 0.32)
                .foregroundStyle(Color.fond)
                .offset(y: size * 0.06)
        }
        .offset(y: size * 0.17)
    }

    private var head: some View {
        ZStack {
            ear(x: -1)
            ear(x: 1)
            symbol("circle.fill", side: size * 0.5)
                .foregroundStyle(fur)
            // Museau clair, joues roses, yeux, nez et sourire.
            symbol("circle.fill", side: size * 0.22)
                .foregroundStyle(Color.fond)
                .offset(y: size * 0.08)
            ForEach([-1.0, 1.0], id: \.self) { side in
                symbol("circle.fill", side: size * 0.08)
                    .foregroundStyle(Color.solidarite.opacity(0.35))
                    .offset(x: side * size * 0.15, y: size * 0.06)
                symbol("circle.fill", side: size * 0.075)
                    .foregroundStyle(Color.texte)
                    .offset(x: side * size * 0.09, y: -size * 0.02)
            }
            symbol("circle.fill", side: size * 0.05)
                .foregroundStyle(Color.texte)
                .offset(y: size * 0.05)
            symbol("chevron.compact.down", width: size * 0.09, height: size * 0.04)
                .foregroundStyle(Color.texte)
                .offset(y: size * 0.11)
        }
        .offset(y: -size * 0.17)
    }

    private func ear(x side: CGFloat) -> some View {
        ZStack {
            symbol("triangle.fill", side: size * 0.17)
                .foregroundStyle(fur)
            symbol("triangle.fill", side: size * 0.08)
                .foregroundStyle(Color.solidarite.opacity(0.45))
                .offset(y: size * 0.02)
        }
        .rotationEffect(.degrees(side * 18))
        .offset(x: side * size * 0.15, y: -size * 0.22)
    }

    /// La noisette tenue contre le ventre, avec sa petite feuille.
    private var hazelnut: some View {
        ZStack {
            symbol("drop.fill", width: size * 0.13, height: size * 0.16)
                .foregroundStyle(fur.mix(with: .black, by: 0.3))
                .rotationEffect(.degrees(180))
            symbol("leaf.fill", side: size * 0.07)
                .foregroundStyle(Color.economie)
                .offset(x: size * 0.04, y: -size * 0.08)
        }
        .offset(y: size * 0.2)
    }

    private func symbol(_ name: String, side: CGFloat) -> some View {
        symbol(name, width: side, height: side)
    }

    private func symbol(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}

#Preview("Clair") {
    HStack(spacing: 24) {
        MascotView(size: 160)
        MascotView(size: 64, isAnimated: false)
    }
    .padding()
    .grenierBackground()
}

#Preview("Sombre") {
    MascotView(size: 160)
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
