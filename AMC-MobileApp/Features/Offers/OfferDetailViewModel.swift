// OfferDetailViewModel.swift
// F3 Fiche d'un lot et choix de part, F4 Palier franchi (T-019).
// La quantité est en parts (`Offer.shareUnit`, ex. « sac de 10 kg ») ; les prix sont par part.
//
// Temps réel (T-096, S-05) : dans l'écran,
//     .task { await viewModel.load(); await viewModel.observe() }
// `observe()` suit la commande du groupe (parts, ménages, palier, prix, économie) et s'arrête avec la tâche.
// Quand une AUTRE famille fait franchir un palier pendant l'écoute, `tierUnlockCount` augmente de 1 et
// `liveUnlock` contient la célébration à montrer (puis `dismissLiveUnlock()`), par exemple :
//     .onChange(of: viewModel.tierUnlockCount) { … }   ou une feuille liée à `viewModel.liveUnlock != nil`
// Sa propre réservation continue de remplir `celebration` (pas `liveUnlock`). Une écoute coupée garde les
// données affichées et met `isLive` à false (pas d'écran d'erreur).

import Foundation
import Observation

@Observable
@MainActor
final class OfferDetailViewModel {
    nonisolated struct Content: Sendable, Hashable {
        var offer: Offer
        var product: Product
        var vendor: Vendor
        /// Commande du groupe sur ce lot, nil si personne du groupe n'a encore réservé.
        var groupOrder: GroupOrder?
        /// Parts déjà réservées par le ménage (0 si aucune).
        var myShareQuantity: Int
        /// T-181 : panier suspendu déjà enregistré avec la part du ménage (0 = aucun).
        var mySuspendedCents: Cents = 0
        /// Sans commande du groupe : la première réservation l'ouvrira (lot actif, date limite future, ménage dans un groupe).
        var canStartOrder: Bool = false
        /// E21-2 : part du ménage telle qu'enregistrée (prix final et paiement après la clôture), nil sans part.
        var myShare: Share?
        /// E21-2 : le bouton « Fermer la commande » est visible (`ClosurePolicy.canClose`).
        var canClose: Bool = false

        var committedShares: Int { groupOrder?.committedShares ?? 0 }
        /// Prix, palier et économie actuels du groupe.
        var pricing: OfferPricing { OfferPricing(offer: offer, product: product, committedShares: committedShares) }
        /// Parts encore disponibles dans le lot (en plus de celles du ménage).
        var remainingShares: Int { max(0, offer.totalShares - committedShares) }
        /// Le groupe peut encore modifier les parts.
        var isOpen: Bool { groupOrder.map(OfferSummaryLoader.isActive) ?? canStartOrder }
    }

    /// Ce que montre F4 quand la réservation fait franchir un palier.
    nonisolated struct TierCelebration: Sendable, Hashable {
        /// Numéro du palier débloqué (1 = premier) et nombre de paliers.
        var tierNumber: Int
        var tierCount: Int
        /// Prix d'une part avant et après (« 11,50 $ → 9,90 $ »).
        var previousPriceCents: Cents
        var newPriceCents: Cents
        /// Parts engagées par le groupe après la réservation.
        var committedShares: Int
        /// Part du ménage, son total au nouveau prix et son économie vs l'épicerie.
        var myQuantity: Int
        var myTotalCents: Cents
        var mySavingsCents: Cents

        var isLastTier: Bool { tierNumber == tierCount }
    }

    /// E21-3 : feuille « Réserver = enregistrer sa carte » montrée avant la première réservation.
    /// Rien n'est débité : le montant est un plafond (prix du palier atteint avec la part, plus le don).
    nonisolated struct CardRegistration: Sendable, Hashable, Identifiable {
        /// Parts que le ménage s'apprête à réserver.
        var quantity: Int
        /// « Tu paieras au plus X $ » : `PaymentPot.maxPriceCents` avec la part, plus le panier suspendu.
        var maxPriceCents: Cents
        /// Panier suspendu choisi (0 = aucun), compris dans `maxPriceCents`.
        var donationCents: Cents
        /// `PaymentSimulator.methodLabel` (« Apple Pay (démo) »).
        var methodLabel: String

        var id: Self { self }
    }

