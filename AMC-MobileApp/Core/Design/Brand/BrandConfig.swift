// BrandConfig.swift
// Marque de l'app lue d'un JSON embarqué (B-032, E19 Personnalisation).
//
// Fichier : `Core/Design/Brand/brand.json` (copié dans le bundle par le dossier synchronisé).
// Fichier absent ou illisible : marque Grenier. Champ absent : valeur Grenier pour ce champ seulement.
//
// Usage dans une vue :
//   @Environment(\.brand) private var brand
//   Text(brand.name) · Image(systemName: brand.logo.symbol) · .foregroundStyle(brand.accent)

import SwiftUI
import UIKit

nonisolated struct BrandConfig: Sendable, Hashable {
    /// Logo : un SF Symbol (toujours là, sert de repli) et un asset optionnel du catalogue.
    nonisolated struct Logo: Sendable, Hashable, Decodable {
        var symbol: String
        var asset: String?

        init(symbol: String, asset: String? = nil) {
            self.symbol = symbol
            self.asset = asset
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try container.decodeIfPresent(String.self, forKey: .symbol)?.nonEmpty ?? BrandConfig.grenier.logo.symbol
            asset = try container.decodeIfPresent(String.self, forKey: .asset)?.nonEmpty
        }

        private enum CodingKeys: String, CodingKey { case symbol, asset }
    }

    /// Couleurs en hexadécimal (« #A84D18 »). Nil : couleurs du catalogue (`AccentColor`).
    nonisolated struct Colors: Sendable, Hashable, Decodable {
        var accentLight: String?
        var accentDark: String?

        init(accentLight: String? = nil, accentDark: String? = nil) {
            self.accentLight = accentLight
            self.accentDark = accentDark
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Un hexadécimal invalide vaut « pas de couleur » : on garde celle du catalogue.
            accentLight = try container.decodeIfPresent(String.self, forKey: .accentLight).flatMap(BrandConfig.validHex)
            accentDark = try container.decodeIfPresent(String.self, forKey: .accentDark).flatMap(BrandConfig.validHex)
        }

        private enum CodingKeys: String, CodingKey { case accentLight, accentDark }
    }

    /// Textes clés de la connexion et de l'accueil.
    nonisolated struct Texts: Sendable, Hashable, Decodable {
        var tagline: String
        var welcome: String

        init(tagline: String, welcome: String) {
            self.tagline = tagline
            self.welcome = welcome
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = BrandConfig.grenier.texts
            tagline = try container.decodeIfPresent(String.self, forKey: .tagline)?.nonEmpty ?? fallback.tagline
            welcome = try container.decodeIfPresent(String.self, forKey: .welcome)?.nonEmpty ?? fallback.welcome
        }

        private enum CodingKeys: String, CodingKey { case tagline, welcome }
    }

    var name: String
    var logo: Logo
    var colors: Colors
    var texts: Texts

    /// Marque par défaut.
    static let grenier = BrandConfig(
        name: "Grenier",
        logo: Logo(symbol: "basket.fill"),
        colors: Colors(),
        texts: Texts(
            tagline: String(localized: "Achète en gros avec les familles de ton quartier, directement aux producteurs."),
            welcome: String(localized: "Bienvenue dans ton Grenier")
        )
    )

    /// Marque embarquée, lue une fois.
    static let current = BrandConfig.load()

    /// Nom de la ressource dans le bundle.
    static let resourceName = "brand"

    /// Lit `brand.json` du bundle ; Grenier si le fichier manque ou est invalide.
    static func load(from bundle: Bundle = .main, resource: String = resourceName) -> BrandConfig {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return .grenier }
        return decode(data)
    }

    /// Décode un JSON de marque ; Grenier si le JSON est invalide.
    static func decode(_ data: Data) -> BrandConfig {
        (try? JSONDecoder().decode(BrandConfig.self, from: data)) ?? .grenier
    }

    /// Accent de la marque, en clair et en sombre ; `Color.grenier` sans couleur dans le JSON.
    var accent: Color {
        guard let light = colors.accentLight.flatMap(Self.uiColor) else { return Color("AccentColor") }
        let dark = colors.accentDark.flatMap(Self.uiColor) ?? light
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: Hexadécimal

    /// « #A84D18 » ou « A84D18 » normalisé en « #A84D18 » ; nil si ce n'est pas 6 chiffres hexadécimaux.
    static func validHex(_ value: String) -> String? {
        let digits = value.trimmingCharacters(in: .whitespaces).uppercased().drop { $0 == "#" }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits
    }

    static func uiColor(hex: String) -> UIColor? {
        guard let normalized = validHex(hex), let value = UInt32(normalized.dropFirst(), radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

nonisolated extension BrandConfig: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BrandConfig.grenier
        name = try container.decodeIfPresent(String.self, forKey: .name)?.nonEmpty ?? fallback.name
        logo = try container.decodeIfPresent(Logo.self, forKey: .logo) ?? fallback.logo
        colors = try container.decodeIfPresent(Colors.self, forKey: .colors) ?? fallback.colors
        texts = try container.decodeIfPresent(Texts.self, forKey: .texts) ?? fallback.texts
    }

    private enum CodingKeys: String, CodingKey { case name, logo, colors, texts }
}

private extension String {
    nonisolated var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension EnvironmentValues {
    /// Marque de l'app (B-032) ; la marque d'un groupe (B-034) pourra la remplacer dans un sous-arbre.
    @Entry var brand: BrandConfig = .current
}
