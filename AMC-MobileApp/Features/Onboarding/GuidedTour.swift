// GuidedTour.swift
// Visite guidée avec Noisette (FB-19) : une carte d'accueil sur l'Accueil du portail Familles,
// puis des bulles TipKit enchaînées par un `TipGroup(.ordered)`, rejouable depuis le Profil.
//
// Rejouer sans redémarrer : `Tips.resetDatastore()` ne marche qu'avant `Tips.configure()`, donc demanderait
// de relancer l'app. À la place, chaque bulle a un identifiant qui contient un numéro de visite (`run`)
// gardé dans UserDefaults : « Revoir la visite guidée » incrémente ce numéro et recrée le groupe,
// TipKit voit des bulles neuves (les anciennes, invalidées, restent dans son stockage sans gêner).

import Foundation
import Observation
import SwiftUI
import TipKit

// MARK: - Étapes

/// Écran où une étape de la visite est ancrée.
nonisolated enum TourScreen: String, Sendable, CaseIterable {
    case home, pickup, groups, impact
}

/// Étapes de la visite, dans l'ordre où Noisette les montre.
nonisolated enum TourStep: String, Sendable, CaseIterable {
    /// Les lots près de chez toi et le palier qui fait baisser le prix.
    case nearbyOffers
    /// Réserver une part.
    case reserveShare
    /// Le code et le créneau de cueillette.
    case pickup
    /// Les groupes de quartier.
    case groups
    /// L'impact et les économies.
    case impact

    var screen: TourScreen {
        switch self {
        case .nearbyOffers, .reserveShare: .home
        case .pickup: .pickup
        case .groups: .groups
        case .impact: .impact
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .nearbyOffers: "Des lots près de chez toi"
        case .reserveShare: "Réserve ta part"
        case .pickup: "Ta cueillette"
        case .groups: "Tes groupes de quartier"
        case .impact: "Ton impact"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .nearbyOffers:
            "Des producteurs d'ici vendent en gros. Plus ton groupe réserve de parts, plus le palier fait baisser le prix pour tout le monde."
        case .reserveShare:
            "Touche un lot, choisis ta quantité et réserve ta part : chaque part rapproche le groupe du prochain palier."
        case .pickup:
            "Ton code QR et ton créneau t'attendent ici pour récupérer ta part au point de cueillette."
        case .groups:
            "Rejoins ou crée un groupe avec tes voisins : ensemble, vous achetez en gros."
        case .impact:
            "Vois combien tu as économisé et ce que ton quartier change ensemble. Bonne cueillette !"
        }
    }

    var systemImage: String {
        switch self {
        case .nearbyOffers: "chart.line.downtrend.xyaxis"
        case .reserveShare: "cart.badge.plus"
        case .pickup: "qrcode"
        case .groups: "person.3.fill"
        case .impact: "leaf.fill"
        }
    }
}

/// Bulle TipKit d'une étape. L'identifiant contient le numéro de visite : une visite rejouée a des bulles neuves.
nonisolated struct TourTip: Tip {
    let step: TourStep
    let run: Int

    var id: String { Self.id(step: step, run: run) }
    var title: Text { Text(step.title) }
    var message: Text? { Text(step.message) }
    var image: Image? { Image(systemName: step.systemImage) }

    static func id(step: TourStep, run: Int) -> String {
        "noisette.\(step.rawValue).\(run)"
    }
}

// MARK: - Activation (tests, démo)

nonisolated enum GuidedTourPolicy {
    /// Argument de lancement : montre la visite (rejouée à chaque lancement), même avec `-useFakeData`.
    static let demoTourArgument = "-demoTour"
    static let previewVariable = "XCODE_RUNNING_FOR_PREVIEWS"

    /// Pas de visite pendant les tests unitaires ou UI, dans les previews ni avec les données fake
    /// (`-useFakeData`, `-useFakeBackend`), sauf si `-demoTour` est passé.
    static func isEnabled(arguments: [String], environment: [String: String]) -> Bool {
        if arguments.contains(demoTourArgument) { return true }
        if environment[previewVariable] == "1" { return false }
        let options = BackendLaunchOptions(arguments: arguments, environment: environment)
        return !options.isRunningTests && !options.useFakeBackend
    }

    static func replaysAtLaunch(arguments: [String]) -> Bool {
        arguments.contains(demoTourArgument)
    }
}

// MARK: - État persistant

