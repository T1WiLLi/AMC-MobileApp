// PostalCode.swift
// V4 (audit de validation) : un seul validateur de code postal canadien (A1A 1A1), partagé par l'adresse du ménage.

import Foundation

nonisolated enum PostalCode {
    /// Code postal canadien compact en minuscules (« h2r1a1 »), `nil` s'il n'a pas la forme A1A 1A1.
    static func normalized(_ text: String) -> String? {
        let compact = text.lowercased().filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count == 6 else { return nil }
        for (index, character) in compact.enumerated() {
            guard character.isASCII else { return nil }
            let wantsLetter = index.isMultiple(of: 2)
            if wantsLetter ? !character.isLetter : !character.isNumber { return nil }
        }
        return compact
    }

    static func isValid(_ text: String) -> Bool { normalized(text) != nil }
}
