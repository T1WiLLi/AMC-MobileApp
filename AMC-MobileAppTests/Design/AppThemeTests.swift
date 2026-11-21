import Testing
import UIKit
@testable import AMC_MobileApp

/// B-035 : thèmes interchangeables (accent, fond, coins).
struct AppThemeTests {
    @Test(arguments: AppTheme.allCases)
    func everyAccentPassesAAWithTheTextPutOnIt(theme: AppTheme) {
        #expect(GroupTheme.meetsAA(light: theme.accentLight, dark: theme.accentDark))
    }

    @Test(arguments: AppTheme.allCases)
    func lightAndDarkResolveToDifferentColors(theme: AppTheme) {
        #expect(theme.accent(for: .light) != theme.accent(for: .dark))
        #expect(theme.fond(for: .light) != theme.fond(for: .dark))
    }

    @Test func storedRawValuesStayStable() {
        #expect(AppTheme.allCases.map(\.rawValue) == ["grenier", "fleuve", "montRoyal"])
        #expect(AppTheme(rawValue: "inconnu") == nil)
    }

    @Test func grenierKeepsTheBrandAccent() throws {
        let asset = try #require(UIColor(named: "AccentColor"))
        let light = asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(GroupTheme.contrastRatio(light, AppTheme.grenier.accentLight) < 1.01)
    }

    @Test func themeTraitDrivesTheDynamicAccent() {
        let traits = UITraitCollection { $0.userInterfaceStyle = .light; $0[AppThemeTrait.self] = .fleuve }
        let resolved = UIColor(AppTheme.accent).resolvedColor(with: traits)
        #expect(GroupTheme.contrastRatio(resolved, AppTheme.fleuve.accentLight) < 1.01)
    }

    @Test func cornersDifferBetweenThemes() {
        #expect(Set(AppTheme.allCases.map(\.cornerRadius)).count == AppTheme.allCases.count)
    }
}
