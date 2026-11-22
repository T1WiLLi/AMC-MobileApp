// GuidedTour.swift
// Visites guidées : Noisette (portail Familles, FB-19) et Racoonette (portail Vendeurs). Une carte d'accueil,
// puis une bulle par étape, posée à côté de l'élément qu'elle explique, avec « Précédent », « Suivant »,
// « Passer » et « Étape x sur n ».
//
// Un seul moteur pour les deux visites :
// - `TourID` nomme la visite (mascotte, étapes, clé de sauvegarde, argument de démo) ;
// - `GuidedTourMachine` (testée) est la petite machine à états d'UNE visite ; `GuidedTour` la garde dans
//   UserDefaults à chaque pas (elle survit à un nouveau rendu des écrans et à un redémarrage) ;
// - la barre d'onglets du portail (`FamilyTabView`, `VendorTabView`) change d'onglet pour chaque étape et dessine
//   la bulle (`GuidedTourOverlay`) au-dessus ; les écrans ne font que signaler où est l'élément de leur étape
//   (`.guidedTourAnchor(_:)`) et faire défiler leur ScrollView jusqu'à lui (`.guidedTourScroll(_:)`) ;
// - une étape qui demande un écran poussé (fiche d'un lot, éditeur de paliers) le fait pousser par l'écran racine
//   de l'onglet, qui le retire quand la visite passe à l'étape suivante.

import Foundation
import Observation
import SwiftUI

// MARK: - Visites

/// Les visites guidées de l'app.
nonisolated enum TourID: String, Sendable, CaseIterable {
    /// Noisette, l'écureuil : le portail Familles.
    case noisette
    /// Racoonette, le raton laveur : le portail Vendeurs.
    case racoonette

    var steps: [TourStep] { TourStep.allCases.filter { $0.tour == self } }

    /// Phase de la visite dans UserDefaults. La clé de Noisette est celle de la première version.
    var storageKey: String {
        switch self {
        case .noisette: "guidedTour.phase"
        case .racoonette: "guidedTour.racoonette.phase"
        }
    }

    /// Argument de lancement : montre la visite (rejouée à chaque lancement), même avec `-useFakeData`.
    var demoArgument: String {
        switch self {
        case .noisette: "-demoTour"
        case .racoonette: "-demoVendorTour"
        }
    }

    /// Nom de la mascotte (nom propre : jamais traduit).
    var mascotName: String {
        switch self {
        case .noisette: "Noisette"
        case .racoonette: "Racoonette"
        }
    }

    /// Texte de la carte d'accueil, sous « Salut, moi c'est … ! ».
    var welcome: String {
        let count = steps.count
        switch self {
        case .noisette:
            return String(localized: "Je suis l'écureuil du quartier. En \(count) petites bulles, je te montre comment payer moins cher en achetant avec tes voisins.")
        case .racoonette:
            return String(localized: "Je suis le raton laveur du Grenier. En \(count) petites bulles, je te montre comment vendre à tout un quartier, sans courir après chaque famille.")
        }
    }

    /// Où rejouer la visite : le Profil, dans le portail de la mascotte.
    var portal: Portal {
        switch self {
        case .noisette: .family
        case .racoonette: .vendor
        }
    }

    var replayHint: String {
        switch self {
        case .noisette: String(localized: "Noisette te remontre l'app, étape par étape, en commençant par l'Accueil")
        case .racoonette: String(localized: "Racoonette te remontre le portail Vendeurs, étape par étape, en commençant par le Tableau")
        }
    }
}

// MARK: - Étapes

/// Écran (onglet, ou écran poussé dans l'onglet) où une étape est montrée.
nonisolated enum TourScreen: String, Sendable, CaseIterable {
    // Familles
    case home, offerDetail, groups, pickup, impact
    // Vendeurs
    case vendorDashboard, vendorOffers, vendorTierEditor, vendorDemand, vendorRevenue

    /// Écran poussé au-dessus de la racine de son onglet.
    var isPushed: Bool { self == .offerDetail || self == .vendorTierEditor }
}

