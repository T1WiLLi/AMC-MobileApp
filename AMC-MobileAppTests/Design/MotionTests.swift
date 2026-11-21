import SwiftUI
import Testing
@testable import AMC_MobileApp

@MainActor
struct GrenierMotionTests {
    @Test func springsWithoutReduceMotion() {
        #expect(GrenierMotion.snappy.curve(reduceMotion: false) == .snappy(duration: 0.3))
        #expect(GrenierMotion.smooth.curve(reduceMotion: false) == .smooth(duration: 0.4))
        #expect(GrenierMotion.bouncy.curve(reduceMotion: false) == .bouncy(duration: 0.5, extraBounce: 0.05))
        for motion in GrenierMotion.allCases {
            #expect(motion.animation(reduceMotion: false) != nil)
        }
    }

    @Test func reduceMotionRemovesSpringsAndBounce() {
        for motion in GrenierMotion.allCases {
            switch motion.curve(reduceMotion: true) {
            case .none, .fade: break
            case .snappy, .smooth, .bouncy: Issue.record("\(motion) garde un ressort sous Reduce Motion")
            }
        }
    }

    @Test func reduceMotionVariants() {
        #expect(GrenierMotion.snappy.curve(reduceMotion: true) == GrenierMotion.Curve.none)
        #expect(GrenierMotion.snappy.animation(reduceMotion: true) == nil)
        #expect(GrenierMotion.smooth.curve(reduceMotion: true) == .fade(duration: 0.2))
        #expect(GrenierMotion.bouncy.curve(reduceMotion: true) == .fade(duration: 0.25))
        #expect(Animation.grenier(.smooth, reduceMotion: true) != nil)
        #expect(Animation.grenier(.snappy, reduceMotion: true) == nil)
    }

    @Test func withGrenierAnimationRunsBodyAndReturnsResult() {
        var value = 0
        let result = withGrenierAnimation(.bouncy, reduceMotion: true) { value += 1; return value * 10 }
        #expect(value == 1)
        #expect(result == 10)
    }

    @Test func transitionsAreOpacityOnlyUnderReduceMotion() {
        for kind in GrenierTransition.allCases {
            #expect(kind.effects(reduceMotion: true) == .init(scale: 1, edge: nil))
        }
        #expect(GrenierTransition.cardAppear.effects(reduceMotion: false) == .init(scale: 0.96, edge: nil))
        #expect(GrenierTransition.banner.effects(reduceMotion: false) == .init(scale: 1, edge: .top))
        #expect(GrenierTransition.celebration.effects(reduceMotion: false).scale < 1)
    }

    @Test func pressableScalesOnlyWithMotion() {
        #expect(PressableButtonStyle.scale(isPressed: false, reduceMotion: false) == 1)
        #expect(PressableButtonStyle.scale(isPressed: true, reduceMotion: false) == PressableButtonStyle.pressedScale)
        #expect(PressableButtonStyle.pressedScale < 1 && PressableButtonStyle.pressedScale >= 0.95)
        #expect(PressableButtonStyle.opacity(isPressed: true, reduceMotion: false) == 1)
        // Reduce Motion : pas d'échelle, mais l'appui reste visible.
        #expect(PressableButtonStyle.scale(isPressed: true, reduceMotion: true) == 1)
        #expect(PressableButtonStyle.opacity(isPressed: true, reduceMotion: true) < 1)
        #expect(PressableButtonStyle.opacity(isPressed: false, reduceMotion: true) == 1)
    }
}

@MainActor
struct GrenierHapticTests {
    @Test func mapsToSystemFeedback() {
        #expect(GrenierHaptic.selection.feedback == .selection)
        #expect(GrenierHaptic.success.feedback == .success)
        #expect(GrenierHaptic.warning.feedback == .warning)
        #expect(GrenierHaptic.error.feedback == .error)
    }
}
