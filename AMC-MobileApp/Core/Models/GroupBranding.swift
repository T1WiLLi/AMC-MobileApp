// GroupBranding.swift
// Marque d'un groupe de quartier (B-033, E19 Personnalisation) : champ `branding` de `groups/{groupId}`.
// Thème seulement (nom affiché, emblème, accent, message d'accueil) ; photo et bannière : T-122.
//
// Décodage tolérant : champ absent, vide ou mal formé = valeur par défaut, jamais d'erreur sur le groupe.
// Usage : `group.resolvedBranding.accent`, `group.resolvedBranding.welcomeMessage` (re-thème : B-034).

import SwiftUI
import UIKit

nonisolated struct GroupBranding: Codable, Sendable, Hashable {
    /// Nom affiché à la place de `NeighborhoodGroup.name` ; nil = nom du groupe.
    var displayName: String?
    /// SF Symbol de l'emblème ; nil = emblème Groupes.
    var emblem: String?
    /// Accent en hexadécimal (« #1E6B52 »), clair puis sombre ; nil = accent Grenier.
    var accentLight: String?
    var accentDark: String?
    /// Message d'accueil ; nil = « Bienvenue chez <nom> ».
    var welcomeMessage: String?

    /// Emblème quand le groupe n'en choisit pas.
    static let defaultEmblem = "person.3.fill"

    init(displayName: String? = nil, emblem: String? = nil, accentLight: String? = nil,
         accentDark: String? = nil, welcomeMessage: String? = nil) {
        self.displayName = displayName
        self.emblem = emblem
        self.accentLight = accentLight.flatMap(BrandConfig.validHex)
        self.accentDark = accentDark.flatMap(BrandConfig.validHex)
        self.welcomeMessage = welcomeMessage
    }

    init(from decoder: any Decoder) throws {
        // `branding` qui n'est pas un objet : marque par défaut plutôt qu'un groupe illisible.
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        func text(_ key: CodingKeys) -> String? {
            guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        self.init(displayName: text(.displayName), emblem: text(.emblem), accentLight: text(.accentLight),
                  accentDark: text(.accentDark), welcomeMessage: text(.welcomeMessage))
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, emblem, accentLight, accentDark, welcomeMessage
    }

    /// Accent du groupe en clair et en sombre ; nil sans accent (garder celui de l'app).
    var accent: Color? {
        guard let light = accentLight.flatMap(BrandConfig.uiColor) else { return nil }
        let dark = accentDark.flatMap(BrandConfig.uiColor) ?? light
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Marque d'un groupe avec les valeurs par défaut remplies.
nonisolated struct ResolvedGroupBranding: Sendable, Hashable {
    var displayName: String
    var emblem: String
    var welcomeMessage: String
    var branding: GroupBranding

    /// Accent du groupe ; nil = accent de l'app.
    var accent: Color? { branding.accent }
    var hasCustomAccent: Bool { branding.accentLight != nil }
}

nonisolated extension NeighborhoodGroup {
    /// Marque du groupe, valeurs par défaut comprises (`branding` absent = marque par défaut).
    var resolvedBranding: ResolvedGroupBranding {
        let branding = branding ?? GroupBranding()
        let name = branding.displayName ?? self.name
        return ResolvedGroupBranding(
            displayName: name,
            emblem: branding.emblem ?? GroupBranding.defaultEmblem,
            welcomeMessage: branding.welcomeMessage ?? "Bienvenue chez \(name)",
            branding: branding
        )
    }
}
