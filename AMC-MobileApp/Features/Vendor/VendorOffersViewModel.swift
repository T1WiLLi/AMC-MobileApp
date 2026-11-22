// VendorOffersViewModel.swift
// Gestion des lots du vendeur (T-064, RQ-036, RQ-037) : lots par section, pause, reprise, retrait, duplication.
//
// Usage dans une vue :
//   @State private var model = VendorOffersViewModel(repositories: context.repositories, vendorId: context.vendorId)
//   .task { await model.load() }  ·  .refreshable { await model.refresh() }
//   switch model.state { case .loaded(let sections): ForEach(sections) { section in Section(section.title) { … } } }
//   Actions : `await model.pause(offerId:)`, `resume(offerId:)`, `withdraw(offerId:)`, `duplicate(offerId:)`.
//   `model.actionError` pour l'alerte si une action est refusée ; `model.canPause(_:)`… pour griser les boutons.
//
// Le modèle n'a pas de statut « en pause » : un lot en pause est un lot `draft` (absent du fil des familles,
// `openGroupOrder` refuse d'y ouvrir une commande). Les brouillons (lots dupliqués) partagent donc cette section.

import Foundation
import Observation

@Observable @MainActor
final class VendorOffersViewModel {
    /// Section de la liste.
    nonisolated enum SectionKind: String, Sendable, Hashable, CaseIterable, Identifiable {
        /// `active`
        case active
        /// `draft` : en pause ou brouillon.
        case paused
        /// `closed` ou `cancelled`.
        case ended

        var id: String { rawValue }

        var title: String {
            switch self {
            case .active: String(localized: "Actifs")
            case .paused: String(localized: "En pause et brouillons")
            case .ended: String(localized: "Terminés et retirés")
            }
        }

        static func of(_ status: Offer.Status) -> SectionKind {
            switch status {
            case .active: .active
            case .draft: .paused
            case .closed, .cancelled: .ended
            }
        }
    }

    /// Un lot du vendeur, avec son produit et la demande engagée.
    nonisolated struct OfferRow: Identifiable, Sendable, Hashable {
        var offer: Offer
        /// Produit du lot ; nil s'il est introuvable.
        var product: Product?
        /// Parts engagées, toutes commandes du lot confondues (hors annulées), groupes publics et privés
        /// (via `VendorRepositoryQueries.linkedGroupOrders(ofOffers:in:)` : une commande sans groupe est ignorée).
        var committedShares: Int
        /// Commandes encore ouvertes (`open` ou `reached`).
        var liveOrderCount: Int
        /// Commandes clôturées ou livrées : leurs prix sont figés.
        var confirmedOrderCount: Int

        var id: String { offer.id }
        var deadline: Date { offer.deadline }
        var status: Offer.Status { offer.status }
        /// Nom du produit, ou l'unité de part à défaut.
        var productName: String { product?.name ?? offer.shareUnit }
        var fillFraction: Double {
            offer.totalShares > 0 ? min(1, Double(committedShares) / Double(offer.totalShares)) : 0
        }
    }

    /// Une section non vide de la liste.
    nonisolated struct OfferSection: Identifiable, Sendable, Hashable {
        var kind: SectionKind
        /// Actifs et en pause : date limite croissante ; terminés : plus récents d'abord.
        var rows: [OfferRow]

        var id: SectionKind { kind }
        var title: String { kind.title }
    }

    /// Sections non vides, dans l'ordre Actifs, En pause, Terminés ; `.empty` si le vendeur n'a aucun lot.
    private(set) var state: LoadState<[OfferSection]> = .idle
    /// Dernière action refusée ou échouée ; remis à nil au début de chaque action.
    var actionError: AppError?
    /// Lot sur lequel une action est en cours (pour un indicateur sur la ligne).
    private(set) var busyOfferId: String?
    /// Dernier lot créé par `duplicate`, pour ouvrir l'éditeur dessus.
    private(set) var lastDuplicatedOffer: Offer?

