// GrenierStatTile.swift
// Tuile de chiffre clé partagée par toute l'app (« 27 familles », « 1 240 $ revenus prévus ») :
// symbole teinté, valeur animée, libellés. Remplace les ~10 copies locales (GroupsStatTile, DemandStatTile,
// TrustTile, StatChip, FigureTile, StatTile…) pour que toutes les tuiles de chiffres se ressemblent.
//
// La tuile remplit toujours la hauteur proposée : dans une rangée, poser
// `.fixedSize(horizontal: false, vertical: true)` sur le `HStack` pour que toutes prennent la hauteur de la plus haute.
//
//     GrenierStatTile("27", systemImage: "person.2.fill", tint: .solidarite,
//                     caption: Text("familles"), numericValue: 27)
//
//     GrenierStatTile(Money.formatRounded(cents), systemImage: "dollarsign.circle.fill",
//                     style: .card, icon: .badge, title: Text("Revenus prévus"), numericValue: Double(cents))
//
//     GrenierStatTile(systemImage: "scalemass.fill", style: .card, icon: .badge, caption: …) {
//         AnimatedCounter(value: kilograms, format: .integer(unit: "kg"))   // valeur sur mesure
//     }
//
// Les libellés sont des `Text` : `Text(variable)` est affiché tel quel, `Text("clé")` passe par le catalogue.

import SwiftUI

/// Habillage de la tuile.
enum GrenierStatTileStyle: Sendable {
    /// Fond de la teinte à 10 %, coins de 16, marge de 12 (tuiles dans une carte ou un en-tête).
    case tinted
    /// Carte opaque Grenier (`grenierCard()`), posée directement sur le fond d'écran.
    case card
    /// Pastille compacte : symbole sur la ligne du chiffre, fond teinté, petite marge.
    case compact
}

/// Place du symbole (ignorée en `.compact`, où il est toujours devant le chiffre).
enum GrenierStatTileIconPlacement: Sendable {
    /// Au-dessus de la valeur, sans fond.
    case top
    /// Au-dessus de la valeur, dans une pastille teintée (`grenierIconTile`).
    case badge
    /// Devant le titre, dans un `Label` (le titre est alors requis).
    case title
}

/// Tuile de chiffre clé : symbole, titre, valeur animée, barre de progression, légende et détail, tous optionnels
/// sauf le symbole et la valeur.
struct GrenierStatTile<Value: View>: View {
    typealias Style = GrenierStatTileStyle
    typealias IconPlacement = GrenierStatTileIconPlacement

    private let value: Value
    private let systemImage: String
    private let tint: Color
    private let style: Style
    private let icon: IconPlacement
    private let title: Text?
    private let caption: Text?
    private let detail: Text?
    private let detailSystemImage: String?
    private let numericValue: Double?
    private let valueFont: Font?
    private let progress: Double?
    private let accessibilityLabelOverride: Text?
    /// Texte de la valeur quand elle en est un : déclenche le rebond et la transition de chiffres.
    private let valueText: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var badgeSide: CGFloat = 40

    /// Tuile à valeur sur mesure (ex. `AnimatedCounter`), qui gère elle-même sa transition de chiffres.
    /// `numericValue` fait rebondir le symbole quand elle change.
    init(
        systemImage: String,
        tint: Color = .grenier,
        style: Style = .tinted,
        icon: IconPlacement = .top,
        title: Text? = nil,
        caption: Text? = nil,
        detail: Text? = nil,
        detailSystemImage: String? = nil,
        numericValue: Double? = nil,
        valueFont: Font? = nil,
        progress: Double? = nil,
        accessibilityLabel: Text? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.init(
            value: value(), valueText: nil, systemImage: systemImage, tint: tint, style: style, icon: icon,
            title: title, caption: caption, detail: detail, detailSystemImage: detailSystemImage,
            numericValue: numericValue, valueFont: valueFont, progress: progress, accessibilityLabel: accessibilityLabel
        )
    }

    private init(
        value: Value, valueText: String?, systemImage: String, tint: Color, style: Style, icon: IconPlacement,
        title: Text?, caption: Text?, detail: Text?, detailSystemImage: String?,
        numericValue: Double?, valueFont: Font?, progress: Double?, accessibilityLabel: Text?
    ) {
        self.value = value
        self.valueText = valueText
        self.systemImage = systemImage
        self.tint = tint
        self.style = style
        self.icon = icon
        self.title = title
        self.caption = caption
        self.detail = detail
        self.detailSystemImage = detailSystemImage
        self.numericValue = numericValue
        self.valueFont = valueFont
        self.progress = progress
        self.accessibilityLabelOverride = accessibilityLabel
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(StatTileBackground(style: style, tint: tint))
            .grenierAnimation(.smooth, value: animationKey)
            .modifier(StatTileAccessibility(label: accessibilityLabelOverride))
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if style == .compact {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    symbol
                    valueView
                }
                texts
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                switch icon {
                case .top:
                    symbol.font(.title3)
                case .badge:
                    symbol
                        .font(.title3)
                        .grenierIconTile(tint, side: badgeSide, cornerRadius: 12)
                        .padding(.bottom, 2)
                case .title:
                    EmptyView()
                }
                if let title {
                    if icon == .title {
                        Label { title } icon: { symbol }
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                    } else {
                        title
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                valueView
                if let progress {
                    ProgressView(value: progress)
                        .tint(tint)
                }
                texts
            }
        }
    }

