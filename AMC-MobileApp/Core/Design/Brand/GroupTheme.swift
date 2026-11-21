// GroupTheme.swift
// Re-thème à l'entrée d'un groupe (B-034, E19 Personnalisation) : accent et emblème de sa marque (B-033).
//
// L'accent du groupe n'est gardé que s'il passe le contraste AA (4,5:1) avec le texte posé dessus
// (blanc en clair, #1C1712 en sombre, comme `Color.onAccent`) ; sinon accent Grenier.
// La fiche du groupe pose `.environment(\.groupTheme, GroupTheme(group:))` ; en sortant de la fiche,
// l'environnement parent (Grenier) revient tout seul.
//
// Usage dans une vue :
//   @Environment(\.groupTheme) private var theme
//   .foregroundStyle(theme.accent) · Image(systemName: theme.emblem)

import SwiftUI
import UIKit

nonisolated struct GroupTheme: Sendable, Equatable {
    /// Accent à utiliser à la place de `Color.grenier`.
    var accent: Color
    /// Emblème du groupe (SF Symbol).
    var emblem: String
    /// Nom affiché et message d'accueil ; nil hors d'un groupe.
    var displayName: String?
    var welcomeMessage: String?
    /// Vrai si l'accent vient de la marque du groupe (et a passé le contraste AA).
    var usesGroupAccent: Bool

    /// Thème de l'app, hors d'un groupe.
    static let grenier = GroupTheme(
        accent: AppTheme.accent, emblem: GroupBranding.defaultEmblem,
        displayName: nil, welcomeMessage: nil, usesGroupAccent: false
    )

    /// Texte posé sur l'accent : blanc en clair, #1C1712 en sombre (`Color.onAccent`).
    static let textOnAccentLight = UIColor.white
    static let textOnAccentDark = UIColor(red: 0x1C / 255, green: 0x17 / 255, blue: 0x12 / 255, alpha: 1)
    /// Seuil AA pour le texte normal.
    static let minimumContrast = 4.5

    init(accent: Color, emblem: String, displayName: String?, welcomeMessage: String?, usesGroupAccent: Bool) {
        self.accent = accent
        self.emblem = emblem
        self.displayName = displayName
        self.welcomeMessage = welcomeMessage
        self.usesGroupAccent = usesGroupAccent
    }

    init(group: NeighborhoodGroup) {
        let resolved = group.resolvedBranding
        let light = resolved.branding.accentLight.flatMap(BrandConfig.uiColor)
        let dark = resolved.branding.accentDark.flatMap(BrandConfig.uiColor) ?? light
        let accent: Color?
        if let light, let dark, Self.meetsAA(light: light, dark: dark) {
            accent = Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        } else {
            accent = nil
        }
        self.init(
            accent: accent ?? Self.grenier.accent,
            emblem: resolved.emblem,
            displayName: resolved.displayName,
            welcomeMessage: resolved.welcomeMessage,
            usesGroupAccent: accent != nil
        )
    }

    // MARK: Contraste (WCAG 2.1)

    /// Vrai si l'accent clair porte du blanc et l'accent sombre du #1C1712 à 4,5:1 au moins.
    static func meetsAA(light: UIColor, dark: UIColor) -> Bool {
        contrastRatio(light, textOnAccentLight) >= minimumContrast
            && contrastRatio(dark, textOnAccentDark) >= minimumContrast
    }

    /// Rapport de contraste WCAG entre deux couleurs opaques, de 1 à 21.
    static func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let (a, b) = (relativeLuminance(first), relativeLuminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

extension EnvironmentValues {
    /// Thème du groupe affiché (B-034) ; Grenier hors d'un groupe.
    @Entry var groupTheme: GroupTheme = .grenier
}
