import Foundation
import Testing
@testable import AMC_MobileApp

/// Marque de l'app depuis un JSON embarqué (B-032).
struct BrandConfigTests {
    private static func decode(_ json: String) -> BrandConfig { BrandConfig.decode(Data(json.utf8)) }

    @Test func decodesACompleteBrand() {
        let brand = Self.decode("""
        {"name":"Panier Jarry","logo":{"symbol":"leaf.fill","asset":"LogoJarry"},
         "colors":{"accentLight":"#1E6B52","accentDark":"5FC9A0"},
         "texts":{"tagline":"Le panier du parc Jarry","welcome":"Salut voisin"}}
        """)
        #expect(brand.name == "Panier Jarry")
        #expect(brand.logo == .init(symbol: "leaf.fill", asset: "LogoJarry"))
        #expect(brand.colors == .init(accentLight: "#1E6B52", accentDark: "#5FC9A0"))
        #expect(brand.texts == .init(tagline: "Le panier du parc Jarry", welcome: "Salut voisin"))
    }

    @Test func missingFieldsFallBackToGrenierOneByOne() {
        let brand = Self.decode(#"{"name":"Panier Jarry","texts":{"welcome":"Salut"}}"#)
        #expect(brand.name == "Panier Jarry")
        #expect(brand.logo == BrandConfig.grenier.logo)
        #expect(brand.colors == BrandConfig.grenier.colors)
        #expect(brand.texts.welcome == "Salut")
        #expect(brand.texts.tagline == BrandConfig.grenier.texts.tagline)
    }

    @Test func blankStringsAndBadColorsAreIgnored() {
        let brand = Self.decode(##"{"name":"  ","logo":{"symbol":""},"colors":{"accentLight":"orange","accentDark":"#12"}}"##)
        #expect(brand.name == "Grenier")
        #expect(brand.logo.symbol == BrandConfig.grenier.logo.symbol)
        #expect(brand.colors.accentLight == nil)
        #expect(brand.colors.accentDark == nil)
    }

    @Test(arguments: ["", "pas du json", "[1, 2]", #"{"name": 42}"#])
    func invalidJSONGivesGrenier(_ json: String) {
        #expect(Self.decode(json) == .grenier)
    }

    @Test func missingResourceGivesGrenier() {
        #expect(BrandConfig.load(from: .main, resource: "marque-introuvable") == .grenier)
    }

    @Test func bundledBrandIsReadable() {
        let brand = BrandConfig.load()
        #expect(brand.name == "Grenier")
        #expect(brand.colors.accentLight == "#A84D18")
        #expect(brand.colors.accentDark == "#F08A4B")
    }

    @Test func hexIsNormalized() {
        #expect(BrandConfig.validHex("a84d18") == "#A84D18")
        #expect(BrandConfig.validHex(" #F08A4B ") == "#F08A4B")
        #expect(BrandConfig.validHex("#GGGGGG") == nil)
        let color = BrandConfig.uiColor(hex: "#FF8000")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(red == 1 && blue == 0)
        #expect(abs(green - 128.0 / 255) < 0.001)
    }
}
