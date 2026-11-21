import Foundation

/// Validation en direct du formulaire courriel (format, longueur, force du mot de passe).
nonisolated enum EmailAuthValidation {
    /// Minimum imposé par Firebase Auth.
    static let minimumPasswordLength = 6

    /// Format raisonnable : quelque chose@domaine.ext, sans espace.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/) != nil
    }

    /// Message sous le champ courriel, ou nil s'il est vide ou valide.
    static func emailIssue(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isValidEmail(trimmed) else { return nil }
        return trimmed.contains("@")
            ? "Il manque le domaine, par exemple @gmail.com."
            : "Il manque le « @ » dans ton courriel."
    }

    /// Message sous le champ mot de passe, ou nil s'il est vide ou assez long.
    static func passwordIssue(_ password: String) -> String? {
        guard !password.isEmpty, password.count < minimumPasswordLength else { return nil }
        let missing = minimumPasswordLength - password.count
        return missing == 1
            ? "Encore 1 caractère (6 minimum)."
            : "Encore \(missing) caractères (6 minimum)."
    }
}

/// Force du mot de passe, affichée en barre sous le champ à la création du compte.
enum PasswordStrength: Int, Comparable, Sendable {
    case tooShort, weak, fair, strong

    init(_ password: String) {
        guard password.count >= EmailAuthValidation.minimumPasswordLength else {
            self = .tooShort
            return
        }
        var score = 0
        if password.count >= 10 { score += 1 }
        if password.contains(where: \.isNumber) { score += 1 }
        if password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }
        switch score {
        case 0...1: self = .weak
        case 2: self = .fair
        default: self = .strong
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .tooShort: "Trop court"
        case .weak: "Faible"
        case .fair: "Correct"
        case .strong: "Solide"
        }
    }

    /// Remplissage de la barre (0…1).
    var progress: Double { Double(rawValue + 1) / 4 }
}
