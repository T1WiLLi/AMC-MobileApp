// GuidedTour.swift
// Visite guidée avec Noisette (FB-19) : une carte d'accueil sur l'Accueil du portail Familles, puis une bulle
// par étape, posée au-dessus de l'élément qu'elle explique, avec « Précédent », « Suivant », « Passer » et « x sur n ».
//
// La visite est une petite machine à états (`GuidedTourMachine`, testée) gardée dans UserDefaults à chaque pas :
// elle survit à un nouveau rendu des écrans et à un redémarrage en pleine visite.
// `FamilyTabView` change d'onglet pour chaque étape et dessine la bulle (`GuidedTourOverlay`) au-dessus des onglets ;
// les écrans ne font que signaler où est l'élément de leur étape (`.guidedTourAnchor(_:)`).
//
// Avant (TipKit, `TipGroup(.ordered)`), la visite s'arrêtait après la première bulle : rien ne changeait d'onglet,
// les deux bulles de l'Accueil partageaient la même ancre, et une bulle fermée d'un toucher à côté n'était pas
// invalidée, donc le groupe ne passait jamais à la suivante.

import Foundation
import Observation
import SwiftUI

// MARK: - Étapes

/// Écran (onglet du portail Familles) où une étape de la visite est montrée.
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

// MARK: - Machine à états

