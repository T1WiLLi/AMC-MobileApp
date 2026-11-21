import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct TierUnlockedCelebrationContentTests {
    let content = TierUnlockedCelebrationContent(
        oldPriceCents: 320, newPriceCents: 260, unit: "kg", savingsPercent: 37, groupName: "Parc-Ex Ouest"
    )

    /// Money.format peut utiliser une espace insécable avant « $ » : on normalise pour comparer.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func titleMatchesMockup() {
        #expect(content.title == "Palier débloqué !")
    }

    @Test func messageNamesTheGroupAndNewPrice() {
        #expect(plain(content.message) == "Grâce à Parc-Ex Ouest, tout le monde paie 2,60 $/kg.")
    }

    @Test func announcementSpeaksTheUnit() {
        #expect(plain(content.announcement) == "Palier débloqué, nouveau prix 2,60 $ le kilo")
    }

    @Test func pricesAreFormatted() {
        #expect(plain(content.oldPriceText) == "3,20 $")
        #expect(plain(content.newPriceText) == "2,60 $")
        #expect(content.unitSuffix == "/kg")
    }

    @Test func savingsBadgeOnlyWhenThereIsASaving() {
        #expect(content.savingsBadge == .percent(37))
        let none = TierUnlockedCelebrationContent(
            oldPriceCents: 320, newPriceCents: 260, unit: "kg", savingsPercent: 0, groupName: "Parc-Ex Ouest"
        )
        #expect(none.savingsBadge == nil)
    }

    @Test func spokenUnits() {
        #expect(TierUnlockedCelebrationContent.spokenUnit("kg") == "le kilo")
        #expect(TierUnlockedCelebrationContent.spokenUnit("L") == "le litre")
        #expect(TierUnlockedCelebrationContent.spokenUnit("lb") == "la livre")
        #expect(TierUnlockedCelebrationContent.spokenUnit("caisse") == "par caisse")
    }

    @Test func autoDismissAfterThreeSeconds() {
        #expect(TierUnlockedCelebrationContent.autoDismissDelay == .seconds(3))
    }
}

@MainActor
struct ConfettiTests {
    @Test func particlesAreDeterministic() {
        #expect(Confetti.particles(count: 20, seed: 7) == Confetti.particles(count: 20, seed: 7))
        #expect(Confetti.particles(count: 20, seed: 7) != Confetti.particles(count: 20, seed: 8))
    }

    @Test func particleCountAndPalette() {
        let particles = Confetti.particles(count: 30)
        #expect(particles.count == 30)
        #expect(particles.allSatisfy { (0..<Confetti.paletteCount).contains($0.colorIndex) })
        #expect(Set(particles.map(\.colorIndex)).count == Confetti.paletteCount)
        #expect(Confetti.particles(count: -1).isEmpty)
    }

    @Test func rainLastsTwoSeconds() {
        #expect(Confetti.duration == 2)
        for particle in Confetti.particles() {
            #expect(Confetti.frame(of: particle, at: Confetti.duration) == nil)
            #expect(Confetti.frame(of: particle, at: 5) == nil)
        }
    }

    @Test func particleHiddenBeforeItsDelay() {
        var particle = Confetti.particles(count: 1)[0]
        particle.delay = 0.3
        #expect(Confetti.frame(of: particle, at: 0.1) == nil)
        #expect(Confetti.frame(of: particle, at: 0.5) != nil)
    }

    @Test func particlesFallAndFade() {
        for particle in Confetti.particles() {
            let early = Confetti.frame(of: particle, at: particle.delay + 0.2)
            let late = Confetti.frame(of: particle, at: 1.9)
            guard let early, let late else {
                Issue.record("confetti invisible")
                continue
            }
            #expect(late.y > early.y)
            #expect((0...1).contains(early.opacity))
            #expect(late.opacity < 0.5)
        }
    }
}