    private(set) var state: LoadState<Content> = .idle
    /// Quantité choisie (en parts), liée au `Picker` « Ta part ».
    var selectedQuantity: Int = 1
    /// T-181 : panier suspendu choisi avant de réserver (0 = aucun), enregistré avec la part.
    var suspendedCents: Cents = 0
    /// Montants proposés par la puce « + Panier suspendu » : 5, 10 ou 20 $.
    static let suspendedChoices: [Cents] = [500, 1_000, 2_000]
    /// Réservation ou annulation en cours (désactive le bouton principal).
    private(set) var isSaving = false
    /// Dernière erreur d'une action ; remise à nil par la vue.
    var actionError: AppError?
    /// Non nil quand la dernière réservation a franchi un palier : la vue présente F4, puis appelle `dismissCelebration()`.
    private(set) var celebration: TierCelebration?
    /// L'écoute en direct de la commande tourne (`observe()`). Repasse à false quand elle s'arrête ou échoue.
    private(set) var isLive = false
    /// +1 chaque fois qu'une autre famille fait monter le palier pendant l'écoute (jamais à la première émission).
    private(set) var tierUnlockCount = 0
    /// Numéro (1 = premier) du dernier palier franchi en direct par une autre famille.
    private(set) var lastUnlockedTierNumber: Int?
    /// Célébration à montrer pour le palier franchi en direct ; remise à nil par `dismissLiveUnlock()`.
    private(set) var liveUnlock: TierCelebration?
    /// E21-2 : fermeture de la commande en cours (désactive le bouton « Fermer la commande »).
    private(set) var isClosing = false
    /// E21-2 : dernière clôture faite depuis cet écran (bouton ou automatique), pour l'haptique et le message.
    private(set) var lastClosure: GroupOrderClosure?
    /// E21-3 : feuille d'enregistrement de la carte à présenter, nil sinon (`requestReserve()`).
    private(set) var cardRegistration: CardRegistration?
    /// E21-3 : la carte a été enregistrée pendant cette visite de la fiche (rien n'est persisté) :
    /// les changements de quantité suivants ne remontrent pas la feuille.
    private(set) var hasRegisteredCard = false

    private let repositories: AppRepositories
    private let offerId: String
    private let householdId: String
    private let groupId: String?
    /// E21-2 : compte connecté, pour savoir s'il peut fermer la commande (coordonnateur ou vendeur du lot).
    private let userId: String
    /// Profil et coordonnateurs du groupe lus au chargement : ce que `ClosurePolicy` vérifie au moment de fermer.
    private var closer: (user: AppUser, groupCoordinatorIds: [String])?
    private let now: @Sendable () -> Date
    /// T-187 : consultation du lot d'un groupe dont le ménage n'est pas membre (fiche publique du groupe).
    /// On montre la commande de CE groupe (produit, paliers, avancement) sans lire de part (réservées aux membres
    /// par les règles) et sans jamais réserver ni ouvrir de commande.
    let isReadOnly: Bool

    /// `groupId` : groupe du ménage, pour trouver sa commande sur ce lot (`nil` = consultation seule).
    /// `isReadOnly` : `groupId` est le groupe visité (pas celui du ménage) ; aucune réservation possible.
    init(repositories: AppRepositories, offerId: String, householdId: String, groupId: String?,
         isReadOnly: Bool = false, userId: String = "", now: @escaping @Sendable () -> Date = { .now }) {
        self.repositories = repositories
        self.offerId = offerId
        self.householdId = householdId
        self.groupId = groupId
        self.isReadOnly = isReadOnly
        self.userId = userId
        self.now = now
    }

    // MARK: Valeurs dérivées pour la vue

    /// Prix actuel du groupe (sans la sélection).
    var pricing: OfferPricing? { state.value?.pricing }

    /// Prix si la quantité choisie remplaçait la part actuelle du ménage (montre le palier qui tomberait).
    var projectedPricing: OfferPricing? {
        guard let content = state.value else { return nil }
        return content.pricing.with(committedShares: projectedCommittedShares(content))
    }