/// Où en est la visite. Pure et sans effet de bord : `GuidedTour` la persiste à chaque changement.
nonisolated struct GuidedTourMachine: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        /// La carte d'accueil de Noisette n'a pas encore été vue.
        case welcome
        /// Visite en cours, à l'étape `index`.
        case touring(index: Int)
        /// Visite vue jusqu'au bout.
        case finished
        /// « Plus tard », « Passer » ou fermée : rien ne s'affiche jusqu'à « Revoir le tutoriel ».
        case skipped
    }

    let steps: [TourStep]
    private(set) var phase: Phase

    init(steps: [TourStep] = TourStep.allCases, phase: Phase = .welcome) {
        self.steps = steps
        // Un index enregistré hors des bornes (étapes changées entre deux versions) reprend au début.
        if case .touring(let index) = phase, !steps.indices.contains(index) {
            self.phase = steps.isEmpty ? .finished : .touring(index: 0)
        } else {
            self.phase = phase
        }
    }

    var index: Int? {
        if case .touring(let index) = phase { index } else { nil }
    }

    var currentStep: TourStep? { index.map { steps[$0] } }
    var isTouring: Bool { index != nil }
    var isFirstStep: Bool { index == 0 }
    var isLastStep: Bool { index == steps.count - 1 }
    /// Visite terminée ou passée : elle ne revient qu'avec `replay()`.
    var isDone: Bool { phase == .finished || phase == .skipped }

    /// « C'est parti ! » sur la carte d'accueil.
    mutating func start() {
        guard phase == .welcome else { return }
        phase = steps.isEmpty ? .finished : .touring(index: 0)
    }

    /// « Plus tard » ou carte glissée vers le bas.
    mutating func postpone() {
        guard phase == .welcome else { return }
        phase = .skipped
    }

    /// « Suivant », ou « Terminer » à la dernière étape.
    mutating func next() {
        guard let index else { return }
        phase = index + 1 < steps.count ? .touring(index: index + 1) : .finished
    }

    /// « Précédent » : sans effet à la première étape.
    mutating func back() {
        guard let index, index > 0 else { return }
        phase = .touring(index: index - 1)
    }

    /// « Passer » ou le bouton Fermer : la visite s'arrête là.
    mutating func skip() {
        guard phase == .welcome || isTouring else { return }
        phase = .skipped
    }

    /// « Revoir le tutoriel avec Noisette » : la carte d'accueil revient.
    mutating func replay() {
        phase = .welcome
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

/// Phase de la visite dans UserDefaults, écrite à chaque pas.
struct GuidedTourStore {
    static let phaseKey = "guidedTour.phase"
    /// Ancienne version (TipKit) : carte vue. Une visite déjà vue ne revient pas après la mise à jour.
    static let legacyWelcomeSeenKey = "guidedTour.welcomeSeen"

    let defaults: UserDefaults

    func load(steps: [TourStep] = TourStep.allCases) -> GuidedTourMachine {
        GuidedTourMachine(steps: steps, phase: storedPhase)
    }

    func save(_ machine: GuidedTourMachine) {
        defaults.set(Self.encode(machine.phase), forKey: Self.phaseKey)
    }

    private var storedPhase: GuidedTourMachine.Phase {
        if let raw = defaults.string(forKey: Self.phaseKey), let phase = Self.decode(raw) { return phase }
        return defaults.bool(forKey: Self.legacyWelcomeSeenKey) ? .finished : .welcome
    }

    static func encode(_ phase: GuidedTourMachine.Phase) -> String {
        switch phase {
        case .welcome: "welcome"
        case .touring(let index): "touring:\(index)"
        case .finished: "finished"
        case .skipped: "skipped"
        }
    }

    static func decode(_ raw: String) -> GuidedTourMachine.Phase? {
        switch raw {
        case "welcome": return .welcome
        case "finished": return .finished
        case "skipped": return .skipped
        default:
            guard raw.hasPrefix("touring:"), let index = Int(raw.dropFirst("touring:".count)), index >= 0 else { return nil }
            return .touring(index: index)
        }
    }
}

// MARK: - Visite

/// Visite guidée partagée par l'Accueil, la Cueillette, les Groupes, l'Impact et le Profil.
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
    private(set) var machine: GuidedTourMachine
    /// Cadre (coordonnées de la fenêtre) de l'élément de chaque étape, signalé par `.guidedTourAnchor(_:)`.
    private(set) var anchorFrames: [TourStep: CGRect] = [:]
    @ObservationIgnored private let store: GuidedTourStore

    init(store: GuidedTourStore, isEnabled: Bool) {
        self.store = store
        self.isEnabled = isEnabled
        self.machine = store.load()
    }

    /// Au lancement : `-demoTour` rejoue la visite depuis la carte d'accueil. Une visite interrompue reprend où elle était.
    func configureAtLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isEnabled, GuidedTourPolicy.replaysAtLaunch(arguments: arguments) else { return }
        update { $0.replay() }
    }

    /// La carte « Salut, moi c'est Noisette » doit s'afficher.
    var showsWelcome: Bool { isEnabled && machine.phase == .welcome }

    /// Étape à montrer maintenant, nil hors visite.
    var currentStep: TourStep? { isEnabled ? machine.currentStep : nil }

    func start() { update { $0.start() } }
    func postpone() { update { $0.postpone() } }
    func next() { update { $0.next() } }
    func back() { update { $0.back() } }
    func skip() { update { $0.skip() } }

    /// « Revoir le tutoriel avec Noisette » (Profil) : la carte d'accueil revient sur l'Accueil, sans redémarrer.
    func replay() {
        guard isEnabled else { return }
        update { $0.replay() }
    }

    func updateAnchor(_ frame: CGRect, for step: TourStep) {
        // Toujours retenu (une ancre ne se signale qu'à son premier rendu et quand elle bouge) ;
        // seule la bulle lit ces cadres, et seulement pendant la visite.
        guard isEnabled, anchorFrames[step] != frame else { return }
        anchorFrames[step] = frame
    }

    private func update(_ change: (inout GuidedTourMachine) -> Void) {
        var machine = self.machine
        change(&machine)
        guard machine != self.machine else { return }
        self.machine = machine
        store.save(machine)
    }
}

extension View {
    /// Signale à la visite guidée où est l'élément de `step` (FB-19). Sans effet hors visite.
    func guidedTourAnchor(_ step: TourStep) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            GuidedTour.shared.updateAnchor(frame, for: step)
        }
    }
}
