// GrenierIconTile.swift
// Pastille d'icône : un symbole hiérarchique teinté sur un fond de la même teinte (12 % par défaut),
// carré aux coins arrondis ou rond. Remplace les ~35 copies de `.frame(…).background(tint.opacity(…), in: …)`.
//
// Deux formes d'usage, au rendu identique :
//   GrenierIconTile(systemImage: "house.fill", tint: .grenier, side: 52, font: .title2, cornerRadius: 14)
//   Image(systemName: …).font(…).symbolRenderingMode(.hierarchical).foregroundStyle(tint)
//       .symbolEffect(…)                       // les effets propres au site restent à leur place
//       .grenierIconTile(tint, side: 52, cornerRadius: 14)

import SwiftUI

/// Forme de la pastille.
enum GrenierIconTileShape: Equatable {
    /// Carré aux coins arrondis.
    case rounded(CGFloat)
    /// Rond.
    case circle
}

extension View {
    /// Cadre carré `side` et fond teinté (`tint` à `opacity`) : la pastille d'une icône.
    /// Équivaut à `.frame(width: side, height: side).background(tint.opacity(opacity), in: forme)`.
    @ViewBuilder
    func grenierIconTile(_ tint: Color, side: CGFloat, shape: GrenierIconTileShape, opacity: Double = 0.12) -> some View {
        switch shape {
        case .rounded(let radius):
            frame(width: side, height: side)
                .background(tint.opacity(opacity), in: .rect(cornerRadius: radius))
        case .circle:
            frame(width: side, height: side)
                .background(tint.opacity(opacity), in: .circle)
        }
    }

    /// Pastille carrée aux coins arrondis.
    func grenierIconTile(_ tint: Color, side: CGFloat, cornerRadius: CGFloat, opacity: Double = 0.12) -> some View {
        grenierIconTile(tint, side: side, shape: .rounded(cornerRadius), opacity: opacity)
    }

    /// Pastille ronde.
    func grenierIconCircle(_ tint: Color, side: CGFloat, opacity: Double = 0.12) -> some View {
        grenierIconTile(tint, side: side, shape: .circle, opacity: opacity)
    }
}

/// Symbole SF hiérarchique teinté dans sa pastille. Décoratif : à cacher à VoiceOver côté appelant
/// (`.accessibilityHidden(true)`) si la ligne porte déjà le texte.
struct GrenierIconTile: View {
    let systemImage: String
    var tint: Color = .grenier
    let side: CGFloat
    var shape: GrenierIconTileShape = .rounded(14)
    /// `nil` : la police de l'environnement, comme une `Image` sans `.font`.
    var font: Font?
    var opacity: Double = 0.12

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .grenierIconTile(tint, side: side, shape: shape, opacity: opacity)
    }
}

#Preview("Pastilles") {
    HStack(spacing: 16) {
        GrenierIconTile(systemImage: "house.fill", side: 52, font: .title2)
        GrenierIconTile(systemImage: "heart.fill", tint: .solidarite, side: 44, shape: .circle, font: .title3)
        GrenierIconTile(systemImage: "leaf.fill", tint: .economie, side: 36, shape: .rounded(10), font: .title3)
    }
    .padding()
    .grenierBackground()
}

#Preview("Pastilles sombre") {
    HStack(spacing: 16) {
        GrenierIconTile(systemImage: "house.fill", side: 52, font: .title2)
        GrenierIconTile(systemImage: "heart.fill", tint: .solidarite, side: 44, shape: .circle, font: .title3)
    }
    .padding()
    .grenierBackground()
    .preferredColorScheme(.dark)
}