    /// Choix proposés dans le `Picker` (1, 2, 3 parts), limités à ce qui reste dans le lot.
    var quantityOptions: [Int] {
        guard let content = state.value else { return [] }
        let maximum = content.remainingShares + content.myShareQuantity
        return [1, 2, 3].filter { $0 <= maximum }
    }

    /// Total de la quantité choisie au prix projeté (« 26,00 $ »).
    var selectedTotalCents: Cents { projectedPricing?.totalCents(forShares: selectedQuantity) ?? 0 }

    /// Part choisie + panier suspendu, au prix du palier qu'atteindrait le groupe avec cette part.
    var selectedTotalWithBasketCents: Cents { selectedTotalCents + suspendedCents }

    /// E21-3 : « Tu paieras au plus X $ » pour la quantité choisie : `PaymentPot.maxPriceCents` au palier atteint
    /// avec cette part (le prix ne fait que baisser ensuite), plus le panier suspendu choisi.
    var selectedMaxPriceCents: Cents {
        guard let content = state.value else { return 0 }
        return Self.maxPriceCents(quantity: selectedQuantity, content: content,
                                  committedShares: projectedCommittedShares(content)) + suspendedCents
    }

    /// E21-3 : plafond de la part déjà réservée tant que la commande est ouverte (nil sinon) :
    /// « Tu paieras au plus X $ · prix final à la clôture ». Suit le palier en direct (`observe()`).
    var reservedMaxPriceCents: Cents? {
        guard let content = state.value, content.myShareQuantity > 0, content.isOpen,
              content.groupOrder != nil else { return nil }
        return Self.maxPriceCents(quantity: content.myShareQuantity, content: content,
                                  committedShares: content.committedShares) + content.mySuspendedCents
    }

    /// E21-4 : part du ménage après la clôture (payée, refusée, commande annulée) ; nil tant que c'est ouvert.
    var settlement: ShareSettlement? {
        guard let content = state.value else { return nil }
        return ShareSettlement.make(order: content.groupOrder, share: content.myShare,
                                    groceryPricePerShareCents: content.product.referenceGroceryPriceCents)
    }

    /// E21-4 : reçu de la part payée (lot, quantité, prix unitaire final, subvention, don, total, commande) ;
    /// nil si la part n'est pas payée. Le paiement de la dernière clôture faite ici ajoute sa date.
    var receipt: Receipt? {
        guard let content = state.value, settlement?.isPaid == true, let share = content.myShare,
              let order = content.groupOrder else { return nil }
        let payment = lastClosure?.payments.first { $0.householdId == share.householdId && $0.status == .succeeded }
        return try? Receipt.make(
            share: share, order: order, offer: content.offer, productName: content.product.name,
            referencePricePerShareCents: content.product.referenceGroceryPriceCents, payment: payment
        )
    }

    /// La feuille de la carte s'ouvre au prochain « Réserver » : première part du ménage sur cette commande
    /// et carte pas encore enregistrée pendant cette visite.
    var needsCardRegistration: Bool {
        guard let content = state.value else { return false }
        return content.myShareQuantity == 0 && !hasRegisteredCard
    }

    /// `PaymentPot.maxPriceCents` sur la commande du groupe, ou sur une commande pas encore ouverte.
    private static func maxPriceCents(quantity: Int, content: Content, committedShares: Int) -> Cents {
        var order = content.groupOrder ?? GroupOrder(
            id: "", groupId: "", offerId: content.offer.id, status: .open, currentTierIndex: nil,
            committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: []
        )
        order.committedShares = max(0, committedShares)
        return PaymentPot.maxPriceCents(quantity: quantity, offer: content.offer, order: order)
    }

    /// Touche une puce : la même puce une deuxième fois retire le panier suspendu.
    func toggleSuspended(_ cents: Cents) {
        suspendedCents = suspendedCents == cents ? 0 : cents
    }