/// Étapes des visites, dans l'ordre où chaque mascotte les montre.
nonisolated enum TourStep: String, Sendable, CaseIterable {
    // MARK: Noisette
    /// Ce qu'est LeGrenier (bulle au centre : pas d'élément à montrer).
    case intro
    /// Ton groupe de quartier (Accueil).
    case homeGroup
    /// Les économies (Accueil).
    case homeSavings
    /// Les commandes en cours (Accueil).
    case homeOrders
    /// Les nouveaux lots près de chez toi (Accueil).
    case homeOffers
    /// Les paliers d'un lot : le prix baisse quand les familles se joignent (fiche du lot).
    case offerTiers
    /// Réserver une part et offrir un panier suspendu (fiche du lot).
    case offerShare
    /// Les groupes : page publique de ton groupe.
    case groups
    /// Rejoindre ou créer un groupe, carte du quartier.
    case groupsActions
    /// Code QR, créneau et hôte de la cueillette.
    case pickup
    /// Les économies, l'impact et le classement.
    case impact
    /// Le Profil : préférences, langue, revoir le tutoriel.
    case profile

    // MARK: Racoonette
    /// Ce qu'est le portail Vendeurs (bulle au centre).
    case vendorIntro
    /// Les chiffres clés du Tableau.
    case vendorStats
    /// Les lots ouverts et le badge « Minimum à risque ».
    case vendorRisk
    /// Ma vitrine : la page publique et les zones desservies.
    case vendorShop
    /// Créer un lot (onglet Lots).
    case vendorCreate
    /// L'éditeur de paliers.
    case vendorTiers
    /// Mes produits (le catalogue).
    case vendorProducts
    /// La carte de la demande.
    case vendorDemand
    /// Les revenus et les statistiques par produit.
    case vendorRevenue
    /// Le Profil du portail Vendeurs.
    case vendorProfile

    var tour: TourID {
        switch self {
        case .intro, .homeGroup, .homeSavings, .homeOrders, .homeOffers, .offerTiers, .offerShare,
             .groups, .groupsActions, .pickup, .impact, .profile:
            .noisette
        case .vendorIntro, .vendorStats, .vendorRisk, .vendorShop, .vendorCreate, .vendorTiers,
             .vendorProducts, .vendorDemand, .vendorRevenue, .vendorProfile:
            .racoonette
        }
    }

    var screen: TourScreen {
        switch self {
        case .intro, .homeGroup, .homeSavings, .homeOrders, .homeOffers: .home
        case .offerTiers, .offerShare: .offerDetail
        case .groups, .groupsActions: .groups
        case .pickup: .pickup
        // Le Profil se montre depuis l'écran où la visite est arrivée.
        case .impact, .profile: .impact
        case .vendorIntro, .vendorStats, .vendorRisk, .vendorShop: .vendorDashboard
        case .vendorCreate, .vendorProducts: .vendorOffers
        case .vendorTiers: .vendorTierEditor
        case .vendorDemand: .vendorDemand
        case .vendorRevenue, .vendorProfile: .vendorRevenue
        }
    }

    /// Faux pour les étapes qui parlent de l'app en général : bulle au centre, sans découpe.
    var expectsAnchor: Bool {
        switch self {
        // Les lignes d'un Form ne sont créées qu'une fois à l'écran : pas de cadre fiable, l'éditeur s'explique au centre.
        case .intro, .vendorIntro, .vendorTiers: false
        default: true
        }
    }

    /// Élément à montrer à la place quand celui de l'étape n'existe pas (écran vide).
    var fallback: TourStep? {
        switch self {
        case .homeOrders: .homeGroup
        case .vendorRisk: .vendorStats
        default: nil
        }
    }

    /// Où amener l'élément dans le ScrollView : en haut, la bulle se pose dessous, là où il y a de la place.
    var scrollAnchor: UnitPoint { .top }

    var title: String {
        switch self {
        case .intro: String(localized: "Bienvenue au Grenier")
        case .homeGroup: String(localized: "Ton groupe de quartier")
        case .homeSavings: String(localized: "Tes économies")
        case .homeOrders: String(localized: "Tes commandes en cours")
        case .homeOffers: String(localized: "Des lots près de chez toi")
        case .offerTiers: String(localized: "Le prix baisse avec les familles")
        case .offerShare: String(localized: "Ta part et le panier suspendu")
        case .groups: String(localized: "Ta page de groupe")
        case .groupsActions: String(localized: "Rejoindre ou créer un groupe")
        case .pickup: String(localized: "Ta cueillette")
        case .impact: String(localized: "Ton impact")
        case .profile: String(localized: "Ton profil")
        case .vendorIntro: String(localized: "Bienvenue côté producteurs")
        case .vendorStats: String(localized: "Ton tableau de bord")
        case .vendorRisk: String(localized: "Tes lots ouverts")
        case .vendorShop: String(localized: "Ta vitrine publique")
        case .vendorCreate: String(localized: "Publie un lot")
        case .vendorTiers: String(localized: "Les paliers, ta force")
        case .vendorProducts: String(localized: "Tes produits")
        case .vendorDemand: String(localized: "Où est la demande")
        case .vendorRevenue: String(localized: "Tes revenus")
        case .vendorProfile: String(localized: "Ton profil")
        }
    }

    var message: String {
        switch self {
        case .intro:
            String(localized: "LeGrenier, c'est l'achat en gros entre voisins : des producteurs d'ici vendent par lots, et plus ton groupe réserve de parts, plus le prix baisse pour tout le monde. Je te fais faire le tour !")
        case .homeGroup:
            String(localized: "Voici ton groupe : tes voisins, ton quartier et ce qui s'y passe. C'est avec eux que tu achètes en gros.")
        case .homeSavings:
            String(localized: "Ici, tu vois combien tu as déjà économisé par rapport à l'épicerie. Ça grimpe à chaque commande !")
        case .homeOrders:
            String(localized: "Tes commandes ouvertes et celles de ton groupe. Touche-en une pour suivre les paliers et ta part.")
        case .homeOffers:
            String(localized: "Les producteurs d'ici publient de nouveaux lots chaque semaine. Touche un lot pour voir son prix et ses paliers : j'en ouvre un pour toi.")
        case .offerTiers:
            String(localized: "Voici les paliers : plus de familles réservent, plus le prix par part descend. La barre montre où en est ton groupe et ce qu'il manque pour le prochain palier.")
        case .offerShare:
            String(localized: "Choisis ta quantité, puis touche Réserver : tu paies seulement à la cueillette. Tu peux aussi ajouter un panier suspendu, un petit montant qui offre un panier à une famille qui en a besoin.")
        case .groups:
            String(localized: "Chaque groupe a sa page publique : membres, commandes et producteurs. Touche le tien pour la voir.")
        case .groupsActions:
            String(localized: "Avec le bouton +, rejoins un groupe avec un code ou crée le tien. Tout près, la carte montre les groupes, les points de cueillette et les producteurs autour de toi.")
        case .pickup:
            String(localized: "Le jour de la cueillette, montre ce code QR à l'hôte, un voisin qui reçoit les lots. Juste au-dessus : ton créneau et le lieu.")
        case .impact:
            String(localized: "Tes économies, ce que ton quartier change ensemble, et plus bas le classement solidaire des arrondissements.")
        case .profile:
            String(localized: "Ici : tes préférences, la langue et « Revoir le tutoriel avec Noisette » pour me retrouver. Bonne cueillette !")
        case .vendorIntro:
            String(localized: "Ce portail te permet de vendre à des quartiers entiers : tu publies un lot avec des paliers de prix, les familles se regroupent pour les atteindre, et tu livres une seule fois par groupe.")
        case .vendorStats:
            String(localized: "Tes chiffres clés d'un coup d'œil : revenus prévus, parts réservées, familles servies et lots ouverts.")
        case .vendorRisk:
            String(localized: "Chaque carte montre où en est un lot. Si le minimum de commande risque de ne pas être atteint, un badge t'indique combien de parts manquent.")
        case .vendorShop:
            String(localized: "« Ma vitrine » est la page que les familles voient : photos, description, produits mis en avant. Tu y choisis aussi les zones desservies, les quartiers où tu livres.")
        case .vendorCreate:
            String(localized: "Touche le + dans l'onglet Lots pour publier un nouveau lot : produit, quantité, prix à l'épicerie et paliers de prix.")
        case .vendorTiers:
            String(localized: "Chaque palier baisse ton prix quand assez de parts sont réservées. La courbe montre l'effet : les familles ont tout intérêt à inviter leurs voisins !")
        case .vendorProducts:
            String(localized: "Ton catalogue : crée tes produits une seule fois et réutilise-les à chaque lot. Tu y retrouves aussi les statistiques de chaque produit.")
        case .vendorDemand:
            String(localized: "La carte montre où les familles commandent et ce qu'elles souhaitent acheter. Touche une bulle pour lire leurs souhaits et « Proposer un lot ici ».")
        case .vendorRevenue:
            String(localized: "Tes revenus prévus et tes chiffres clés, puis plus bas les ventes par produit : tu vois tout de suite ce qui marche le mieux.")
        case .vendorProfile:
            String(localized: "Ici : tes préférences, la langue et « Revoir le tutoriel avec Racoonette » pour me retrouver. Bonne vente !")
        }
    }

    var systemImage: String {
        switch self {
        case .intro: "basket.fill"
        case .homeGroup: "person.3.fill"
        case .homeSavings: "chart.line.downtrend.xyaxis"
        case .homeOrders: "cart.fill"
        case .homeOffers: "sparkles"
        case .offerTiers: "stairs"
        case .offerShare: "basket.fill"
        case .groups: "person.3.fill"
        case .groupsActions: "plus.circle.fill"
        case .pickup: "qrcode"
        case .impact: "leaf.fill"
        case .profile, .vendorProfile: "person.crop.circle.fill"
        case .vendorIntro: "storefront.fill"
        case .vendorStats: "chart.bar.fill"
        case .vendorRisk: "shippingbox.fill"
        case .vendorShop: "storefront"
        case .vendorCreate: "plus.circle.fill"
        case .vendorTiers: "stairs"
        // Le bouton « Mes produits » de la barre d'outils (tray.full.fill est « Mes disponibilités », juste à côté).
        case .vendorProducts: "basket.fill"
        case .vendorDemand: "map.fill"
        case .vendorRevenue: "dollarsign.circle.fill"
        }
    }
}

