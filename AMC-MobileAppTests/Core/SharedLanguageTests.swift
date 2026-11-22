import Foundation
import Testing
@testable import AMC_MobileApp

/// Langue de l'app partagée avec le widget et la Live Activity (App Group).
struct SharedLanguageTests {
    /// UserDefaults isolés, pour ne pas toucher à l'App Group réel.
    private func makeDefaults() -> UserDefaults {
        let name = "SharedLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func writesAndReadsForcedLanguage() {
        let defaults = makeDefaults()
        SharedLanguage.write(code: "en", to: defaults)
        #expect(SharedLanguage.storedCode(in: defaults) == "en")
        #expect(SharedLanguage.forcedLocale(in: defaults)?.identifier == "en_CA")

        SharedLanguage.write(code: "fr", to: defaults)
        #expect(SharedLanguage.forcedLocale(in: defaults)?.identifier == "fr_CA")
    }

    @Test func systemLanguageClearsTheChoice() {
        let defaults = makeDefaults()
        SharedLanguage.write(code: "en", to: defaults)
        SharedLanguage.write(code: nil, to: defaults)
        #expect(SharedLanguage.storedCode(in: defaults) == nil)
        #expect(SharedLanguage.forcedLocale(in: defaults) == nil)
    }

    @Test func unsupportedLanguageIsIgnored() {
        let defaults = makeDefaults()
        SharedLanguage.write(code: "de", to: defaults)
        #expect(SharedLanguage.storedCode(in: defaults) == nil)

        defaults.set("de", forKey: SharedLanguage.storageKey)
        #expect(SharedLanguage.forcedLocale(in: defaults) == nil)
    }

    @Test func missingContainerIsHarmless() {
        SharedLanguage.write(code: "en", to: nil)
        #expect(SharedLanguage.storedCode(in: nil) == nil)
    }
}