    /// Économie de la quantité choisie vs l'épicerie (« Tu économises 15 $ sur ta part »).
    var selectedSavingsCents: Cents { projectedPricing?.savingsCents(forShares: selectedQuantity) ?? 0 }

    /// La quantité choisie fait franchir un palier (pour annoncer « Ta part débloque le palier »).
    var selectionUnlocksTier: Bool {
        guard let pricing, let projectedPricing else { return false }
        return projectedPricing.tierNumber > pricing.tierNumber
    }

    /// Le bouton « Réserver » est actif.
    var canReserve: Bool {
        guard !isReadOnly, let content = state.value, content.isOpen, !isSaving else { return false }
        guard selectedQuantity > 0, quantityOptions.contains(selectedQuantity) else { return false }
        return selectedQuantity != content.myShareQuantity
            || (content.myShareQuantity > 0 && suspendedCents != content.mySuspendedCents)
    }

    // MARK: Actions

    func load() async {
        if state.value == nil { state = .loading }
        await fetch()
        // RQ-053 (a) : premier appareil qui ouvre la commande après la date limite, il la ferme.
        if await closeAutomaticallyIfDue() { await fetch() }
    }

    private func fetch() async {
        let repositories = repositories, offerId = offerId, householdId = householdId, groupId = groupId
        let isReadOnly = isReadOnly
        let previous = state.value
        let result: LoadState<Content> = await .run {
            let offer = try await repositories.offers.offer(id: offerId)
            let product = try await repositories.vendors.product(id: offer.productId)
            let vendor = try await repositories.vendors.vendor(id: offer.vendorId)
            var order: GroupOrder?
            var myQuantity = 0
            var mySuspended: Cents = 0
            var myShare: Share?
            if let groupId {
                order = try await repositories.groupOrders.groupOrders(ofGroup: groupId)
                    .first { $0.offerId == offerId }
                if let order, !isReadOnly {
                    myQuantity = try await OfferSummaryLoader.shareQuantity(
                        householdId: householdId, groupOrderId: order.id, repositories: repositories
                    )
                    if myQuantity > 0 {
                        myShare = try await repositories.groupOrders.share(ofHousehold: householdId, inGroupOrder: order.id)
                        mySuspended = myShare?.suspendedAmountCents ?? 0
                    }
                }
            }
            let canStartOrder = !isReadOnly && order == nil && groupId != nil && offer.status == .active
                && offer.deadline > .now
            var content = Content(
                offer: offer, product: product, vendor: vendor, groupOrder: order, myShareQuantity: myQuantity,
                mySuspendedCents: mySuspended, canStartOrder: canStartOrder, myShare: myShare
            )
            // Le bouton « Fermer la commande » (barre du bas) ne disparaît pas le temps de la relecture : `loadCloser`
            // le recalcule juste après, sans faire sauter la mise en page.
            content.canClose = previous?.canClose ?? false
            return content
        }
        // T-199 (R-c) : un rechargement qui échoue ou est annulé (retour d'un autre écran) garde le contenu affiché ;
        // passer à `.failed` ou `.loading` recréerait le `ScrollView` et le ramènerait en haut.
        if previous != nil, case .failed = result { return }
        state = result
        await loadCloser()
        if let content = state.value, content.myShareQuantity > 0 {
            // E21-3 : une part existante veut dire que la carte a déjà été enregistrée à la réservation.
            hasRegisteredCard = true
            selectedQuantity = content.myShareQuantity
            suspendedCents = content.mySuspendedCents
        }
    }

    /// E21-2 : profil du compte et coordonnateurs de son groupe, puis `canClose`. Une lecture ratée cache le bouton, sans erreur.
    private func loadCloser() async {
        guard var content = state.value, let order = content.groupOrder, !isReadOnly, !userId.isEmpty else { return }
        if closer == nil {
            guard let user = try? await repositories.users.user(id: userId) else { return }
            guard let group = try? await repositories.groups.group(id: order.groupId) else { return }
            closer = (user, group.coordinatorIds)
        }
        guard let closer else { return }
        content.canClose = ClosurePolicy.canClose(
            user: closer.user, groupCoordinatorIds: closer.groupCoordinatorIds, offer: content.offer, order: order
        )
        state = .loaded(content)
    }

