import SwiftUI

/// Carte sélectionnable d'un portail (Familles ou Vendeurs), opaque, bordure Grenier quand elle est choisie.
///
/// - `.regular` : grande carte du choix du portail (icône, titre, phrase, détail).
/// - `.compact` : version courte pour la bascule du Profil.
struct PortalCard: View {
    enum Size: Sendable {
        case regular
        case compact
    }

    let portal: Portal
    let isSelected: Bool
    var size: Size = .regular
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var iconSide: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var compactIconSide: CGFloat = 40

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, maxHeight: size == .compact ? .infinity : nil, alignment: .topLeading)
                .padding(size == .regular ? 16 : 12)
                .background(Color.surface, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(isSelected ? Color.grenier : Color.piste, lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(PortalCardButtonStyle())
        .grenierAnimation(.smooth, value: isSelected)
        .grenierHaptic(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(portal.title)
        .accessibilityValue(portal.tagline)
        .accessibilityHint(isSelected ? String(localized: "Touche deux fois pour retirer ce choix.") : String(localized: "Touche deux fois pour choisir ce portail."))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cornerRadius: CGFloat { size == .regular ? 24 : 18 }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .regular: regularContent
        case .compact: compactContent
        }
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                icon(side: min(iconSide, 88), corner: 14)
                Spacer(minLength: 8)
                checkmark
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(portal.title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.texte)
                Text(portal.tagline)
                    .font(.headline)
                    .foregroundStyle(Color.grenier)
                Text(portal.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// Icône et coche en haut, texte dessous : tient dans une demi-largeur sans couper les mots.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                icon(side: min(compactIconSide, 64), corner: 12)
                Spacer(minLength: 4)
                checkmark
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(portal.title)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                Text(portal.tagline)
                    .font(.caption)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func icon(side: CGFloat, corner: CGFloat) -> some View {
        Image(systemName: portal.systemImage)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? Color.onAccent : Color.grenier)
            .padding(side * 0.24)
            .frame(width: side, height: side)
            .background(isSelected ? Color.grenier : Color.grenier.opacity(0.12), in: .rect(cornerRadius: corner))
            .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
            .accessibilityHidden(true)
    }

    private var checkmark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(size == .regular ? .title2 : .title3)
            .symbolRenderingMode(.palette)
            // Cercle vide en Texte secondaire plein (6,2:1) : à 50 % il tombait à 2,2:1, sous le 3:1 des contrôles.
            .foregroundStyle(
                isSelected ? Color.onAccent : Color.texteSecondaire,
                isSelected ? Color.grenier : Color.texteSecondaire
            )
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// Léger enfoncement au toucher, sans le fond gris des boutons par défaut.
private struct PortalCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}

private struct PortalCardPreview: View {
    @State private var selection: Set<Portal> = [.family]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Portal.allCases) { portal in
                    PortalCard(portal: portal, isSelected: selection.contains(portal)) {
                        if selection.contains(portal) { selection.remove(portal) } else { selection.insert(portal) }
                    }
                }
                HStack(spacing: 12) {
                    ForEach(Portal.allCases) { portal in
                        PortalCard(portal: portal, isSelected: portal == .family, size: .compact) {}
                    }
                }
            }
            .padding()
        }
        .grenierBackground()
    }
}

#Preview("Clair") {
    PortalCardPreview()
}

#Preview("Sombre") {
    PortalCardPreview()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    PortalCardPreview()
        .dynamicTypeSize(.accessibility5)
}
