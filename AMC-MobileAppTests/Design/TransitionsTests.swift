import SwiftUI
import Testing
@testable import AMC_MobileApp

@MainActor
struct GrenierTransitionsTests {
    @Test func cascadeDelayGrowsThenCaps() {
        let style = GrenierAppearStyle.cards
        let effects = style.effects(reduceMotion: false)
        #expect(style.delay(for: 0, reduceMotion: false) == 0)
        #expect(style.delay(for: 1, reduceMotion: false) == effects.interval)
        #expect(style.delay(for: 3, reduceMotion: false) > style.delay(for: 2, reduceMotion: false))
        // Une longue liste ne fait jamais attendre plus que l'index plafond.
        let cap = style.delay(for: effects.maxStaggeredIndex, reduceMotion: false)
        #expect(style.delay(for: 50, reduceMotion: false) == cap)
        #expect(cap <= 0.4)
        #expect(style.delay(for: -3, reduceMotion: false) == 0)
    }

    @Test func reduceMotionAppearsInPlaceWithoutDelay() {
        for style in GrenierAppearStyle.allCases {
            let effects = style.effects(reduceMotion: true)
            #expect(effects.offsetY == 0)
            #expect(effects.scale == 1)
            for index in 0..<10 {
                #expect(style.delay(for: index, reduceMotion: true) == 0)
            }
        }
    }

    @Test func sheetStaggerIsSubtlerThanCards() {
        let cards = GrenierAppearStyle.cards.effects(reduceMotion: false)
        let sheet = GrenierAppearStyle.sheet.effects(reduceMotion: false)
        #expect(sheet.offsetY < cards.offsetY)
        #expect(sheet.interval <= cards.interval)
        #expect(sheet.scale >= cards.scale)
    }

    @Test func tabEntranceIsAShortFade() {
        #expect(GrenierTabEntrance.startOpacity > 0 && GrenierTabEntrance.startOpacity < 1)
        #expect(GrenierTabEntrance.duration <= 0.3)
    }

    @Test func zoomRegistryCountsDuplicateSources() {
        let registry = GrenierZoomRegistry()
        let route = OfferRoute(offerId: "o1")
        #expect(!registry.contains(route))
        registry.register(route)
        registry.register(route)
        registry.unregister(route)
        // Une même carte affichée deux fois reste source tant qu'une copie est à l'écran.
        #expect(registry.contains(route))
        registry.unregister(route)
        #expect(!registry.contains(route))
        registry.unregister(route)
        #expect(!registry.contains(route))
        #expect(!registry.contains(GroupRoute(groupId: "o1")))
    }
}