    /// RQ-053 (a) : ferme la commande si sa date limite est passée et qu'elle est encore ouverte.
    /// Une course perdue (`.orderClosed` : un autre appareil l'a fermée) ou un refus des règles est ignoré.
    /// - Returns: true si la commande a été fermée (ou l'était déjà) : l'écran se relit.
    private func closeAutomaticallyIfDue() async -> Bool {
        guard let content = state.value, let order = content.groupOrder,
              ClosurePolicy.shouldAttemptAutomaticClosure(order: order, offer: content.offer, now: now()) else { return false }
        do {
            lastClosure = try await repositories.groupOrders.closeGroupOrder(id: order.id, trigger: .automatic)
            ShareActivity.shared.shareDidChange()
            return true
        } catch AppError.orderClosed {
            return true
        } catch {
            return false
        }
    }

    /// E21-2 (RQ-053 b) : « Fermer la commande ». Les familles paient leur part au prix final ; sous le minimum,
    /// la commande est annulée et personne n'est débité. L'écran se relit ensuite (statut, prix final).
    func closeOrder() async {
        guard let content = state.value, let order = content.groupOrder, content.canClose,
              let closer, !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        do {
            lastClosure = try await repositories.groupOrders.closeGroupOrder(
                id: order.id, trigger: .manual(user: closer.user, groupCoordinatorIds: closer.groupCoordinatorIds)
            )
            ShareActivity.shared.shareDidChange()
        } catch AppError.orderClosed {
            // Déjà fermée (autre appareil, date limite) : on relit simplement la commande.
        } catch {
            actionError = AppError(error)
        }
        await fetch()
    }

    /// Bouton « Réserver » : à la première part, montre d'abord la feuille de la carte (`cardRegistration`) ;
    /// sinon réserve tout de suite.
    func requestReserve() async {
        guard canReserve else { return }
        if needsCardRegistration {
            cardRegistration = CardRegistration(
                quantity: selectedQuantity,
                maxPriceCents: selectedMaxPriceCents,
                donationCents: suspendedCents,
                methodLabel: PaymentSimulator.methodLabel
            )
            return
        }
        await reserve()
    }

    /// « Enregistrer et réserver » dans la feuille : la carte est retenue pour la visite, puis la part est réservée.
    /// Aucun montant n'est retenu.
    func confirmCardRegistration() async {
        guard cardRegistration != nil else { return }
        cardRegistration = nil
        hasRegisteredCard = true
        await reserve()
    }

    /// « Annuler » dans la feuille : rien n'est réservé ni enregistré.
    func dismissCardRegistration() {
        cardRegistration = nil
    }

    /// Réserve `selectedQuantity` parts (ou change la part). Si un palier tombe, remplit `celebration`.
    func reserve() async {
        await setShare(quantity: selectedQuantity)
    }

    /// Retire la part du ménage.
    func cancelShare() async {
        await setShare(quantity: 0)
        if actionError == nil { suspendedCents = 0 }
    }

    func dismissCelebration() {
        celebration = nil
    }

    func dismissLiveUnlock() {
        liveUnlock = nil
    }

    /// Suit la commande en temps réel (autres familles qui réservent). À lancer dans `.task` après `load()` ;
    /// s'arrête avec la tâche. Sans commande du groupe sur ce lot, rend la main tout de suite.
    func observe() async {
        guard let orderId = state.value?.groupOrder?.id else { return }
        await follow(await repositories.groupOrders.observeGroupOrder(id: orderId))
    }

    /// Applique chaque émission de `updates` (exposé pour les tests). La première émission sert de référence :
    /// elle met l'écran à jour sans célébrer.
    func follow(_ updates: AsyncThrowingStream<GroupOrder, any Error>) async {
        isLive = true
        defer { isLive = false }
        var isFirst = true
        do {
            for try await order in updates {
                let wasOpen = state.value?.isOpen ?? false
                apply(order, celebrate: !isFirst)
                isFirst = false
                // E21-4 : fermée ailleurs (autre appareil, date limite) : on relit la part (prix final, paiement).
                if wasOpen, state.value?.groupOrder?.id == order.id, !TierEngine.isOpen(order) {
                    await fetch()
                }
            }
        } catch {
            // Écoute coupée : on garde les dernières données ; `isLive` repasse à false.
        }
    }

