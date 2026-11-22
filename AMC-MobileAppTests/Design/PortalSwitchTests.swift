import SwiftUI
import Testing
@testable import AMC_MobileApp

/// Enregistre les phases vues pendant une bascule, sans attendre (T-123).
@MainActor
private final class PhaseRecorder {
    var phases: [PortalTransitionPhase] = []
    var sleeps: [Double] = []
    var announcements: [String] = []
    weak var coordinator: PortalSwitchCoordinator?
}

@MainActor
struct PortalSwitchTests {
    private func makeCoordinator() -> (PortalSwitchCoordinator, PhaseRecorder) {
        let recorder = PhaseRecorder()
        let coordinator = PortalSwitchCoordinator(
            sleep: { [recorder] seconds in
                recorder.sleeps.append(seconds)
                if let phase = recorder.coordinator?.phase { recorder.phases.append(phase) }
            },
            announce: { [recorder] text in recorder.announcements.append(text) }
        )
        recorder.coordinator = coordinator
        return (coordinator, recorder)
    }

    @Test func runsCoverPresentRevealThenIdle() async {
        let (coordinator, recorder) = makeCoordinator()
        #expect(coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false))
        #expect(coordinator.phase == .covering(.vendor))

        await coordinator.waitUntilIdle()

        // Le portail change pendant la pause `settle`, voile encore en `.covering`.
        #expect(recorder.phases == [.covering(.vendor), .covering(.vendor), .presenting(.vendor), .revealing(.vendor)])
        #expect(coordinator.phase == .idle)
        #expect(coordinator.completedSwitches == 1)
        #expect(recorder.announcements == [Portal.vendor.switchAnnouncement])
    }

    @Test func followsTheTimeline() async {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.switchPortal(from: .vendor, to: .family, reduceMotion: true)
        await coordinator.waitUntilIdle()
        let timeline = PortalTransitionTimeline.standard(reduceMotion: true)
        #expect(recorder.sleeps == [timeline.presentAt, timeline.settle, timeline.hold, timeline.reveal])
    }

