// WidgetLanguage.swift
// Le widget et la Live Activity suivent la langue choisie dans l'app (lue dans l'App Group, `SharedLanguage`),
// et non celle de l'appareil : comme `AppLanguage` côté app, pour `Text("…")` et `String(localized:)`.

import SwiftUI

nonisolated enum WidgetLanguage {
    /// Locale de l'extension : celle choisie dans l'app, sinon fr_CA ou en_CA selon la langue de l'appareil.
    /// Lue à chaque rendu : l'extension peut rester en vie pendant que la langue change dans l'app.
    static var locale: Locale { GrenierFormat.locale }

    /// Chaîne du catalogue de l'extension dans la langue choisie dans l'app (ou celle de l'appareil).
    static func localized(_ value: String.LocalizationValue) -> String {
        guard let forced = SharedLanguage.forcedLocale() else {
            return Swift.String(localized: value, bundle: .main)
        }
        var resource = LocalizedStringResource(value, bundle: .main)
        resource.locale = forced
        return Swift.String(localized: resource)
    }
}

extension String {
    /// Remplace `String(localized:)` de Foundation dans l'extension (et dans `Shared/` compilé avec elle),
    /// pour résoudre dans la langue de l'app. Même signature d'appel que côté app (`AppLanguage`).
    nonisolated init(localized keyAndValue: String.LocalizationValue) {
        self = WidgetLanguage.localized(keyAndValue)
    }
}

extension View {
    /// `Text("…")` et les formats SwiftUI dans la langue de l'app.
    func widgetLanguage() -> some View {
        environment(\.locale, WidgetLanguage.locale)
    }
}