/// Où en est la visite.
nonisolated enum GuidedTourPhase: Sendable, Equatable {
    /// La carte d'accueil de Noisette n'a pas encore été vue.
    case welcome
    /// Visite acceptée : les bulles s'enchaînent.
    case touring
    /// « Plus tard » : aucune bulle, jusqu'à « Revoir la visite guidée ».
    case skipped
}

/// Drapeaux de la visite dans UserDefaults : numéro de visite, carte vue, visite acceptée.
struct GuidedTourStore {
    static let runKey = "guidedTour.run"
    static let welcomeSeenKey = "guidedTour.welcomeSeen"
    static let acceptedKey = "guidedTour.accepted"

    let defaults: UserDefaults

    var run: Int { defaults.integer(forKey: Self.runKey) }

    var phase: GuidedTourPhase {
        guard defaults.bool(forKey: Self.welcomeSeenKey) else { return .welcome }
        return defaults.bool(forKey: Self.acceptedKey) ? .touring : .skipped
    }

    /// Ordre des bulles de la visite courante.
    var tips: [TourTip] { TourStep.allCases.map { TourTip(step: $0, run: run) } }

    func finishWelcome(accepted: Bool) {
        defaults.set(true, forKey: Self.welcomeSeenKey)
        defaults.set(accepted, forKey: Self.acceptedKey)
    }

    /// Nouvelle visite : nouveau numéro (bulles neuves), et la carte d'accueil revient.
    func replay() {
        defaults.set(run + 1, forKey: Self.runKey)
        defaults.set(false, forKey: Self.welcomeSeenKey)
        defaults.set(false, forKey: Self.acceptedKey)
    }
}

// MARK: - Visite

/// Visite guidée partagée par l'Accueil, la Cueillette, les Groupes, l'Impact et le Profil.
/// Chaque écran ancre sa bulle d'une ligne : `.popoverTip(GuidedTour.shared.tip(on: .pickup))`.
@Observable
final class GuidedTour {
    static let shared = GuidedTour(
        store: GuidedTourStore(defaults: .standard),
        isEnabled: GuidedTourPolicy.isEnabled(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    )

    let isEnabled: Bool
    private(set) var phase: GuidedTourPhase
    @ObservationIgnored private let store: GuidedTourStore
    /// Bulles enchaînées ; nil tant que TipKit n'est pas configuré (ou visite désactivée).
    private var group: TipGroup?

    init(store: GuidedTourStore, isEnabled: Bool) {
        self.store = store
        self.isEnabled = isEnabled
        self.phase = store.phase
    }

    /// Au lancement : configure TipKit (une seule fois, ici) et prépare les bulles. Rien en tests ni en mode fake.
    func configureAtLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isEnabled, group == nil else { return }
        if GuidedTourPolicy.replaysAtLaunch(arguments: arguments) {
            store.replay()
            phase = store.phase
        }
        do {
            try Tips.configure([.displayFrequency(.immediate)])
        } catch {
            // Déjà configuré : les bulles marchent quand même.
        }
        rebuildGroup()
    }

    /// La carte « Salut, moi c'est Noisette » doit s'afficher.
    var showsWelcome: Bool { isEnabled && phase == .welcome }

    /// Bulle à ancrer sur `screen`, seulement si c'est l'étape courante de la visite.
    func tip(on screen: TourScreen) -> (any Tip)? {
        guard isEnabled, phase == .touring,
              let tip = group?.currentTip as? TourTip, tip.step.screen == screen else { return nil }
        return tip
    }

    func finishWelcome(accepted: Bool) {
        store.finishWelcome(accepted: accepted)
        phase = store.phase
    }

    /// « Revoir la visite guidée » (Profil) : la carte d'accueil revient sur l'Accueil, sans redémarrer.
    func replay() {
        guard isEnabled else { return }
        store.replay()
        phase = store.phase
        rebuildGroup()
    }

    private func rebuildGroup() {
        let tips: [any Tip] = store.tips
        group = TipGroup(.ordered) { tips }
    }
}

extension View {
    /// Ancre la bulle de la visite guidée de `screen` en haut de cette vue (FB-19). Sans effet hors visite.
    /// L'ancre est un point invisible au milieu du bord du haut : la bulle s'ouvre juste en dessous, flèche vers le haut,
    /// au lieu de chercher une place autour d'une vue grande comme l'écran.
    func guidedTourTip(_ screen: TourScreen) -> some View {
        overlay(alignment: .top) {
            Color.clear
                .frame(width: 1, height: 1)
                .popoverTip(GuidedTour.shared.tip(on: screen), arrowEdge: .top)
                .accessibilityHidden(true)
        }
    }
}
