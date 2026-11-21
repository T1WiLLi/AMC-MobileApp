import Testing
import UIKit
@testable import AMC_MobileApp

/// Re-thème à l'entrée d'un groupe (B-034).
struct GroupThemeTests {
    private static func group(_ branding: GroupBranding?) -> NeighborhoodGroup {
        NeighborhoodGroup(
            id: "g1", name: "Voisins de Jarry", neighborhood: "Villeray", centerGeohash: "f25dv",
            radiusMeters: 800, coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "VJ-1",
            branding: branding
        )
    }

    @Test func contrastRatioFollowsWCAG() {
        #expect(abs(GroupTheme.contrastRatio(.white, .black) - 21) < 0.01)
        #expect(abs(GroupTheme.contrastRatio(.white, .white) - 1) < 0.01)
        // Grenier (#A84D18) sur blanc : au-dessus de 4,5:1.
        let grenier = try! #require(BrandConfig.uiColor(hex: "#A84D18"))
        #expect(GroupTheme.contrastRatio(grenier, .white) >= 4.5)
    }

    @Test func readableGroupAccentIsApplied() {
        let theme = GroupTheme(group: Self.group(GroupBranding(
            displayName: "Jarry ensemble", emblem: "leaf.fill", accentLight: "#1E6B52", accentDark: "#5FC9A0",
            welcomeMessage: "Salut voisin !"
        )))
        #expect(theme.usesGroupAccent)
        #expect(theme.emblem == "leaf.fill")
        #expect(theme.displayName == "Jarry ensemble")
        #expect(theme.welcomeMessage == "Salut voisin !")
    }

    @Test(arguments: [("#FFE066", "#FFE066"), ("#1E6B52", "#0A2A20")])
    func accentBelowAAFallsBackToGrenier(light: String, dark: String) {
        // Jaune pâle sous du blanc, ou vert trop foncé sous du texte sombre.
        let theme = GroupTheme(group: Self.group(GroupBranding(emblem: "sun.max.fill", accentLight: light, accentDark: dark)))
        #expect(!theme.usesGroupAccent)
        #expect(theme.accent == GroupTheme.grenier.accent)
        // L'emblème reste celui du groupe.
        #expect(theme.emblem == "sun.max.fill")
    }

    @Test func groupWithoutBrandingKeepsGrenier() {
        let theme = GroupTheme(group: Self.group(nil))
        #expect(!theme.usesGroupAccent)
        #expect(theme.accent == GroupTheme.grenier.accent)
        #expect(theme.emblem == GroupBranding.defaultEmblem)
        #expect(theme.displayName == "Voisins de Jarry")
    }

    @Test func outsideAGroupTheThemeIsGrenier() {
        #expect(GroupTheme.grenier.displayName == nil)
        #expect(!GroupTheme.grenier.usesGroupAccent)
    }

    @Test func fakeBrandedGroupsPassAA() async throws {
        let groups = try await AppRepositories.fake(behavior: .instant).groups.groups(inNeighborhood: nil)
        let branded = groups.filter { $0.branding?.accentLight != nil }
        #expect(branded.count >= 2)
        for group in branded {
            #expect(GroupTheme(group: group).usesGroupAccent, "\(group.id) devrait passer AA")
        }
    }
}
