// VolunteerDeliveryViewModel.swift
// RQ-069 (T-117) : livraison à domicile par un voisin bénévole.
// Deux côtés du même écran : le ménage (aîné ou mobilité réduite) demande et suit sa livraison ;
// un voisin bénévole voit les demandes du quartier (avec la distance), en prend, récupère la part et la livre.

import Foundation
import Observation

@Observable
@MainActor
final class VolunteerDeliveryViewModel {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case family
        case volunteer

        var id: Self { self }
        var title: String { self == .family ? "Me faire livrer" : "Livrer un voisin" }
        var systemImage: String { self == .family ? "house.fill" : "figure.walk" }
    }

    /// Une commande où le ménage a une part pas encore récupérée : candidate à la livraison.
    nonisolated struct OrderOption: Identifiable, Sendable, Hashable {
        var order: GroupOrder
        var share: Share
        var productName: String
        var shareUnit: String

        var id: String { order.id }
    }

    /// Demande ouverte vue par un bénévole, avec sa distance approximative (quartier, jamais la porte).
    nonisolated struct OpenItem: Identifiable, Sendable, Hashable {
        var request: VolunteerDelivery.Request
        /// Mètres entre le quartier du bénévole et celui du ménage ; nil si un geohash est illisible.
        var distanceMeters: Double?

        var id: String { request.id }
    }

    nonisolated struct Content: Sendable, Hashable {
        var firstName: String
        var householdName: String
        var householdGeohash: String
        var seniorMode: Bool
        var groupIds: Set<String>
        /// Demandes du ménage, en cours d'abord puis les plus récentes.
        var myRequests: [VolunteerDelivery.Request]
        /// Livraisons du bénévole : en cours d'abord.
        var myDeliveries: [VolunteerDelivery.Request]
        /// Demandes à prendre, la plus proche d'abord.
        var openItems: [OpenItem]
        var orderOptions: [OrderOption]
        /// Adresses révélées (ma demande en cours, mes livraisons en cours), par id de demande.
        var addresses: [String: VolunteerDelivery.PrivateAddress]

        var activeRequest: VolunteerDelivery.Request? {
            myRequests.first { !$0.status.isFinished || ($0.status == .delivered && $0.receiptConfirmedAt == nil) }
        }
        var pastRequests: [VolunteerDelivery.Request] {
            myRequests.filter { $0.id != activeRequest?.id }
        }
        var activeDeliveries: [VolunteerDelivery.Request] { myDeliveries.filter(\.status.isActive) }
        var completedDeliveries: [VolunteerDelivery.Request] { myDeliveries.filter { $0.status == .delivered } }
        var canTakeMore: Bool { activeDeliveries.count < VolunteerDelivery.maxActivePerVolunteer }
    }

    /// Ce que le ménage remplit dans la feuille « Demander une livraison ».
    struct Draft: Sendable, Hashable {
        var orderId: String?
        var start: Date
        var duration: TimeInterval = 2 * 3_600
        var address = ""
        var instructions = ""
        var note = ""
        var reducedMobility = false

        init(start: Date) { self.start = start }
    }

    private(set) var state: LoadState<Content> = .idle
    var mode: Mode
    /// Demande en cours d'envoi (indicateur sur la bonne carte).
    private(set) var pendingId: String?
    private(set) var isSubmitting = false
    private(set) var actionError: AppError?
    /// Augmente à chaque action réussie (haptique de succès).
    private(set) var successes = 0
    /// Livraison que le bénévole vient de remettre : déclenche la scène « Livré ! ».
    var justDelivered: VolunteerDelivery.Request?

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String
    private let groupId: String
    private let now: @Sendable () -> Date

    init(repositories: AppRepositories, userId: String, householdId: String, groupId: String,
         mode: Mode = .family, now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
        self.groupId = groupId
        self.mode = mode
        self.now = now
    }

    var isBusy: Bool { pendingId != nil || isSubmitting }

    /// Premier créneau proposé dans la feuille : demain, 10 h.
    func newDraft() -> Draft {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now())) ?? now()
        var draft = Draft(start: tomorrow.addingTimeInterval(10 * 3_600))
        draft.orderId = state.value?.orderOptions.first?.id
        return draft
    }

    func dismissError() { actionError = nil }

    // MARK: - Chargement

    func load() async {
        if state.value == nil { state = .loading }
        let repositories = repositories, userId = userId, householdId = householdId, groupId = groupId, now = now()
        do {
            state = .loaded(try await Self.content(
                repositories: repositories, userId: userId, householdId: householdId, groupId: groupId, now: now
            ))
        } catch {
            if state.value == nil { state = .failed(AppError(error)) } else { actionError = AppError(error) }
        }
    }

    nonisolated private static func content(
        repositories: AppRepositories, userId: String, householdId: String, groupId: String, now: Date
    ) async throws -> Content {
        async let userTask = repositories.users.user(id: userId)
        async let householdTask = repositories.users.household(id: householdId)
        async let groupsTask = repositories.groups.groups(ofHousehold: householdId)
        async let requestsTask = repositories.deliveries.deliveries(ofGroup: groupId)
        async let ordersTask = repositories.groupOrders.groupOrders(ofGroup: groupId)
        let user = try? await userTask
        let household = try? await householdTask
        let groupIds = Set((try? await groupsTask)?.map(\.id) ?? [groupId])
        let requests = try await requestsTask
        let orders = try await ordersTask.filter { $0.status != .cancelled }

        var options: [OrderOption] = []
        for order in orders {
            guard let share = try? await repositories.groupOrders.shares(ofGroupOrder: order.id)
                .first(where: { $0.householdId == householdId }),
                share.quantity > 0, !share.isPickedUp else { continue }
            let offer = try? await repositories.offers.offer(id: order.offerId)
            var product: Product?
            if let offer { product = try? await repositories.vendors.product(id: offer.productId) }
            options.append(OrderOption(order: order, share: share, productName: product?.name ?? "Ta commande",
                                       shareUnit: offer?.shareUnit ?? "part"))
        }

        let geohash = household?.geohash ?? ""
        let mine = requests.filter { $0.householdId == householdId }
            .sorted { ($0.status.isFinished ? 1 : 0, -$0.createdAt.timeIntervalSince1970)
                < ($1.status.isFinished ? 1 : 0, -$1.createdAt.timeIntervalSince1970) }
        let deliveries = VolunteerDelivery.deliveries(of: householdId, in: requests)
        let open = VolunteerDelivery.openRequests(groupId: groupId, for: householdId, in: requests, now: now)
            .map { OpenItem(request: $0, distanceMeters: Geohash.distanceMeters(from: geohash, to: $0.geohash)) }
            .sorted { ($0.distanceMeters ?? .infinity, $0.request.window.start) < ($1.distanceMeters ?? .infinity, $1.request.window.start) }

        var addresses: [String: VolunteerDelivery.PrivateAddress] = [:]
        let revealable = mine.filter { !$0.status.isFinished } + deliveries.filter(\.status.isActive)
        for request in revealable {
            if let address = try? await repositories.deliveries.address(
                ofDelivery: request.id, groupOrderId: request.groupOrderId, viewerHouseholdId: householdId
            ) {
                addresses[request.id] = address
            }
        }

        let name = user?.displayName ?? household?.name ?? "Moi"
        return Content(
            firstName: name.split(separator: " ").first.map(String.init) ?? name,
            householdName: household?.name ?? name,
            householdGeohash: geohash,
            seniorMode: user?.seniorMode ?? false,
            groupIds: groupIds,
            myRequests: mine,
            myDeliveries: deliveries,
            openItems: open,
            orderOptions: options,
            addresses: addresses
        )
    }

    // MARK: - Ménage

    /// Valide la demande (`VolunteerDelivery.request`) puis l'enregistre. Renvoie le message d'erreur à afficher
    /// sous le formulaire, ou nil si la demande est partie.
    func submit(_ draft: Draft) async -> String? {
        guard let content = state.value, !isSubmitting else { return nil }
        guard let option = content.orderOptions.first(where: { $0.id == draft.orderId }) else {
            return "Choisis la commande à te faire livrer."
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let id = "delivery-\(UUID().uuidString.lowercased())"
        let input = VolunteerDelivery.NewRequest(
            id: id, groupId: groupId, order: option.order, share: option.share,
            householdName: content.householdName, householdGeohash: content.householdGeohash,
            window: .init(start: draft.start, end: draft.start.addingTimeInterval(draft.duration)),
            seniorMode: content.seniorMode, reducedMobility: draft.reducedMobility,
            address: draft.address, instructions: draft.instructions, note: draft.note
        )
        do {
            let (request, address) = try VolunteerDelivery.request(input, existing: content.myRequests, now: now())
            try await repositories.deliveries.createDelivery(request, address: address)
            successes += 1
            await load()
            return nil
        } catch {
            return AppError(error).message
        }
    }

    func cancel(_ request: VolunteerDelivery.Request) async {
        await perform(request) { repositories, householdId in
            try await repositories.deliveries.cancelDelivery(
                id: request.id, groupOrderId: request.groupOrderId, householdId: householdId
            )
        }
    }

    func confirmReceipt(_ request: VolunteerDelivery.Request) async {
        await perform(request) { repositories, householdId in
            try await repositories.deliveries.confirmReceipt(
                id: request.id, groupOrderId: request.groupOrderId, householdId: householdId
            )
        }
    }

    // MARK: - Bénévole

    func claim(_ request: VolunteerDelivery.Request) async {
        guard let content = state.value else { return }
        let name = content.firstName, groups = content.groupIds
        await perform(request) { repositories, householdId in
            try await repositories.deliveries.claimDelivery(
                id: request.id, groupOrderId: request.groupOrderId, volunteerHouseholdId: householdId,
                volunteerName: name, volunteerGroupIds: groups
            )
        }
    }

    func release(_ request: VolunteerDelivery.Request) async {
        await perform(request) { repositories, householdId in
            try await repositories.deliveries.releaseDelivery(
                id: request.id, groupOrderId: request.groupOrderId, volunteerHouseholdId: householdId
            )
        }
    }

    func startRoute(_ request: VolunteerDelivery.Request) async {
        await perform(request) { repositories, householdId in
            try await repositories.deliveries.startRoute(
                id: request.id, groupOrderId: request.groupOrderId, volunteerHouseholdId: householdId
            )
        }
    }

    func markDelivered(_ request: VolunteerDelivery.Request) async {
        let delivered = await perform(request) { repositories, householdId in
            try await repositories.deliveries.markDelivered(
                id: request.id, groupOrderId: request.groupOrderId, volunteerHouseholdId: householdId
            )
        }
        if let delivered { justDelivered = delivered }
    }

    // MARK: - Interne

    @discardableResult
    private func perform(
        _ request: VolunteerDelivery.Request,
        _ action: @Sendable (AppRepositories, String) async throws -> VolunteerDelivery.Request
    ) async -> VolunteerDelivery.Request? {
        guard !isBusy else { return nil }
        pendingId = request.id
        actionError = nil
        defer { pendingId = nil }
        do {
            let updated = try await action(repositories, householdId)
            successes += 1
            await load()
            return updated
        } catch {
            actionError = AppError(error)
            await load()
            return nil
        }
    }
}
