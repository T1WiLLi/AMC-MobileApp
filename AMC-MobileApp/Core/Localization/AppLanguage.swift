import Foundation
import Synchronization

/// T-171 (FB-09) : langue de l'interface choisie dans Profil › Préférences.
///
/// - `.system` (par défaut) : la langue de l'appareil (ou celle des Réglages iOS de l'app), sinon le français.
/// - `.french` / `.english` : forcée pour toute l'app, **sans relancer** :
///   - les `Text("…")` suivent `\.locale`, posé à la racine (`AMCMobileApp`) ;
///   - les `String(localized:)` du module passent par la surcharge plus bas, qui résout dans la langue choisie ;
///   - la racine est recréée (`.id`) pour que les textes déjà calculés (ViewModels) le soient de nouveau.
/// - Le choix est aussi écrit dans `AppleLanguages` : au prochain lancement, iOS lui-même (boutons système
///   comme « Continuer avec Apple », alertes, formats de date) démarre dans cette langue.
/// - Et dans l'App Group (`SharedLanguage`) : le widget et la Live Activity suivent la même langue
///   (`ExtensionLanguageSync` les redessine au changement).
nonisolated enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case french = "fr"
    case english = "en"

    /// Clé `UserDefaults` / `@AppStorage`.
    static let storageKey = "grenier.appLanguage"

    /// Langues que l'app sait afficher ; la première sert de repli.
    static let supportedCodes = ["fr", "en"]

    /// Langue forcée pour les recherches de `String(localized:)` ; `nil` = celle du bundle (appareil).
    private static let lookupLocale = Mutex<Locale?>(nil)

    /// Choix enregistré (lu dans `UserDefaults`).
    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Code de langue effectivement affiché : « fr » ou « en ».
    var resolvedCode: String {
        switch self {
        case .french, .english:
            return rawValue
        case .system:
            let preferred = Bundle.preferredLocalizations(
                from: Self.supportedCodes,
                forPreferences: Locale.preferredLanguages
            ).first
            return preferred.flatMap { Self.supportedCodes.contains($0) ? $0 : nil } ?? "fr"
        }
    }

    /// Locale de l'interface : langue choisie, région Canada (formats « 12,50 $ » ou « $12.50 »).
    var locale: Locale {
        Locale(identifier: resolvedCode + "_CA")
    }

    /// Locale de formatage (montants, dates, nombres) de la langue en cours.
    static var formattingLocale: Locale {
        lookupLocale.withLock { $0 } ?? AppLanguage.system.locale
    }

    /// Séparateur décimal de la langue en cours : « , » en français, « . » en anglais.
    static var decimalSeparator: String { formattingLocale.decimalSeparator ?? "," }

    /// Vrai quand la langue en cours est l'anglais.
    static var isEnglish: Bool {
        formattingLocale.language.languageCode?.identifier == "en"
    }

    /// Heure « à la québécoise » en français (« 17 h », « 17 h 30 »), « 5 PM » / « 5:30 PM » en anglais.
    static func clockText(hour: Int, minute: Int) -> String {
        guard isEnglish else {
            return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
        }
        let suffix = hour % 24 < 12 ? "AM" : "PM"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(twelve) \(suffix)" : String(format: "%d:%02d %@", twelve, minute, suffix)
    }

    /// Au lancement : si la langue de l'app a été changée dans les Réglages iOS depuis le dernier choix
    /// fait dans l'app, les Réglages gagnent. Applique ensuite la langue retenue.
    @discardableResult
    static func bootstrap() -> AppLanguage {
        var language = stored
        if language != .system,
           let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:)),
           let first = (domain["AppleLanguages"] as? [String])?.first {
            let code = String(first.prefix(2))
            if code != language.rawValue {
                guard let fromSettings = AppLanguage(rawValue: code) else {
                    // Langue non traduite choisie dans les Réglages : on la laisse à iOS (repli : français).
                    UserDefaults.standard.removeObject(forKey: storageKey)
                    lookupLocale.withLock { $0 = nil }
                    GrenierFormat.setLocale(nil)
                    SharedLanguage.write(code: nil)
                    return .system
                }
                language = fromSettings
            }
        }
        apply(language)
        return language
    }

    /// À appeler au lancement et à chaque changement : retient la langue pour `String(localized:)`
    /// et l'écrit dans `AppleLanguages` pour le prochain lancement.
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        GrenierFormat.setLocale(language == .system ? nil : language.locale)
        // Widget et Live Activity (extension) : même langue, lue dans l'App Group.
        SharedLanguage.write(code: language == .system ? nil : language.rawValue)
        switch language {
        case .system:
            lookupLocale.withLock { $0 = nil }
            // Rend la main à l'appareil (ou aux Réglages iOS de l'app) au prochain lancement.
            if defaults.string(forKey: storageKey) != nil {
                defaults.removeObject(forKey: "AppleLanguages")
            }
            defaults.removeObject(forKey: storageKey)
        case .french, .english:
            lookupLocale.withLock { $0 = language.locale }
            defaults.set(language.rawValue, forKey: storageKey)
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Chaîne du catalogue dans la langue choisie (ou celle de l'appareil).
    static func localized(_ value: String.LocalizationValue) -> String {
        guard let locale = lookupLocale.withLock({ $0 }) else {
            return Swift.String(localized: value, bundle: .main)
        }
        var resource = LocalizedStringResource(value, bundle: .main)
        resource.locale = locale
        return Swift.String(localized: resource)
    }
}

extension String {
    /// T-171 : remplace `String(localized:)` de Foundation dans ce module, pour suivre la langue choisie
    /// dans l'app sans relancer. Même signature d'appel : `String(localized: "Texte \(n)")`.
    /// Les littéraux restent extraits dans `Localizable.xcstrings` (type `String.LocalizationValue`).
    nonisolated init(localized keyAndValue: String.LocalizationValue) {
        self = AppLanguage.localized(keyAndValue)
    }
}
