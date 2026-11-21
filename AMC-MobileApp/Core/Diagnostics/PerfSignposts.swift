// PerfSignposts.swift
// Mesure des temps (T-111, S-11 étape 1) : démarrage, restauration de la session Auth, requêtes Firestore.
// Chaque mesure sort à la fois en intervalle `os_signpost` (Instruments) et en ligne de journal avec la durée
// en ms (`log stream`), sous le sous-système de l'app et la catégorie « Perf ». Voir docs/perf.md.
//
// Coût nul quand désactivé : en Release, sans l'argument `-PerfSignposts` et sans Instruments qui enregistre,
// `measure` appelle juste le bloc (pas d'horloge, pas de signpost, pas de journal).

import Foundation
import OSLog
import os

nonisolated enum PerfSignposts {
    static let subsystem = Bundle.main.bundleIdentifier ?? "ca.amc2026.mobileapp"
    static let category = "Perf"

    private static let signposter = OSSignposter(subsystem: subsystem, category: category)
    private static let logger = Logger(subsystem: subsystem, category: category)

    /// Actif en Debug, avec l'argument de lancement `-PerfSignposts`, ou quand Instruments enregistre.
    static var isEnabled: Bool {
        isEnabledAtLaunch || signposter.isEnabled
    }

    private static let isEnabledAtLaunch: Bool = {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.arguments.contains("-PerfSignposts")
        #endif
    }()

    // MARK: - Mesure d'un bloc

    /// Mesure un bloc synchrone et renvoie son résultat (l'erreur éventuelle est relancée telle quelle).
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let interval = begin(name)
        do {
            let value = try body()
            interval.end()
            return value
        } catch {
            interval.end(failed: true)
            throw error
        }
    }

    /// Mesure un bloc asynchrone et renvoie son résultat (l'erreur éventuelle est relancée telle quelle).
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let interval = begin(name)
        do {
            let value = try await body()
            interval.end()
            return value
        } catch {
            interval.end(failed: true)
            throw error
        }
    }

    // MARK: - Intervalle ouvert

    /// Ouvre un intervalle qui peut se fermer ailleurs (callback, autre fonction). Fermer avec `end()`.
    static func begin(_ name: StaticString) -> Interval {
        guard isEnabled else { return Interval(name: name, state: nil) }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        return Interval(name: name, state: state)
    }

    /// Intervalle en cours. `end()` ne compte que la première fois : on peut l'appeler à chaque callback.
    final class Interval: Sendable {
        let name: StaticString
        private let signpost: OSSignpostIntervalState?
        private let start: ContinuousClock.Instant?
        private let isOpen = OSAllocatedUnfairLock(initialState: true)

        fileprivate init(name: StaticString, state: OSSignpostIntervalState?) {
            self.name = name
            self.signpost = state
            self.start = state == nil ? nil : .now
        }

        /// Ferme l'intervalle et renvoie sa durée ; nil s'il était déjà fermé ou si la mesure est désactivée.
        @discardableResult
        func end(failed: Bool = false) -> Duration? {
            let wasOpen = isOpen.withLock { open in
                defer { open = false }
                return open
            }
            guard wasOpen, let signpost, let start else { return nil }
            let elapsed = ContinuousClock.now - start
            PerfSignposts.signposter.endInterval(name, signpost)
            PerfSignposts.log(name, elapsed, failed: failed)
            return elapsed
        }
    }

    // MARK: - Démarrage

    private static let firstScreenShown = OSAllocatedUnfairLock(initialState: false)

    /// À appeler à l'apparition du premier écran : journalise le temps depuis le lancement du processus.
    /// Ne compte qu'une fois par lancement.
    static func markFirstScreen() {
        let alreadyShown = firstScreenShown.withLock { shown in
            defer { shown = true }
            return shown
        }
        guard !alreadyShown, isEnabled else { return }
        signposter.emitEvent("launch.firstScreen")
        guard let start = processStartDate() else { return }
        let elapsed = Duration.milliseconds(Int64(Date.now.timeIntervalSince(start) * 1_000))
        log("launch.firstScreen", elapsed, failed: false)
    }

    /// Heure de lancement du processus (avant `main`), lue avec `sysctl`.
    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }

    // MARK: - Journal

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private static func log(_ name: StaticString, _ elapsed: Duration, failed: Bool) {
        let label = name.description
        let ms = milliseconds(elapsed)
        if failed {
            logger.info("\(label, privacy: .public) : \(ms, format: .fixed(precision: 1)) ms (échec)")
        } else {
            logger.info("\(label, privacy: .public) : \(ms, format: .fixed(precision: 1)) ms")
        }
    }
}
