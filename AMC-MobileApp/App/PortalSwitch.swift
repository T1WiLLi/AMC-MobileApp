import SwiftUI

// Bascule animée entre portails (T-123).
//
// Déroulé (≈ 1 s, ≈ 0,8 s sous Reduce Motion) :
//
// | Phase        | À l'écran                                                                  |
// | ------------ | -------------------------------------------------------------------------- |
// | `.covering`  | le voile Grenier se répand depuis le bouton Profil, logo panier au centre   |
// | `.presenting`| le portail change sous le voile ; le panier devient l'icône du portail,     |
// |              | le nom et « Côté familles / producteurs » apparaissent ; haptique, VoiceOver |
// | `.revealing` | le voile s'efface, la nouvelle barre d'onglets reprend sa taille            |
// | `.idle`      | rien                                                                       |
//
// Sous Reduce Motion : simple fondu enchaîné, sans cercle ni changement d'échelle.
// Une demande pendant une bascule est ignorée : on ne coupe jamais une bascule en cours.
//
//     @Environment(PortalSwitchCoordinator.self) private var portalSwitch: PortalSwitchCoordinator?
//     portalSwitch?.switchPortal(from: portal, to: .vendor, reduceMotion: reduceMotion)

/// Étape de la bascule ; le portail associé est la destination.
enum PortalTransitionPhase: Equatable, Sendable {
    case idle
    case covering(Portal)
    case presenting(Portal)
    case revealing(Portal)

    var destination: Portal? {
        switch self {
        case .idle: nil
        case .covering(let portal), .presenting(let portal), .revealing(let portal): portal
        }
    }

    var isActive: Bool { self != .idle }

    /// Le voile bloque les touchers tant qu'il couvre l'écran.
    var blocksTouches: Bool {
        switch self {
        case .covering, .presenting: true
        case .idle, .revealing: false
        }
    }

    /// Le nom et l'icône du portail de destination sont affichés.
    var showsDestination: Bool {
        switch self {
        case .presenting, .revealing: true
        case .idle, .covering: false
        }
    }

    /// Échelle du disque du voile (il part du bouton Profil). Toujours 1 sous Reduce Motion : fondu seul.
    func coverScale(reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        return self == .idle ? 0.001 : 1
    }

    /// Opacité du voile et de son contenu.
    var coverOpacity: Double {
        switch self {
        case .covering, .presenting: 1
        case .idle, .revealing: 0
        }
    }

    /// Échelle de l'écran du portail derrière le voile : il recule pendant la bascule puis revient.
    func contentScale(reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        switch self {
        case .idle, .revealing: return 1
        case .covering: return 0.94
        case .presenting: return 0.97
        }
    }

    /// Échelle du logo et du titre au centre du voile.
    func badgeScale(reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        switch self {
        case .idle: return 0.7
        case .covering: return 0.92
        case .presenting: return 1
        case .revealing: return 1.08
        }
    }
}

/// Minutage de la bascule, en secondes depuis la demande.
struct PortalTransitionTimeline: Equatable, Sendable {
    /// Durée de l'animation du voile qui couvre l'écran.
    var cover: Double
    /// Moment où le portail change sous le voile (après la fermeture de la feuille Profil).
    var presentAt: Double
    /// Temps pendant lequel le nom du portail reste affiché.
    var hold: Double
    /// Durée de l'effacement du voile.
    var reveal: Double

    var revealAt: Double { presentAt + hold }
    var total: Double { revealAt + reveal }

    static func standard(reduceMotion: Bool) -> PortalTransitionTimeline {
        reduceMotion
            ? PortalTransitionTimeline(cover: 0.2, presentAt: 0.36, hold: 0.42, reveal: 0.2)
            : PortalTransitionTimeline(cover: 0.36, presentAt: 0.44, hold: 0.3, reveal: 0.26)
    }

    /// Animation de chaque phase (fondu court sous Reduce Motion).
    func animation(for phase: PortalTransitionPhase, reduceMotion: Bool) -> Animation? {
        switch phase {
        case .idle: nil
        case .covering: reduceMotion ? .easeInOut(duration: cover) : .smooth(duration: cover)
        case .presenting: GrenierMotion.smooth.animation(reduceMotion: reduceMotion)
        case .revealing: reduceMotion ? .easeInOut(duration: reveal) : .smooth(duration: reveal)
        }
    }
}

/// Orchestre la bascule de portail. Créé par `RootView`, lu dans l'environnement par le profil
/// et le menu du bouton Profil. `RootView` applique le portail quand la phase passe à `.presenting`.
@Observable
@MainActor
final class PortalSwitchCoordinator {
    private(set) var phase: PortalTransitionPhase = .idle
    /// Nombre de bascules arrivées au portail de destination (déclencheur de l'haptique).
    private(set) var completedSwitches = 0

    @ObservationIgnored private let sleep: @MainActor (Double) async -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        sleep: @escaping @MainActor (Double) async -> Void = { seconds in
            // Pas d'annulation : une bascule commencée va toujours jusqu'au bout.
            try? await Task.sleep(for: .seconds(seconds))
        },
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    /// Lance la bascule ; `false` si c'est déjà le portail actif ou si une bascule est en cours.
    @discardableResult
    func switchPortal(from current: Portal, to destination: Portal, reduceMotion: Bool) -> Bool {
        guard destination != current, !phase.isActive else { return false }
        let timeline = PortalTransitionTimeline.standard(reduceMotion: reduceMotion)
        move(to: .covering(destination), timeline: timeline, reduceMotion: reduceMotion)
        task = Task { [weak self] in
            await self?.run(to: destination, timeline: timeline, reduceMotion: reduceMotion)
        }
        return true
    }

    /// Attend la fin de la bascule en cours (tests).
    func waitUntilIdle() async {
        await task?.value
    }

    private func run(to destination: Portal, timeline: PortalTransitionTimeline, reduceMotion: Bool) async {
        await sleep(timeline.presentAt)
        move(to: .presenting(destination), timeline: timeline, reduceMotion: reduceMotion)
        completedSwitches += 1
        announce(destination.switchAnnouncement)
        await sleep(timeline.hold)
        move(to: .revealing(destination), timeline: timeline, reduceMotion: reduceMotion)
        await sleep(timeline.reveal)
        // Voile déjà invisible : retour à l'état initial sans animation.
        phase = .idle
        task = nil
    }

    private func move(to newPhase: PortalTransitionPhase, timeline: PortalTransitionTimeline, reduceMotion: Bool) {
        withAnimation(timeline.animation(for: newPhase, reduceMotion: reduceMotion)) {
            phase = newPhase
        }
    }
}