// MARK: - Machine à états

/// Où en est une visite. Pure et sans effet de bord : `GuidedTour` la persiste à chaque changement.
nonisolated struct GuidedTourMachine: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        /// La carte d'accueil de la mascotte n'a pas encore été vue.
        case welcome
        /// Visite en cours, à l'étape `index`.
        case touring(index: Int)
        /// Visite vue jusqu'au bout.
        case finished
        /// « Plus tard », « Passer » ou fermée : rien ne s'affiche jusqu'à « Revoir le tutoriel ».
        case skipped
    }

    let tour: TourID
    let steps: [TourStep]
    private(set) var phase: Phase

    init(tour: TourID = .noisette, steps: [TourStep]? = nil, phase: Phase = .welcome) {
        self.tour = tour
        let steps = steps ?? tour.steps
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

    /// « Revoir le tutoriel » : la carte d'accueil revient.
    mutating func replay() {
        phase = .welcome
    }
}

// MARK: - Activation (tests, démo)

nonisolated enum GuidedTourPolicy {
    /// Argument de lancement de Noisette (gardé pour les anciens scripts de démo).
    static let demoTourArgument = TourID.noisette.demoArgument
    /// Argument de lancement de Racoonette.
    static let demoVendorTourArgument = TourID.racoonette.demoArgument
    static let previewVariable = "XCODE_RUNNING_FOR_PREVIEWS"

    /// Pas de visite pendant les tests unitaires ou UI, dans les previews ni avec les données fake
    /// (`-useFakeData`, `-useFakeBackend`), sauf si l'argument de démo de la visite est passé.
    static func isEnabled(tour: TourID = .noisette, arguments: [String], environment: [String: String]) -> Bool {
        if arguments.contains(tour.demoArgument) { return true }
        if environment[previewVariable] == "1" { return false }
        let options = BackendLaunchOptions(arguments: arguments, environment: environment)
        return !options.isRunningTests && !options.useFakeBackend
    }

    static func replaysAtLaunch(tour: TourID = .noisette, arguments: [String]) -> Bool {
        arguments.contains(tour.demoArgument)
    }
}