    let vendorId: String

    private let repositories: AppRepositories
    private let now: @Sendable () -> Date

    /// Décalage de la date limite d'un lot dupliqué.
    nonisolated static let duplicateDeadlineShift: TimeInterval = 7 * 86_400

    init(repositories: AppRepositories, vendorId: String, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.now = now
    }

    // MARK: Dérivés

    var sections: [OfferSection] { state.value ?? [] }
    var rows: [OfferRow] { sections.flatMap(\.rows) }

    func row(offerId: String) -> OfferRow? { rows.first { $0.id == offerId } }
    func section(_ kind: SectionKind) -> OfferSection? { sections.first { $0.kind == kind } }

    func canPause(_ row: OfferRow) -> Bool { (try? checkPause(row)) != nil }
    func canResume(_ row: OfferRow) -> Bool { (try? checkResume(row)) != nil }
    func canWithdraw(_ row: OfferRow) -> Bool { (try? checkWithdraw(row)) != nil }

    // MARK: Chargement

    func load() async {
        if state.value == nil { state = .loading }
        await reload()
    }

    func refresh() async { await reload() }

    private func reload() async {
        do {
            state = .from(try await fetchSections())
        } catch {
            state = .failed(AppError(error))
        }
    }

    private func fetchSections() async throws -> [OfferSection] {
        let offers = try await repositories.offers.offers(ofVendor: vendorId)
        let products = try await repositories.vendors.products(ofVendor: vendorId)
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var linked = try await VendorRepositoryQueries.linkedGroupOrders(
            ofOffers: offers.map(\.id), in: repositories, statuses: Set(GroupOrder.Status.allCases)
        )
        // E21-2 (RQ-053 a) : les commandes encore ouvertes après la date limite sont fermées à l'ouverture de l'écran.
        if await closeDueOrders(linked.map(\.order), offers: offers) {
            linked = try await VendorRepositoryQueries.linkedGroupOrders(
                ofOffers: offers.map(\.id), in: repositories, statuses: Set(GroupOrder.Status.allCases)
            )
        }
        let ordersByOffer = Dictionary(grouping: linked.map(\.order), by: \.offerId)

        let rows: [OfferRow] = offers.map { offer in
            let orders = ordersByOffer[offer.id] ?? []
            let counted = orders.filter { $0.status != .cancelled }
            return OfferRow(
                offer: offer,
                product: productsById[offer.productId],
                committedShares: counted.reduce(0) { $0 + $1.committedShares },
                liveOrderCount: orders.filter(TierEngine.isOpen).count,
                confirmedOrderCount: orders.filter { $0.status == .closed || $0.status == .delivered }.count
            )
        }

        return SectionKind.allCases.compactMap { kind in
            var sectionRows = rows.filter { SectionKind.of($0.status) == kind }
            guard !sectionRows.isEmpty else { return nil }
            if kind == .ended {
                sectionRows.sort { $0.deadline > $1.deadline }
            } else {
                sectionRows.sort { $0.deadline < $1.deadline }
            }
            return OfferSection(kind: kind, rows: sectionRows)
        }
    }