    private func apply(_ order: GroupOrder, celebrate: Bool) {
        guard var content = state.value, content.groupOrder?.id == order.id else { return }
        let before = content.pricing
        content.groupOrder = order
        if !TierEngine.isOpen(order) { content.canClose = false }
        state = .loaded(content)
        let after = content.pricing
        // Pendant sa propre réservation, c'est `setShare` qui célèbre (`celebration`).
        guard celebrate, !isSaving, after.tierNumber > before.tierNumber else { return }
        tierUnlockCount += 1
        lastUnlockedTierNumber = after.tierNumber
        liveUnlock = TierCelebration(
            tierNumber: after.tierNumber,
            tierCount: after.tierCount,
            previousPriceCents: before.currentPriceCents,
            newPriceCents: after.currentPriceCents,
            committedShares: order.committedShares,
            myQuantity: content.myShareQuantity,
            myTotalCents: after.totalCents(forShares: content.myShareQuantity),
            mySavingsCents: after.savingsCents(forShares: content.myShareQuantity)
        )
    }

    private func setShare(quantity: Int) async {
        guard let content = state.value, !isSaving else { return }
        // T-187 : un visiteur ne réserve jamais dans un groupe dont il n'est pas membre (les règles refuseraient aussi).
        guard !isReadOnly else {
            actionError = .invalidInput(String(localized: "Rejoins ce groupe pour réserver ta part."))
            return
        }
        guard content.groupOrder != nil || (content.canStartOrder && quantity > 0), let groupId else {
            actionError = .invalidInput(String(localized: "Rejoins un groupe de quartier pour réserver ce lot."))
            return
        }
        isSaving = true
        defer { isSaving = false }
        let before = content.pricing
        do {
            // Première réservation du groupe sur ce lot : on ouvre la commande (T-033).
            let order: GroupOrder
            if let existing = content.groupOrder {
                order = existing
            } else {
                order = try await repositories.groupOrders.openGroupOrder(groupId: groupId, offerId: offerId)
            }
            var updated = order
            if quantity != content.myShareQuantity {
                updated = try await repositories.groupOrders.setShare(
                    quantity: quantity, householdId: householdId, groupOrderId: order.id
                )
            }
            var newContent = content
            newContent.groupOrder = updated
            newContent.myShareQuantity = quantity
            newContent.mySuspendedCents = quantity > 0 ? content.mySuspendedCents : 0
            state = .loaded(newContent)
            // T-181 : le panier suspendu est enregistré avec la part (plafond de `SolidarityLedger`).
            if quantity > 0, suspendedCents != newContent.mySuspendedCents {
                let saved = try await repositories.groupOrders.setSuspendedBasket(
                    suspendedCents, householdId: householdId, groupOrderId: order.id
                )
                newContent.mySuspendedCents = saved.suspendedAmountCents
            }
            state = .loaded(newContent)
            // L'Accueil (sous la fiche dans la pile) recharge ses cartes : nouveau prix, nouvelle part.
            ShareActivity.shared.shareDidChange()

            let after = newContent.pricing
            if quantity > 0, after.tierNumber > before.tierNumber {
                celebration = TierCelebration(
                    tierNumber: after.tierNumber,
                    tierCount: after.tierCount,
                    previousPriceCents: before.currentPriceCents,
                    newPriceCents: after.currentPriceCents,
                    committedShares: updated.committedShares,
                    myQuantity: quantity,
                    myTotalCents: after.totalCents(forShares: quantity),
                    mySavingsCents: after.savingsCents(forShares: quantity)
                )
            }
        } catch {
            actionError = AppError(error)
        }
    }

    private func projectedCommittedShares(_ content: Content) -> Int {
        content.committedShares - content.myShareQuantity + selectedQuantity
    }
}