// MARK: - État persistant

/// Phase d'une visite dans UserDefaults, écrite à chaque pas.
struct GuidedTourStore {
    /// Clé de Noisette (gardée pour qui l'a déjà vue).
    static let phaseKey = TourID.noisette.storageKey
    /// Ancienne version (TipKit) : carte vue. Une visite déjà vue ne revient pas après la mise à jour.
    static let legacyWelcomeSeenKey = "guidedTour.welcomeSeen"

    let defaults: UserDefaults

    func load(tour: TourID = .noisette) -> GuidedTourMachine {
        GuidedTourMachine(tour: tour, phase: storedPhase(for: tour))
    }

    func save(_ machine: GuidedTourMachine) {
        defaults.set(Self.encode(machine.phase), forKey: machine.tour.storageKey)
    }

    private func storedPhase(for tour: TourID) -> GuidedTourMachine.Phase {
        if let raw = defaults.string(forKey: tour.storageKey), let phase = Self.decode(raw) { return phase }
        // Seule Noisette existait avant TipKit : la carte déjà vue ne revient pas pour elle.
        if tour == .noisette, defaults.bool(forKey: Self.legacyWelcomeSeenKey) { return .finished }
        return .welcome
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

/// Cadre d'un élément à montrer, signalé par l'écran qui le porte.
struct TourAnchor: Equatable {
    /// Coordonnées de la fenêtre.
    var frame: CGRect
    /// Coins de la découpe : ceux de l'élément.
    var cornerRadius: CGFloat
    /// Marge autour de l'élément.
    var padding: CGFloat
}

/// Une visite guidée vivante : machine persistée + cadres des éléments à montrer.
@Observable
final class GuidedTour {
    static let noisette = GuidedTour(tour: .noisette)
    static let racoonette = GuidedTour(tour: .racoonette)

    static func instance(for tour: TourID) -> GuidedTour {
        switch tour {
        case .noisette: noisette
        case .racoonette: racoonette
        }
    }

    private convenience init(tour: TourID) {
        self.init(
            tour: tour,
            store: GuidedTourStore(defaults: .standard),
            isEnabled: GuidedTourPolicy.isEnabled(
                tour: tour,
                arguments: ProcessInfo.processInfo.arguments,
                environment: ProcessInfo.processInfo.environment
            )
        )
    }

    let tour: TourID
    let isEnabled: Bool
    private(set) var machine: GuidedTourMachine
    /// Éléments de chaque étape, signalés par `.guidedTourAnchor(_:)`.
    private(set) var anchors: [TourStep: TourAnchor] = [:]
    /// Augmente quand un défilement vers l'élément de l'étape est (re)demandé.
    private(set) var scrollTick = 0
    @ObservationIgnored private let store: GuidedTourStore

    init(tour: TourID = .noisette, store: GuidedTourStore, isEnabled: Bool) {
        self.tour = tour
        self.store = store
        self.isEnabled = isEnabled
        self.machine = store.load(tour: tour)
    }

    /// Au lancement : l'argument de démo rejoue la visite depuis la carte d'accueil. Une visite interrompue reprend où elle était.
    func configureAtLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isEnabled, GuidedTourPolicy.replaysAtLaunch(tour: tour, arguments: arguments) else { return }
        update { $0.replay() }
        // QA : `-demoTourStep 7` saute directement à l'étape d'index 7 (sans passer par la carte d'accueil).
        if let raw = arguments.firstIndex(of: "-demoTourStep").flatMap({ arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }),
           let target = Int(raw) {
            update { machine in
                machine.start()
                for _ in 0..<max(0, target) { machine.next() }
            }
        }
    }

    /// La carte d'accueil de la mascotte doit s'afficher.
    var showsWelcome: Bool { isEnabled && machine.phase == .welcome }

    /// Étape à montrer maintenant, nil hors visite.
    var currentStep: TourStep? { isEnabled ? machine.currentStep : nil }

    func start() { update { $0.start() } }
    func postpone() { update { $0.postpone() } }
    func next() { update { $0.next() } }
    func back() { update { $0.back() } }
    func skip() { update { $0.skip() } }

    /// « Revoir le tutoriel » (Profil) : la carte d'accueil revient, sans redémarrer.
    func replay() {
        guard isEnabled else { return }
        update { $0.replay() }
    }

    func anchor(for step: TourStep) -> TourAnchor? { anchors[step] }

    func updateAnchor(_ anchor: TourAnchor, for step: TourStep) {
        // Toujours retenu (une ancre se signale à son premier rendu et quand elle bouge) ;
        // seule la bulle lit ces cadres, et seulement pendant la visite.
        guard isEnabled, anchors[step] != anchor else { return }
        let isNew = anchors[step] == nil
        anchors[step] = anchor
        // L'élément de l'étape vient d'apparaître (écran chargé, fiche poussée) : on l'amène à l'écran.
        if isNew, step == currentStep { requestScroll() }
    }

    /// L'élément a disparu avec son écran : son cadre ne vaut plus rien.
    func removeAnchor(for step: TourStep) {
        guard anchors[step] != nil else { return }
        anchors[step] = nil
    }

    /// Demande aux ScrollView de l'écran d'amener l'élément de l'étape à l'écran.
    func requestScroll() { scrollTick += 1 }

    private func update(_ change: (inout GuidedTourMachine) -> Void) {
        var machine = self.machine
        change(&machine)
        guard machine != self.machine else { return }
        self.machine = machine
        store.save(machine)
    }
}

extension View {
    /// Signale à la visite guidée où est l'élément de `step` (FB-19) et lui donne son identifiant de défilement.
    /// `cornerRadius` et `padding` règlent la découpe pour qu'elle épouse l'élément. Sans effet hors visite.
    func guidedTourAnchor(_ step: TourStep, cornerRadius: CGFloat? = nil, padding: CGFloat = 6) -> some View {
        modifier(TourAnchorModifier(step: step, cornerRadius: cornerRadius, padding: padding))
    }