    /// Tente la clôture automatique de chaque commande échue ; une course perdue (`.orderClosed`) ou un refus
    /// est ignoré. Vrai si au moins une commande a changé (à relire).
    private func closeDueOrders(_ orders: [GroupOrder], offers: [Offer]) async -> Bool {
        let offersById = Dictionary(offers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let date = now()
        var changed = false
        for order in orders {
            guard let offer = offersById[order.offerId],
                  ClosurePolicy.shouldAttemptAutomaticClosure(order: order, offer: offer, now: date) else { continue }
            do {
                try await repositories.groupOrders.closeGroupOrder(id: order.id, trigger: .automatic)
                changed = true
            } catch AppError.orderClosed {
                changed = true
            } catch {
                continue
            }
        }
        return changed
    }

    // MARK: Actions

    /// Met un lot actif en pause (statut `draft`) : il disparaît du fil des familles.
    /// Refusé si la date limite est passée (la clôture est en cours).
    func pause(offerId: String) async {
        await perform(offerId: offerId) { row in
            try self.checkPause(row)
            var offer = row.offer
            offer.status = .draft
            try await self.repositories.offers.saveOffer(offer)
        }
    }

    /// Republie un lot en pause ou un brouillon (statut `active`).
    /// Refusé si la date limite est passée ou si le lot n'a aucun palier.
    func resume(offerId: String) async {
        await perform(offerId: offerId) { row in
            try self.checkResume(row)
            var offer = row.offer
            offer.status = .active
            try await self.repositories.offers.saveOffer(offer)
        }
    }

    /// Retire un lot (statut `cancelled`). Refusé si des commandes sont déjà confirmées (prix figés),
    /// ou si le lot est déjà terminé.
    func withdraw(offerId: String) async {
        await perform(offerId: offerId) { row in
            try self.checkWithdraw(row)
            var offer = row.offer
            offer.status = .cancelled
            try await self.repositories.offers.saveOffer(offer)
        }
    }

    /// Crée un brouillon à partir d'un lot : nouvel identifiant, mêmes paliers, parts et zones,
    /// date limite décalée de 7 jours (au moins 7 jours après maintenant). Renvoie le brouillon, nil en cas d'échec.
    @discardableResult
    func duplicate(offerId: String) async -> Offer? {
        var created: Offer?
        await perform(offerId: offerId) { row in
            let source = row.offer
            let shifted = source.deadline.addingTimeInterval(Self.duplicateDeadlineShift)
            let current = self.now()
            var copy = source
            copy.id = "offer-\(UUID().uuidString.lowercased())"
            copy.status = .draft
            copy.deadline = shifted > current ? shifted : current.addingTimeInterval(Self.duplicateDeadlineShift)
            try await self.repositories.offers.saveOffer(copy)
            created = copy
        }
        if let created { lastDuplicatedOffer = created }
        return created
    }

    // MARK: Règles

    private func checkPause(_ row: OfferRow) throws(AppError) {
        guard row.status == .active else {
            throw .invalidInput(String(localized: "Seul un lot actif peut être mis en pause."))
        }
        guard row.deadline > now() else {
            throw .invalidInput(String(localized: "La date limite de ce lot est passée : il ne peut plus être mis en pause."))
        }
    }

    private func checkResume(_ row: OfferRow) throws(AppError) {
        guard row.status == .draft else {
            throw .invalidInput(String(localized: "Seul un lot en pause ou un brouillon peut être republié."))
        }
        guard !row.offer.tiers.isEmpty else {
            throw .invalidInput(String(localized: "Ajoute au moins un palier de prix avant de republier ce lot."))
        }
        guard row.deadline > now() else {
            throw .invalidInput(String(localized: "La date limite de ce lot est passée : change-la avant de le republier."))
        }
    }

    private func checkWithdraw(_ row: OfferRow) throws(AppError) {
        guard row.status == .active || row.status == .draft else {
            throw .invalidInput(String(localized: "Ce lot est déjà terminé ou retiré."))
        }
        guard row.confirmedOrderCount == 0 else {
            throw .invalidInput(
                String(localized: "Des commandes de ce lot sont déjà confirmées : il ne peut plus être retiré.")
            )
        }
    }

    /// Exécute une action sur un lot, puis recharge la liste. Les erreurs vont dans `actionError`.
    private func perform(offerId: String, _ action: (OfferRow) async throws -> Void) async {
        actionError = nil
        busyOfferId = offerId
        defer { busyOfferId = nil }
        do {
            guard let row = row(offerId: offerId) else { throw AppError.notFound }
            guard row.offer.vendorId == vendorId else { throw AppError.permissionDenied }
            try await action(row)
        } catch {
            actionError = AppError(error)
        }
        await reload()
    }
}
