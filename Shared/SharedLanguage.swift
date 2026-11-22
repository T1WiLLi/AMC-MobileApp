// SharedLanguage.swift
// Langue choisie dans l'app (AppLanguage, T-171), partagée avec l'extension GrenierWidgets par l'App Group :
// le widget et la Live Activity s'affichent dans la langue de l'app, pas dans celle de l'appareil.

import Foundation

nonisolated enum SharedLanguage {
    /// App Group commun à l'app et à l'extension (voir Config/*.entitlements).
    static let appGroup = "group.ca.amc2026.mobileapp"
    /// Clé du choix dans les UserDefaults de l'App Group : « fr », « en », absente = langue de l'appareil.
    static let storageKey = "grenier.appLanguage"
    /// Langues traduites ; la première sert de repli.
    static let supportedCodes = ["fr", "en"]

    /// UserDefaults de l'App Group (nil si le conteneur n'existe pas).
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Écrit le choix de l'app : `nil` rend la main à la langue de l'appareil.
    static func write(code: String?, to defaults: UserDefaults? = SharedLanguage.defaults) {
        guard let defaults else { return }
        if let code, supportedCodes.contains(code) {
            defaults.set(code, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// Langue forcée par l'app (« fr » ou « en »), nil si l'app suit l'appareil.
    static func storedCode(in defaults: UserDefaults? = SharedLanguage.defaults) -> String? {
        defaults?.string(forKey: storageKey).flatMap { supportedCodes.contains($0) ? $0 : nil }
    }

    /// Locale forcée par l'app (« en_CA », « fr_CA »), nil si l'app suit l'appareil.
    static func forcedLocale(in defaults: UserDefaults? = SharedLanguage.defaults) -> Locale? {
        storedCode(in: defaults).map { Locale(identifier: $0 + "_CA") }
    }
}