    @Test func waitsForTheDestinationContentBeforeRevealing() async {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setContentReady(false, for: .vendor)
        coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false)
        await coordinator.waitUntilIdle()
        let timeline = PortalTransitionTimeline.standard(reduceMotion: false)
        let polls = recorder.sleeps.dropFirst(3).dropLast()
        // Jamais prêt : le voile attend au plus `maxContentWait`, puis se lève quand même.
        #expect(!polls.isEmpty && polls.allSatisfy { $0 == PortalTransitionTimeline.contentPollStep })
        #expect(polls.reduce(0, +) <= PortalTransitionTimeline.maxContentWait + 0.0001)
        #expect(recorder.sleeps.last == timeline.reveal)
        #expect(coordinator.phase == .idle)
    }

    @Test func doesNotWaitWhenTheDestinationIsReady() async {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setContentReady(true, for: .vendor)
        coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false)
        await coordinator.waitUntilIdle()
        let timeline = PortalTransitionTimeline.standard(reduceMotion: false)
        #expect(recorder.sleeps == [timeline.presentAt, timeline.settle, timeline.hold, timeline.reveal])
    }

    /// FB-17 : le portail change voile immobile, avant l'animation `.presenting`, et l'écran
    /// derrière ne s'anime qu'au lever du voile.
    @Test func appliesThePortalUnderAStillVeilBeforePresenting() async {
        let (coordinator, recorder) = makeCoordinator()
        var applied: [(Portal, PortalTransitionPhase)] = []
        coordinator.applyPortal = { [weak coordinator] portal in
            applied.append((portal, coordinator?.phase ?? .idle))
        }
        #expect(coordinator.contentScale == 1)
        coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false)
        await coordinator.waitUntilIdle()
        #expect(applied.count == 1)
        #expect(applied.first?.0 == .vendor)
        #expect(applied.first?.1 == .covering(.vendor))
        #expect(recorder.phases.first == .covering(.vendor))
        #expect(coordinator.contentScale == 1)
    }

    @Test func reduceMotionNeverScalesTheContent() async {
        let (coordinator, _) = makeCoordinator()
        var scales: [CGFloat] = []
        coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: true)
        scales.append(coordinator.contentScale)
        await coordinator.waitUntilIdle()
        scales.append(coordinator.contentScale)
        #expect(scales.allSatisfy { $0 == 1 })
    }

    @Test func ignoresSamePortal() {
        let (coordinator, _) = makeCoordinator()
        #expect(!coordinator.switchPortal(from: .family, to: .family, reduceMotion: false))
        #expect(coordinator.phase == .idle)
    }

    @Test func ignoresRequestsDuringASwitch() async {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false))
        #expect(!coordinator.switchPortal(from: .family, to: .vendor, reduceMotion: false))
        await coordinator.waitUntilIdle()
        #expect(coordinator.completedSwitches == 1)
        // Une fois revenue au repos, une nouvelle bascule est acceptée.
        #expect(coordinator.switchPortal(from: .vendor, to: .family, reduceMotion: false))
        await coordinator.waitUntilIdle()
        #expect(coordinator.completedSwitches == 2)
    }

    @Test func timelineStaysAroundOneSecond() {
        let standard = PortalTransitionTimeline.standard(reduceMotion: false)
        #expect(standard.total >= 0.8 && standard.total <= 1.1)
        // Le portail change une fois l'écran couvert, jamais pendant que le voile s'étend.
        #expect(standard.presentAt >= standard.cover)
        let reduced = PortalTransitionTimeline.standard(reduceMotion: true)
        #expect(reduced.presentAt >= reduced.cover)
        #expect(reduced.total <= standard.total)
    }

    @Test func phasesDriveTheVisuals() {
        #expect(PortalTransitionPhase.idle.coverOpacity == 0)
        #expect(PortalTransitionPhase.covering(.vendor).coverOpacity == 1)
        #expect(PortalTransitionPhase.presenting(.vendor).coverOpacity == 1)
        #expect(PortalTransitionPhase.revealing(.vendor).coverOpacity == 0)

        #expect(PortalTransitionPhase.covering(.vendor).blocksTouches)
        #expect(!PortalTransitionPhase.revealing(.vendor).blocksTouches)
        #expect(!PortalTransitionPhase.idle.blocksTouches)

        #expect(!PortalTransitionPhase.covering(.family).showsDestination)
        #expect(PortalTransitionPhase.presenting(.family).showsDestination)
        #expect(PortalTransitionPhase.presenting(.family).destination == .family)
        #expect(PortalTransitionPhase.idle.destination == nil)
    }

    @Test func reduceMotionIsAPlainCrossfade() {
        let phases: [PortalTransitionPhase] = [.idle, .covering(.vendor), .presenting(.vendor), .revealing(.vendor)]
        for phase in phases {
            #expect(phase.coverScale(reduceMotion: true) == 1)
            #expect(phase.badgeScale(reduceMotion: true) == 1)
        }
        // Sans Reduce Motion, le voile part d'un point et l'écran recule.
        #expect(PortalTransitionPhase.idle.coverScale(reduceMotion: false) < 0.01)
    }

    @Test func coveringRadiusReachesTheFarthestCorner() {
        let size = CGSize(width: 400, height: 800)
        let origin = CGPoint(x: 362, y: 78)
        let radius = PortalSplashOverlay.coveringRadius(from: origin, in: size)
        for corner in [CGPoint.zero, CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 800), CGPoint(x: 400, y: 800)] {
            let distance = ((corner.x - origin.x) * (corner.x - origin.x) + (corner.y - origin.y) * (corner.y - origin.y)).squareRoot()
            #expect(radius >= distance - 0.001)
        }
    }

    @Test func everyPortalHasSplashCopy() {
        for portal in Portal.allCases {
            #expect(!portal.splashTagline.isEmpty)
            #expect(portal.switchAnnouncement.contains(portal.title))
        }
        #expect(Portal.family.splashTagline == "Côté familles")
        #expect(Portal.vendor.splashTagline == "Côté producteurs")
    }
}
