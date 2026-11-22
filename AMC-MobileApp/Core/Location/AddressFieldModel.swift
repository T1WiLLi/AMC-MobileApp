// AddressFieldModel.swift
// T-185 : état d'un champ d'adresse validé par Apple (`AddressField`), indépendant de la vue pour être testé.
//
// Le texte reste chez l'écran (son view-model) ; ce modèle garde ce qui a été vérifié :
// - une adresse déjà enregistrée et pas modifiée compte comme bonne (`accept(saved:)`), pour ne pas bloquer
//   les anciennes données ;
// - sinon, le texte doit avoir été validé (`validate(_:)`), et l'écran réécrit l'adresse normalisée renvoyée.
//
// Usage dans un view-model :
//   let addressCheck = AddressFieldModel(validator: validator)
//   addressCheck.accept(saved: point.address)                // au chargement
//   guard let text = await addressCheck.ensureValid(address) else { return }   // à l'enregistrement

import Foundation
import Observation

@Observable
@MainActor
final class AddressFieldModel {
    /// Ce qu'on écrit dans le champ une fois l'adresse validée.
    enum Style: Sendable {
        /// Adresse complète (« 8150 Boulevard Pie-IX, Montréal QC H1Z 3T6 »), appartement tapé conservé.
        case full
        /// Numéro et rue seulement (« 8150 Boulevard Pie-IX »), quand le code postal a son propre champ.
        case streetLine
    }

    enum Status: Equatable, Sendable {
        /// Champ vide.
        case empty
        /// Adresse déjà enregistrée, pas modifiée : acceptée sans nouvelle vérification.
        case saved
        /// Modifiée, pas encore vérifiée.
        case edited
        case validating
        case valid
        case notFound
    }

    let style: Style
    /// Suggestions d'Apple pour le texte en cours.
    private(set) var suggestions: [AddressSuggestion] = []
    /// Dernière adresse validée (position comprise), pour le texte `validatedText`.
    private(set) var validated: ValidatedAddress?
    private(set) var validatedText: String?
    private(set) var notFoundText: String?
    private(set) var validatingText: String?
    private var savedText: String?

    private let validator: any AddressValidating
    /// Ajouté à la requête (ex. code postal saisi à part), pour aider Apple.
    var context: String?

    init(validator: any AddressValidating, style: Style = .full) {
        self.validator = validator
        self.style = style
    }

    // MARK: État

    /// Adresse déjà enregistrée : acceptée telle quelle tant qu'on n'y touche pas.
    func accept(saved text: String) {
        let trimmed = Self.trim(text)
        savedText = trimmed.isEmpty ? nil : trimmed
    }

    func status(for text: String) -> Status {
        let trimmed = Self.trim(text)
        if trimmed.isEmpty { return .empty }
        if validatingText == trimmed { return .validating }
        if validatedText == trimmed { return .valid }
        if notFoundText == trimmed { return .notFound }
        if savedText == trimmed { return .saved }
        return .edited
    }

    /// Le texte peut-il être enregistré tel quel ? (vide compte si le champ est facultatif)
    func isAccepted(_ text: String, optional: Bool = false) -> Bool {
        switch status(for: text) {
        case .saved, .valid: true
        case .empty: optional
        case .edited, .validating, .notFound: false
        }
    }

    /// Bloque l'enregistrement : vérification en cours, ou adresse introuvable.
    func blocksSaving(_ text: String) -> Bool {
        let status = status(for: text)
        return status == .validating || status == .notFound
    }

    /// Adresse validée pour ce texte (nil si non validée, ou acceptée seulement parce qu'elle était enregistrée).
    func validatedAddress(for text: String) -> ValidatedAddress? {
        status(for: text) == .valid ? validated : nil
    }

    // MARK: Suggestions

    /// Suggestions pour le texte tapé. À appeler après un court délai (l'`AddressField` attend 300 ms).
    func refreshSuggestions(for text: String) async {
        let trimmed = Self.trim(text)
        guard status(for: trimmed) == .edited || status(for: trimmed) == .notFound, trimmed.count >= 3 else {
            suggestions = []
            return
        }
        let found = await validator.suggestions(for: trimmed)
        guard !Task.isCancelled else { return }
        suggestions = found
    }

    func clearSuggestions() { suggestions = [] }

    // MARK: Validation

    /// Vérifie le texte auprès d'Apple. Renvoie le texte normalisé à réécrire dans le champ, nil si introuvable.
    @discardableResult
    func validate(_ text: String) async -> String? {
        let trimmed = Self.trim(text)
        guard !trimmed.isEmpty else { return nil }
        suggestions = []
        validatingText = trimmed
        let query = [trimmed, context.map(Self.trim)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let result = await validator.validate(query)
        // Une autre vérification a commencé entre-temps : la plus récente gagne.
        guard validatingText == trimmed else { return result.map { display($0, typed: trimmed) } }
        validatingText = nil
        guard let result else {
            notFoundText = trimmed
            return nil
        }
        let normalized = display(result, typed: trimmed)
        validated = result
        validatedText = normalized
        notFoundText = nil
        return normalized
    }

    /// Choisit une suggestion : la valide et renvoie le texte normalisé.
    func pick(_ suggestion: AddressSuggestion) async -> String? {
        await validate(suggestion.id)
    }

    /// À l'enregistrement : texte à enregistrer s'il est bon (validé maintenant au besoin), nil sinon.
    func ensureValid(_ text: String, optional: Bool = false) async -> String? {
        if isAccepted(text, optional: optional) { return Self.trim(text) }
        guard status(for: text) != .notFound, status(for: text) != .empty else { return nil }
        return await validate(text)
    }

    private func display(_ address: ValidatedAddress, typed: String) -> String {
        switch style {
        case .streetLine:
            return address.streetLine
        case .full:
            guard let unit = AddressMatching.unitSuffix(in: typed) else { return address.formatted }
            return "\(address.formatted), \(unit)"
        }
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
