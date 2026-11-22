// AppTheme.swift
// Thèmes interchangeables (B-035, E19 Personnalisation) : accent, fond et coins des cartes,
// branchés sur les tokens du design system. Choisis dans le Profil, persistés (`@AppStorage`).
//
// Le thème est un trait UIKit relié à l'environnement SwiftUI : `Color.grenier`, `AppTheme.fond`
// et la teinte de l'app se résolvent selon le thème courant, comme pour clair/sombre, sans recréer
// les écrans. La racine pose `.environment(\.appTheme, theme)`.
//
// Usage : `Color.grenier` (déjà thémé) · `.grenierBackground()` · `.grenierCard()` · `@Environment(\.appTheme)`

import SwiftUI
import UIKit

nonisolated enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// Orange Grenier, la marque par défaut.
    case grenier
    /// Bleu du fleuve Saint-Laurent.
    case fleuve
    /// Vert des sentiers du mont Royal.
    case montRoyal

    static let storageKey = "grenier.appTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grenier: String(localized: "LeGrenier")
        case .fleuve: String(localized: "Fleuve")
        case .montRoyal: String(localized: "Mont-Royal")
        }
    }

    var subtitle: String {
        switch self {
        case .grenier: String(localized: "Orange chaleureux du marché")
        case .fleuve: String(localized: "Bleu du Saint-Laurent, coins plus nets")
        case .montRoyal: String(localized: "Vert des sentiers, coins plus ronds")
        }
    }

    var symbol: String {
        switch self {
        case .grenier: "basket.fill"
        case .fleuve: "water.waves"
        case .montRoyal: "mountain.2.fill"
        }
    }

    /// Rayon des cartes (`grenierCard`).
    var cornerRadius: CGFloat {
        switch self {
        case .grenier: 24
        case .fleuve: 16
        case .montRoyal: 30
        }
    }

    // MARK: Couleurs

    /// Accent en clair et en sombre. Grenier garde l'asset `AccentColor` (#A84D18 / #F08A4B).
    var accentLight: UIColor {
        switch self {
        case .grenier: Self.hex(0xA84D18)
        case .fleuve: Self.hex(0x1D5E8C)
        case .montRoyal: Self.hex(0x2E6B3B)
        }
    }

    var accentDark: UIColor {
        switch self {
        case .grenier: Self.hex(0xF08A4B)
        case .fleuve: Self.hex(0x6DB6E8)
        case .montRoyal: Self.hex(0x7CC68C)
        }
    }

    /// Fond d'écran : celui de Grenier (#FBF7F0 / #14110E), teinté vers l'accent pour les autres.
    var fondLight: UIColor {
        switch self {
        case .grenier: Self.hex(0xFBF7F0)
        case .fleuve: Self.hex(0xF2F6F9)
        case .montRoyal: Self.hex(0xF3F6EF)
        }
    }

    var fondDark: UIColor {
        switch self {
        case .grenier: Self.hex(0x14110E)
        case .fleuve: Self.hex(0x0E1418)
        case .montRoyal: Self.hex(0x10150F)
        }
    }

    func accent(for style: UIUserInterfaceStyle) -> UIColor { style == .dark ? accentDark : accentLight }
    func fond(for style: UIUserInterfaceStyle) -> UIColor { style == .dark ? fondDark : fondLight }

    /// Accent fixe de ce thème (aperçus du sélecteur).
    var accentColor: Color { Color(UIColor { self.accent(for: $0.userInterfaceStyle) }) }
    var fondColor: Color { Color(UIColor { self.fond(for: $0.userInterfaceStyle) }) }

    /// Accent du thème courant, résolu au rendu (trait `AppThemeTrait`, sinon le choix enregistré).
    static let accent = Color(UIColor { traits in
        resolved(in: traits).accent(for: traits.userInterfaceStyle)
    })

    /// Fond du thème courant, résolu au rendu.
    static let fond = Color(UIColor { traits in
        resolved(in: traits).fond(for: traits.userInterfaceStyle)
    })

    /// Thème enregistré (`@AppStorage(AppTheme.storageKey)`), Grenier par défaut.
    static var stored: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init(rawValue:)) ?? .grenier
    }

    /// Le trait posé par l'environnement ; une feuille présentée ne le reçoit pas (trait par défaut),
    /// d'où le repli sur le choix enregistré.
    static func resolved(in traits: UITraitCollection) -> AppTheme {
        let fromTrait = traits[AppThemeTrait.self]
        return fromTrait == AppThemeTrait.defaultValue ? stored : fromTrait
    }

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Trait UIKit relié à SwiftUI

nonisolated struct AppThemeTrait: UITraitDefinition {
    static let defaultValue = AppTheme.grenier
    static let affectsColorAppearance = true
    static let identifier = "com.grenier.appTheme"
    static let name = "AppTheme"
}

nonisolated struct AppThemeKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = AppTheme.grenier

    static func read(from traitCollection: UITraitCollection) -> AppTheme {
        traitCollection[AppThemeTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: AppTheme) {
        mutableTraits[AppThemeTrait.self] = value
    }
}

extension EnvironmentValues {
    /// Thème choisi dans le Profil (B-035). Posé à la racine de l'app.
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Carte thémée

private struct GrenierCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surface, in: .rect(cornerRadius: theme.cornerRadius))
    }
}

extension View {
    /// Carte opaque Grenier : fond Surface, coins du thème (24 par défaut).
    func grenierCard(padding: CGFloat = 16) -> some View {
        modifier(GrenierCardModifier(padding: padding))
    }
}

// MARK: - Application du thème

private struct AppThemedModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .grenier
    /// T-171 : une feuille ouverte pendant le changement de langue perd son parent (la racine est recréée) :
    /// elle garde donc l'ancienne `\.locale`. On la repose ici, à la racine de la feuille comme de l'app.
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, theme)
            .environment(\.locale, language.locale)
            .tint(Color.grenier)
    }
}

extension View {
    /// Pose le thème choisi (B-035) et la teinte qui en découle. À la racine de l'app, et à la racine
    /// d'une feuille qui doit se re-teindre en direct (une feuille ouverte ne suit pas le trait de la fenêtre).
    func appThemed() -> some View {
        modifier(AppThemedModifier())
    }
}
