// ReferralCode.swift
// Codes de référence des organismes (E10 : RQ-082).
// Un organisme partenaire remet un code à un ménage ; le code donne le statut subventionné
// sans jamais dire au groupe qui est aidé (le statut vit dans `households/{id}/private`).

import Foundation

/// Code d'organisme au format `ORG-XX-NNNNC` : `XX` = préfixe de l'organisme (2 lettres),
/// `NNNN` = numéro de série, `C` = caractère de contrôle (0 à 9 ou X, modulo 11 pondéré).
nonisolated struct ReferralCode: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// Préfixe de l'organisme, 2 lettres majuscules (« CB » pour un centre de bénévolat, par exemple).
    let organisation: String
    /// Numéro de série, de 0 à 9 999.
    let serial: Int

    static let maxSerial = 9_999

    /// Crée un code à remettre à un ménage. Lève `.invalidInput` si le préfixe ou le numéro est invalide.
    init(organisation: String, serial: Int) throws {
        let prefix = organisation.uppercased()
        guard prefix.count == 2, prefix.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw AppError.invalidInput(String(localized: "Le préfixe d'organisme doit compter 2 lettres."))
        }
        guard (0...Self.maxSerial).contains(serial) else {
            throw AppError.invalidInput(String(localized: "Le numéro de série doit être entre 0 et \(Self.maxSerial)."))
        }
        self.organisation = prefix
        self.serial = serial
    }

    /// Lit un code saisi par un ménage : espaces et minuscules tolérés, contrôle vérifié.
    /// Lève `.invalidInput` avec un message clair si le code est mal formé ou contient une faute de frappe.
    init(validating text: String) throws {
        let cleaned = text.uppercased().filter { !$0.isWhitespace }
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        let digits = parts.count == 3 ? parts[2].prefix(4) : ""
        guard parts.count == 3, parts[0] == "ORG", parts[2].count == 5,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }), let serial = Int(digits) else {
            throw AppError.invalidInput(String(localized: "Ce code n'a pas le bon format. Le format attendu est ORG-XX-00000."))
        }
        let code = try ReferralCode(organisation: parts[1], serial: serial)
        guard String(parts[2].suffix(1)) == code.checkCharacter else {
            throw AppError.invalidInput(String(localized: "Ce code contient une faute de frappe. Vérifie-le avec ton organisme."))
        }
        self = code
    }

    /// Vrai si le texte est un code bien formé avec un contrôle valide.
    static func isValid(_ text: String) -> Bool {
        (try? ReferralCode(validating: text)) != nil
    }

    /// « ORG-CB-00427 » : la forme normalisée, celle qu'on enregistre.
    var description: String {
        "ORG-\(organisation)-\(String(format: "%04d", serial))\(checkCharacter)"
    }

    /// Modulo 11 pondéré (comme l'ISBN-10) sur les 6 caractères utiles : attrape une faute de frappe
    /// sur un chiffre et l'inversion de deux caractères voisins. Ce n'est pas de la sécurité.
    var checkCharacter: String {
        let body = organisation + String(format: "%04d", serial)
        let sum = body.enumerated().reduce(0) { sum, item in
            sum + (item.offset + 1) * Self.value(of: item.element)
        }
        let check = sum % 11
        return check == 10 ? "X" : String(check)
    }

    /// Chiffres 0 à 9, lettres A = 10 à Z = 35.
    private static func value(of character: Character) -> Int {
        if let digit = character.wholeNumberValue { return digit }
        return Int(character.asciiValue ?? 65) - 55
    }
}

nonisolated extension ReferralCode {
    /// RQ-082 : profil privé d'un ménage qui utilise un code. Seuls le ménage et son organisme le lisent ;
    /// rien n'en sort vers le groupe.
    /// - Parameter issuedCodes: codes remis par les organismes (forme normalisée). Vide = tout code valide est accepté.
    static func subsidizedProfile(redeeming text: String, issuedCodes: Set<String> = []) throws -> HouseholdPrivate {
        let code = try ReferralCode(validating: text)
        guard issuedCodes.isEmpty || issuedCodes.contains(code.description) else {
            throw AppError.invalidInput(String(localized: "Ce code n'est pas reconnu. Vérifie-le avec ton organisme."))
        }
        return HouseholdPrivate(isSubsidized: true, referralCode: code.description)
    }

    /// Ménages admissibles à la solidarité, à passer à `SolidarityLedger.apply`. Un statut sans code valide ne compte pas.
    static func eligibleHouseholdIds(_ profiles: [String: HouseholdPrivate]) -> Set<String> {
        Set(profiles.compactMap { id, profile in
            guard profile.isSubsidized, let code = profile.referralCode, isValid(code) else { return nil }
            return id
        })
    }
}
