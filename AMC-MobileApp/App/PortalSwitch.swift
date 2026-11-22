import SwiftUI

// Bascule animée entre portails (T-123).
//
// Déroulé (≈ 1 s, ≈ 0,8 s sous Reduce Motion) :
//
// | Phase        | À l'écran                                                                  |
// | ------------ | -------------------------------------------------------------------------- |
// | `.covering`  | le voile Grenier se répand depuis le bouton Profil, logo panier au centre   |
// | (échange)    | voile immobile : le portail change d'un coup, sans aucune animation active  |
// | `.presenting`| le panier devient l'icône du portail,                                       |
// |              | le nom et « Côté familles / producteurs » apparaissent ; haptique, VoiceOver |
// | `.revealing` | le voile s'efface, la nouvelle barre d'onglets reprend sa taille            |
// | `.idle`      | rien                                                                       |
//
// Sous Reduce Motion : simple fondu enchaîné, sans cercle ni changement d'échelle.
// Une demande pendant une bascule est ignorée : on ne coupe jamais une bascule en cours.
//
// FB-17 (saccades) : le portail était changé dans un `onChange(of: phase)` de `RootView`, donc dans
// la même frame que le début de l'animation `.presenting` (morphing du panier, rebond, fondu du titre)
// et que l'animation d'échelle de tout l'arbre des onglets sous le voile. Construire la nouvelle
// barre d'onglets (Liquid Glass, NavigationStack, view models, `.task` de chargement) bloquait le
// thread principal pendant ces premières frames : l'icône sautait. Désormais le coordinateur pilote
// seul la bascule : il change le portail pendant que rien ne bouge (`applyPortal`, sans animation),
// laisse `settle` à la nouvelle hiérarchie pour se construire, puis seulement anime le voile.
// L'écran derrière ne s'anime plus qu'une fois, au lever du voile (`contentScale`).
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
    /// Pause, voile immobile, laissée au nouveau portail pour se construire avant toute animation.
    var settle: Double = PortalTransitionTimeline.settleTime
    /// Temps pendant lequel le nom du portail reste affiché.
    var hold: Double
    /// Durée de l'effacement du voile.
    var reveal: Double

    var revealAt: Double { presentAt + settle + hold }
    var total: Double { revealAt + reveal }

    /// Attente maximale, après `hold`, du contenu du portail de destination (chargement de l'accueil).
    /// Sans ça, le voile se lève sur un squelette et le titre saute (« Accueil » → « Bonjour Sam »).
    static let maxContentWait: Double = 1.6
    /// Pas de l'attente du contenu.
    static let contentPollStep: Double = 0.05
    /// Quelques frames pour construire le portail de destination sous le voile immobile.
    static let settleTime: Double = 0.05
    /// Échelle de départ du nouveau portail sous le voile ; il reprend 1 en se dévoilant.
    static let revealStartScale: CGFloat = 0.96

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
    /// Échelle de l'écran du portail derrière le voile : posée sans animation à l'échange,
    /// animée vers 1 une seule fois, dans la même transaction que le lever du voile.
    private(set) var contentScale: CGFloat = 1
    /// Change le portail affiché (posé par `RootView`) ; appelé sans animation, voile opaque.
    @ObservationIgnored var applyPortal: (@MainActor (Portal) -> Void)?

    @ObservationIgnored private let sleep: @MainActor (Double) async -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Contenu de l'accueil de chaque portail : prêt (`true`) ou en chargement (`false`).
    /// Absent = l'écran ne le signale pas : le voile n'attend pas.
    @ObservationIgnored private var contentReady: [Portal: Bool] = [:]

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

    /// Signalé par l'accueil d'un portail (`portalContentReady(_:when:)`).
    func setContentReady(_ ready: Bool, for portal: Portal) {
        contentReady[portal] = ready
    }

    /// Attend la fin de la bascule en cours (tests).
    func waitUntilIdle() async {
        await task?.value
    }

    private func run(to destination: Portal, timeline: PortalTransitionTimeline, reduceMotion: Bool) async {
        await sleep(timeline.presentAt)
        // Voile opaque et immobile : l'échange lourd ne tombe sur aucune frame animée.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            applyPortal?(destination)
            contentScale = reduceMotion ? 1 : PortalTransitionTimeline.revealStartScale
        }
        await sleep(timeline.settle)
        move(to: .presenting(destination), timeline: timeline, reduceMotion: reduceMotion)
        completedSwitches += 1
        announce(destination.switchAnnouncement)
        await sleep(timeline.hold)
        // Le voile reste tant que l'accueil du portail charge encore (au plus `maxContentWait`).
        var waited = 0.0
        while contentReady[destination] == false, waited < PortalTransitionTimeline.maxContentWait {
            await sleep(PortalTransitionTimeline.contentPollStep)
            waited += PortalTransitionTimeline.contentPollStep
        }
        withAnimation(timeline.animation(for: .revealing(destination), reduceMotion: reduceMotion)) {
            phase = .revealing(destination)
            contentScale = 1
        }
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

// MARK: - Contenu prêt

extension View {
    /// Signale au coordinateur de bascule si l'accueil de `portal` a son contenu : le voile ne se lève
    /// qu'une fois l'écran chargé (au plus `PortalTransitionTimeline.maxContentWait` de plus).
    func portalContentReady(_ portal: Portal, when ready: Bool) -> some View {
        modifier(PortalContentReadyReporter(portal: portal, ready: ready))
    }
}

private struct PortalContentReadyReporter: ViewModifier {
    @Environment(PortalSwitchCoordinator.self) private var coordinator: PortalSwitchCoordinator?
    let portal: Portal
    let ready: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: ready, initial: true) { _, isReady in
                coordinator?.setContentReady(isReady, for: portal)
            }
    }
}
