// GroupBrandingEditorViewModel.swift
// B-036 (T-152) : le coordonnateur change la marque de son groupe (nom affiché, emblème, accent, message
// d'accueil). Aperçu en direct avec le vrai `GroupTheme`, validation des champs, puis
// `groups.updateBranding` (firestore.rules : coordinateur seulement, champ `branding` seulement).
//
// Usage :
//   @State private var editor = GroupBrandingEditorViewModel(repositories: context.repositories, group: group, userId: context.userId)
//   if let updated = await editor.save() { detail.replaceGroup(updated) }

import Foundation
import Observation

@Observable
@MainActor
final class GroupBrandingEditorViewModel: Identifiable {
    enum Status: Equatable {
        case idle
        case saving
        case saved
        case failed(AppError)
    }

    /// Accent proposé : clair (porte du blanc) et sombre (porte du #1C1712), tous deux AA.
    struct AccentPreset: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let light: String
        let dark: String
    }

    static let maxDisplayNameLength = 40
    static let maxWelcomeLength = 160

    /// Accents proposés : tous passent le contraste AA de `GroupTheme` (vérifié par les tests).
    static var accentPresets: [AccentPreset] { [
        AccentPreset(id: "foret", name: String(localized: "Forêt"), light: "#1E6B52", dark: "#7FD1AE"),
        AccentPreset(id: "fleuve", name: String(localized: "Fleuve"), light: "#1F5F8B", dark: "#8CC4EE"),
        AccentPreset(id: "brique", name: String(localized: "Brique"), light: "#A3402A", dark: "#F2A08A"),
        AccentPreset(id: "prune", name: String(localized: "Prune"), light: "#6E3A86", dark: "#CDA6E6"),
        AccentPreset(id: "erable", name: String(localized: "Érable"), light: "#9A4A00", dark: "#F5B56B"),
        AccentPreset(id: "nuit", name: String(localized: "Nuit"), light: "#2E3A70", dark: "#A9B6F0"),
    ] }

    /// Emblèmes proposés (SF Symbols).
    static let emblems: [String] = [
        GroupBranding.defaultEmblem, "leaf.fill", "carrot.fill", "basket.fill", "house.fill", "heart.fill",
        "building.2.fill", "tree.fill", "sun.max.fill", "star.fill", "fork.knife", "hands.and.sparkles.fill",
    ]

    // MARK: Brouillon

    var displayName: String
    var welcomeMessage: String
    /// nil = emblème par défaut.
    var emblem: String?
    /// nil = accent de l'app.
    var accentId: String?

    private(set) var status: Status = .idle
    /// Incrémenté à chaque enregistrement réussi (haptique).
    private(set) var savedCount = 0

    private(set) var group: NeighborhoodGroup
    private let repositories: AppRepositories
    private let userId: String

    init(repositories: AppRepositories, group: NeighborhoodGroup, userId: String) {
        self.repositories = repositories
        self.group = group
        self.userId = userId
        let branding = group.branding ?? GroupBranding()
        displayName = branding.displayName ?? ""
        welcomeMessage = branding.welcomeMessage ?? ""
        emblem = branding.emblem
        if let light = branding.accentLight {
            let dark = branding.accentDark ?? light
            if let preset = Self.accentPresets.first(where: { Self.same($0.light, light) && Self.same($0.dark, dark) }) {
                currentAccent = nil
                accentId = preset.id
            } else {
                // Accent posé hors de l'app (seed, autre version) : gardé tel quel comme premier choix.
                currentAccent = AccentPreset(id: Self.currentAccentId, name: String(localized: "Couleur actuelle"),
                                             light: light, dark: dark)
                accentId = Self.currentAccentId
            }
        } else {
            currentAccent = nil
            accentId = nil
        }
    }

    private static let currentAccentId = "actuel"
    /// Accent actuel du groupe s'il ne fait pas partie des accents proposés.
    private let currentAccent: AccentPreset?

    // MARK: Dérivés

    var isCoordinator: Bool { group.coordinatorIds.contains(userId) }

    /// Accents à choisir : l'accent actuel du groupe (s'il est personnalisé), puis les accents proposés.
    var availableAccents: [AccentPreset] { (currentAccent.map { [$0] } ?? []) + Self.accentPresets }

    var accentPreset: AccentPreset? { accentId.flatMap { id in availableAccents.first { $0.id == id } } }

    /// Marque issue du brouillon (champs vides = valeur par défaut).
    var draft: GroupBranding {
        GroupBranding(
            displayName: Self.trimmed(displayName),
            emblem: emblem,
            accentLight: accentPreset?.light,
            accentDark: accentPreset?.dark,
            welcomeMessage: Self.trimmed(welcomeMessage)
        )
    }

    /// Thème de l'aperçu, calculé comme sur la fiche du groupe.
    var previewTheme: GroupTheme {
        var preview = group
        preview.branding = draft
        return GroupTheme(group: preview)
    }

    var displayNameError: String? {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxDisplayNameLength
            ? String(localized: "\(Self.maxDisplayNameLength) caractères au maximum.") : nil
    }

    var welcomeError: String? {
        welcomeMessage.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxWelcomeLength
            ? String(localized: "\(Self.maxWelcomeLength) caractères au maximum.") : nil
    }

    var hasChanges: Bool { draft != (group.branding ?? GroupBranding()) }

    var canSave: Bool {
        isCoordinator && hasChanges && displayNameError == nil && welcomeError == nil && status != .saving
    }

    var isDefault: Bool { draft == GroupBranding() }

    var error: AppError? {
        if case .failed(let error) = status { error } else { nil }
    }

    // MARK: Actions

    /// Revient à la marque LeGrenier (à enregistrer ensuite).
    func resetToDefault() {
        displayName = ""
        welcomeMessage = ""
        emblem = nil
        accentId = nil
    }

    /// Enregistre la marque ; renvoie le groupe à jour (nil en cas d'échec ou si rien n'a changé).
    @discardableResult
    func save() async -> NeighborhoodGroup? {
        guard canSave else { return nil }
        status = .saving
        do {
            try await repositories.groups.updateBranding(draft, ofGroup: group.id, byUserId: userId)
            let updated = try await repositories.groups.group(id: group.id)
            group = updated
            status = .saved
            savedCount += 1
            return updated
        } catch {
            status = .failed(AppError(error))
            return nil
        }
    }

    func clearError() {
        if case .failed = status { status = .idle }
    }

    private static func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    private static func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