    /// Comme `guidedTourAnchor(_:)`, seulement quand `condition` est vraie (le premier élément d'une liste).
    @ViewBuilder
    func guidedTourAnchor(_ step: TourStep, if condition: Bool, cornerRadius: CGFloat? = nil, padding: CGFloat = 6) -> some View {
        if condition {
            guidedTourAnchor(step, cornerRadius: cornerRadius, padding: padding)
        } else {
            self
        }
    }

    /// À poser sur un ScrollView (ou un Form) : amène l'élément de l'étape en cours de `tour` à l'écran.
    /// Sans élément de ce nom dans le ScrollView, ne fait rien.
    func guidedTourScroll(_ tour: TourID) -> some View {
        modifier(TourScrollModifier(tour: GuidedTour.instance(for: tour)))
    }
}

private struct TourAnchorModifier: ViewModifier {
    let step: TourStep
    /// nil : les coins des cartes du thème.
    let cornerRadius: CGFloat?
    let padding: CGFloat
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? theme.cornerRadius
        return content
            .id(step)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                GuidedTour.instance(for: step.tour)
                    .updateAnchor(TourAnchor(frame: frame, cornerRadius: radius, padding: padding), for: step)
            }
            // Les éléments de la barre d'outils sont recréés par le système : leur cadre reste valable.
            .onDisappear { if step.isInContent { GuidedTour.instance(for: step.tour).removeAnchor(for: step) } }
    }
}

private struct TourScrollModifier: ViewModifier {
    let tour: GuidedTour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: tour.currentStep, initial: true) { _, step in scroll(proxy, step: step, after: 0.45) }
                .onChange(of: tour.scrollTick) { _, _ in scroll(proxy, step: tour.currentStep, after: 0.15) }
        }
    }

    /// Laisse le temps à l'onglet de s'afficher (et à la fiche d'être poussée) avant de défiler.
    private func scroll(_ proxy: ScrollViewProxy, step: TourStep?, after delay: Double) {
        guard let step, step.expectsAnchor else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard tour.currentStep == step else { return }
            withAnimation(reduceMotion ? nil : .smooth) {
                proxy.scrollTo(step, anchor: step.scrollAnchor)
            }
        }
    }
}
