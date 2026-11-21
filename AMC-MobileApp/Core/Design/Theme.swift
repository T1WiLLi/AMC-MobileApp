import SwiftUI

// Design system Grenier (maquettes de claude-samuel, docs/maquettes/00-design-system.png).
//
// Couleurs : asset catalog, en clair et en sombre. Xcode génère les symboles
// `Color.fond`, `.surface`, `.texte`, `.texteSecondaire`, `.economie`, `.solidarite`, `.piste`,
// et `Color.accentColor` / `.tint` pour Grenier (AccentColor).
//
// Règles d'usage :
// - Grenier (accent) = actions et paliers. Economie = argent économisé, jamais une action.
//   Solidarite = panier suspendu et aide anonyme.
// - Texte blanc sur Grenier, Economie et Solidarite en clair ; en sombre, texte `.onAccent` sur ces couleurs.
// - Verre seulement sur la couche de contrôle ; cartes et listes opaques (`.surface`).
// - Une seule action `.glassProminent` par écran, le reste en `.glass`.

extension Color {
    /// Grenier (accent) : actions, paliers, onglet actif. Explicite pour ne pas dépendre du `.tint` de l'environnement.
    static let grenier = Color("AccentColor")

    /// Texte posé sur une couleur pleine (Grenier, Economie, Solidarite) : blanc en clair, #1C1712 en sombre.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255, green: 0x17 / 255, blue: 0x12 / 255, alpha: 1)
            : .white
    })
}

extension Font {
    /// Montants et prix : `.title` gras arrondi (« 2,60 $/kg »).
    static let price = Font.title.bold()
    /// Prix compact dans une carte.
    static let priceCompact = Font.title3.bold()
}

extension View {
    /// Style des montants : police arrondie, chiffres à largeur fixe pour les animations.
    func priceStyle(_ font: Font = .price) -> some View {
        self.font(font)
            .fontDesign(.rounded)
            .monospacedDigit()
    }

    /// Fond d'écran Grenier sous une liste ou un scroll.
    func grenierBackground() -> some View {
        background(Color.fond.ignoresSafeArea())
    }

    /// Carte opaque Grenier : fond Surface, coins 24 concentriques.
    func grenierCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.surface, in: .rect(cornerRadius: 24))
    }
}

/// Symboles SF retenus par le design system (rendu hiérarchique).
enum GrenierSymbol {
    static let home = "house.fill"
    static let groups = "person.3.fill"
    static let offers = "shippingbox.fill"
    static let qrCode = "qrcode"
    static let map = "map.fill"
    static let savings = "chart.line.downtrend.xyaxis"
    static let solidarity = "heart.fill"
    static let impact = "leaf.fill"
}

#Preview("Palette") {
    let swatches: [(String, Color)] = [
        ("Fond", .fond), ("Surface", .surface), ("Texte", .texte), ("Texte secondaire", .texteSecondaire),
        ("Grenier", .accentColor), ("Économie", .economie), ("Solidarité", .solidarite), ("Piste", .piste)
    ]
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bonjour Amina").font(.largeTitle.bold())
            Text("Riz basmati, 200 kg").font(.title2.bold())
            Text("Ferme Lafleur · Mirabel").font(.subheadline).foregroundStyle(.texteSecondaire)
            Text("2,60 $/kg").priceStyle()
            ForEach(swatches, id: \.0) { name, color in
                HStack {
                    RoundedRectangle(cornerRadius: 12).fill(color).frame(width: 56, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.texteSecondaire.opacity(0.3)))
                    Text(name).foregroundStyle(.texte)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .grenierBackground()
}

#Preview("Palette sombre") {
    Text("2,60 $/kg").priceStyle()
        .padding()
        .grenierCard()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}
