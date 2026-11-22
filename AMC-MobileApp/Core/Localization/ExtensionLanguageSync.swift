import WidgetKit

/// Redessine le widget et la Live Activity (extension GrenierWidgets) quand la langue de l'app change :
/// l'extension lit la langue dans l'App Group (`SharedLanguage`), écrite par `AppLanguage.apply`.
enum ExtensionLanguageSync {
    /// Recharge les timelines du widget « prochain palier ».
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Après `AppLanguage.apply` : widget rechargé, Live Activity en cours renvoyée pour être redessinée.
    static func languageDidChange() {
        reloadWidgets()
        Task { await OrderActivityController.shared.refresh() }
    }
}
