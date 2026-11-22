import SwiftUI

/// Racoonette, le raton laveur du Grenier : la mascotte de la visite du portail Vendeurs.
/// Dessinée en formes SwiftUI (aucune image, aucun personnage existant) : un corps et une tête gris, le masque
/// sombre sur les yeux, les oreilles rondes, la queue rayée et une caisse de lot tenue contre le ventre.
/// Elle se distingue de Noisette (`MascotView`, l'écureuil brun et sa feuille-queue) par ses teintes grises,
/// son masque et sa caisse.
///
///     RacoonetteView(size: 132)
///
/// - Elle sautille à l'apparition et quand on la touche.
/// - Sous Reduce Motion (ou `isAnimated: false`), elle reste immobile.
/// - Un seul élément VoiceOver : « Racoonette, le raton laveur du Grenier ».
struct RacoonetteView: View {
    /// Nom de la mascotte, repris dans la visite guidée.
    static let name = "Racoonette"

    var size: CGFloat = 120
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hops = 0

    private var animates: Bool { isAnimated && !reduceMotion }
    /// Pelage, masque et museau : teintes fixes, lisibles en clair comme en sombre.
    private let fur = Color(white: 0.58)
    private let furShade = Color(white: 0.42)
    private let mask = Color(white: 0.14)
    private let muzzle = Color(white: 0.97)

    var body: some View {
        ZStack {
            tail
            bodyShape
            head
            crate
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
        .accessibilityLabel(Text("\(Self.name), le raton laveur du Grenier"))
        .accessibilityAddTraits(.isImage)
    }

    private func hop() {
        guard animates else { return }
        hops += 1
    }

    // MARK: Parties

    /// Queue rayée : un grand capuchon gris, trois anneaux sombres.
    private var tail: some View {
        let width = size * 0.5, height = size * 0.2
        return Capsule()
            .fill(fur)
            .frame(width: width, height: height)
            .overlay {
                HStack(spacing: width * 0.1) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(mask).frame(width: width * 0.1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, width * 0.08)
            }
            .clipShape(.capsule)
            .rotationEffect(.degrees(-38))
            .offset(x: size * 0.3, y: size * 0.12)
    }

    private var bodyShape: some View {
        ZStack {
            Ellipse()
                .fill(fur)
                .frame(width: size * 0.5, height: size * 0.46)
            Ellipse()
                .fill(muzzle)
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(y: size * 0.03)
            // Pattes avant.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(furShade)
                    .frame(width: size * 0.09, height: size * 0.17)
                    .rotationEffect(.degrees(side * -22))
                    .offset(x: side * size * 0.17, y: -size * 0.02)
            }
        }
        .offset(y: size * 0.2)
    }

    private var head: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle().fill(fur)
                    Circle().fill(mask).scaleEffect(0.5).offset(y: size * 0.01)
                }
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: side * size * 0.2, y: -size * 0.2)
            }
            Ellipse()
                .fill(fur)
                .frame(width: size * 0.6, height: size * 0.46)
            // Masque sombre sur les yeux, avec deux yeux clairs.
            Capsule()
                .fill(mask)
                .frame(width: size * 0.5, height: size * 0.17)
                .offset(y: -size * 0.02)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(muzzle)
                    .frame(width: size * 0.1, height: size * 0.1)
                    .overlay {
                        Circle().fill(mask).frame(width: size * 0.05, height: size * 0.05)
                    }
                    .offset(x: side * size * 0.11, y: -size * 0.02)
            }
            // Museau clair, nez et sourire.
            Ellipse()
                .fill(muzzle)
                .frame(width: size * 0.24, height: size * 0.16)
                .offset(y: size * 0.11)
            Ellipse()
                .fill(mask)
                .frame(width: size * 0.07, height: size * 0.05)
                .offset(y: size * 0.07)
            Image(systemName: "chevron.compact.down")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.09, height: size * 0.04)
                .foregroundStyle(mask)
                .offset(y: size * 0.14)
        }
        .offset(y: -size * 0.17)
    }

    /// La caisse d'un lot, tenue contre le ventre : le portail Vendeurs en un coup d'œil.
    private var crate: some View {
        Image(systemName: "shippingbox.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.2, height: size * 0.2)
            .foregroundStyle(Color.grenier)
            .padding(size * 0.02)
            .background(Color.fond.opacity(0.85), in: .rect(cornerRadius: size * 0.06))
            .offset(y: size * 0.24)
    }
}

#Preview("Clair") {
    HStack(spacing: 24) {
        RacoonetteView(size: 160)
        RacoonetteView(size: 64, isAnimated: false)
        MascotView(size: 160)
    }
    .padding()
    .grenierBackground()
}

#Preview("Sombre") {
    RacoonetteView(size: 160)
        .padding()
        .grenierBackground()
        .preferredColorScheme(.dark)
}