    private var symbol: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: reduceMotion ? nil : animationKey)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var valueView: some View {
        let styled = value
            .priceStyle(valueFont ?? defaultValueFont)
            .foregroundStyle(.texte)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if valueText != nil {
            styled.contentTransition(numericValue.map { .numericText(value: $0) } ?? .numericText())
        } else {
            styled
        }
    }

    @ViewBuilder
    private var texts: some View {
        if let caption {
            caption
                .font(style == .card ? .subheadline : .caption)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let detail {
            Label {
                detail.fixedSize(horizontal: false, vertical: true)
            } icon: {
                if let detailSystemImage {
                    Image(systemName: detailSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                }
            }
            .labelStyle(DetailLabelStyle(hasIcon: detailSystemImage != nil))
            .font(style == .card ? .subheadline : .caption)
            .foregroundStyle(.texteSecondaire)
        }
    }

    private var defaultValueFont: Font {
        switch style {
        case .tinted: .title2.bold()
        case .card: .price
        case .compact: .headline
        }
    }

    /// Ce qui fait rebondir le symbole et anime la tuile : la valeur chiffrée, sinon le texte affiché.
    private var animationKey: String? {
        numericValue.map { "\($0)" } ?? valueText
    }
}

extension GrenierStatTile where Value == Text {
    /// Tuile à valeur texte (« 27 », « 900 m », « 1 240 $ »), affichée telle quelle avec la transition de chiffres.
    /// `numericValue` donne le sens de la transition (le chiffre monte ou descend).
    init(
        _ value: String,
        systemImage: String,
        tint: Color = .grenier,
        style: Style = .tinted,
        icon: IconPlacement = .top,
        title: Text? = nil,
        caption: Text? = nil,
        detail: Text? = nil,
        detailSystemImage: String? = nil,
        numericValue: Double? = nil,
        valueFont: Font? = nil,
        progress: Double? = nil,
        accessibilityLabel: Text? = nil
    ) {
        self.init(
            value: Text(verbatim: value), valueText: value, systemImage: systemImage, tint: tint, style: style, icon: icon,
            title: title, caption: caption, detail: detail, detailSystemImage: detailSystemImage,
            numericValue: numericValue, valueFont: valueFont, progress: progress, accessibilityLabel: accessibilityLabel
        )
    }
}

// MARK: - Habillage

private struct StatTileBackground: ViewModifier {
    let style: GrenierStatTileStyle
    let tint: Color

    func body(content: Content) -> some View {
        switch style {
        case .tinted:
            content
                .padding(12)
                .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
        case .card:
            content.grenierCard()
        case .compact:
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tint.opacity(0.1), in: .rect(cornerRadius: 14))
        }
    }
}

/// Lu d'un bloc par VoiceOver ; un libellé fourni remplace la lecture des textes visibles.
private struct StatTileAccessibility: ViewModifier {
    let label: Text?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Détail sans symbole : le texte seul, sans l'espace réservé à l'icône.
private struct DetailLabelStyle: LabelStyle {
    let hasIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        if hasIcon {
            Label(configuration)
        } else {
            configuration.title
        }
    }
}

// MARK: - Aperçus

#if DEBUG
private struct StatTilePreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    GrenierStatTile("27", systemImage: "person.2.fill", tint: .solidarite,
                                    caption: Text(verbatim: "familles"), numericValue: 27)
                    GrenierStatTile("3", systemImage: GrenierSymbol.offers,
                                    caption: Text(verbatim: "lots ouverts"), numericValue: 3)
                    GrenierStatTile("900 m", systemImage: "circle.dashed", tint: .economie,
                                    caption: Text(verbatim: "de rayon, une légende plus longue"))
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    GrenierStatTile("1 240 $", systemImage: "dollarsign.circle.fill", style: .card, icon: .badge,
                                    title: Text(verbatim: "Revenus prévus"), numericValue: 124_000)
                    GrenierStatTile("18 / 40", systemImage: "square.stack.3d.up.fill", style: .card, icon: .badge,
                                    title: Text(verbatim: "Parts engagées"), numericValue: 18, progress: 0.45)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    GrenierStatTile("42", systemImage: GrenierSymbol.groups, tint: .solidarite, style: .card, icon: .title,
                                    title: Text(verbatim: "Familles servies"), detail: Text(verbatim: "dans 3 quartiers"),
                                    detailSystemImage: GrenierSymbol.map, numericValue: 42)
                    GrenierStatTile("128", systemImage: "shippingbox.fill", style: .card,
                                    caption: Text(verbatim: "lots livrés"), numericValue: 128)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    GrenierStatTile("24", systemImage: "house.fill", tint: .solidarite, style: .compact,
                                    caption: Text(verbatim: "familles"), numericValue: 24)
                    GrenierStatTile("2", systemImage: "cart.fill", style: .compact,
                                    caption: Text(verbatim: "commandes"), numericValue: 2)
                    GrenierStatTile("5", systemImage: "shippingbox.fill", tint: .economie, style: .compact,
                                    caption: Text(verbatim: "nouveaux lots"), numericValue: 5)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .grenierBackground()
    }
}

#Preview("Tuiles de chiffres") {
    StatTilePreviewGallery()
}

#Preview("Tuiles de chiffres sombre") {
    StatTilePreviewGallery()
        .preferredColorScheme(.dark)
}
#endif
