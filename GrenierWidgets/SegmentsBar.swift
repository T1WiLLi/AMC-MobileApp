// SegmentsBar.swift
// Barre de palier compacte (3 segments arrondis) pour la Live Activity et le widget.
// Même dessin que TierProgressBar de l'app : segments en Grenier sur la piste, écart 4.

import SwiftUI

struct SegmentsBar: View {
    let fills: [Double]
    var labels: [String] = []
    var highlighted: Int?
    var height: CGFloat = 8
    /// Couleur de la piste (en Dynamic Island, sur fond noir, on passe une piste plus claire).
    var track: Color = GrenierPalette.piste
    var tint: Color = GrenierPalette.accent
    var labelColor: Color = GrenierPalette.texteSecondaire
    var highlightColor: Color = GrenierPalette.texte

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(fills.indices, id: \.self) { index in
                    Capsule()
                        .fill(track)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(tint)
                                    .frame(width: proxy.size.width * fills[index])
                            }
                        }
                        .clipShape(.capsule)
                }
            }
            .frame(height: height)

            if !labels.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(labels.indices, id: \.self) { index in
                        Text(labels[index])
                            .font(.caption2)
                            .fontWeight(index == highlighted ? .bold : .regular)
                            .foregroundStyle(index == highlighted ? highlightColor : labelColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
