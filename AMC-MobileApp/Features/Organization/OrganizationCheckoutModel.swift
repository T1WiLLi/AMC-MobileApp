// OrganizationCheckoutModel.swift
// T-207 : étape de paiement d'un organisme (don, paniers suspendus, parrainage mensuel), comme la réservation
// côté Famille : carte Apple Pay •••• 4242, Face ID ou code, « Traitement… », puis reçu ou refus.
// Aucun argent ne bouge : `PaymentSimulator` décide, puis le portail écrit le don (ou le parrainage) comme avant.
//
// Usage :
//   @State private var checkout: OrganizationCheckoutModel?
//   checkout = OrganizationCheckoutModel(portal: model, purpose: .donation(request, groupId: id),
//                                        amountCents: plan.amountCents, groupName: profile.groupName)
//   Button("Payer") { Task { await checkout.pay() } }

import Foundation
import Observation

@Observable @MainActor
final class OrganizationCheckoutModel {
    /// Ce que l'organisme paie.
    enum Purpose: Sendable, Equatable {
        /// Don unique au fonds de solidarité du groupe.
        case donation(DonationRequest, groupId: String)
        /// Parrainage (nouveau ou objectif changé) : montant prélevé chaque mois.
        case sponsorship(groupId: String, monthlyBasketGoal: Int)
    }

    enum Phase: Equatable {
        /// Récapitulatif, bouton « Payer ».
        case review
        /// Face ID ou code de l'appareil en cours.
        case authenticating
        /// Faux terminal : « Traitement… » (environ 1 s).
        case processing
        /// Paiement accepté et enregistré.
        case succeeded(OrganizationPaymentReceipt)
        /// Refus du terminal : rien n'est écrit, on peut réessayer.
        case declined(OrganizationPaymentDecline)
        /// Paiement accepté mais l'enregistrement a échoué (réseau, règles) : rien n'est débité, on peut réessayer.
        case failed(AppError)
    }

    let purpose: Purpose
    let amountCents: Cents
    let groupName: String
    /// Méthode d'authentification lue une fois (LocalAuthentication) : Face ID, code, ou rien (simulateur).
    let biometry: BiometryKind

    private(set) var phase: Phase = .review
    /// Tentatives de paiement (réessais compris), pour l'analyse et les tests.
    private(set) var attempts = 0
    /// Faux terminal ; les tests changent `outcome` pour simuler un refus puis un succès.
    var simulator: PaymentSimulator

    private let portal: OrganizationPortalModel
    private let authenticator: any BiometricAuthenticator
    private let processingDelay: Duration
    private let now: @Sendable () -> Date

    init(
        portal: OrganizationPortalModel,
        purpose: Purpose,
        amountCents: Cents,
        groupName: String,
        authenticator: any BiometricAuthenticator = DeviceBiometricAuthenticator(),
        simulator: PaymentSimulator = .fromLaunchArguments(),
        processingDelay: Duration = .milliseconds(1_100),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.portal = portal
        self.purpose = purpose
        self.amountCents = amountCents
        self.groupName = groupName
        self.authenticator = authenticator
        self.biometry = authenticator.availability()
        self.simulator = simulator
        self.processingDelay = processingDelay
        self.now = now
    }

    var isRecurring: Bool {
        if case .sponsorship = purpose { return true }
        return false
    }

    /// Authentification ou traitement en cours : le bouton « Payer » ne répond plus.
    var isBusy: Bool { phase == .authenticating || phase == .processing }

    var receipt: OrganizationPaymentReceipt? {
        if case .succeeded(let receipt) = phase { return receipt }
        return nil
    }

    /// Paie : authentification locale, faux terminal, puis enregistrement du don ou du parrainage.
    /// Un second toucher pendant le paiement, ou après un succès, ne fait rien : un seul don est créé.
    func pay() async {
        guard !isBusy, receipt == nil else { return }
        attempts += 1

        if biometry.canAuthenticate {
            phase = .authenticating
            do {
                try await authenticator.authenticate(reason: authenticationReason)
            } catch {
                switch AppError(error) {
                case .invalidInput:
                    // Annulé par l'utilisateur : retour au récapitulatif, sans message.
                    phase = .review
                    return
                case .unknown:
                    // Aucune méthode sur l'appareil (simulateur sans code) : la touche « Payer » vaut confirmation.
                    break
                case let other:
                    phase = .failed(other)
                    return
                }
            }
        }

        phase = .processing
        try? await Task.sleep(for: processingDelay)

        if let decline = simulator.authorizeOrganizationCharge(amountCents: amountCents) {
            phase = .declined(decline)
            return
        }

        switch purpose {
        case .donation(let request, let groupId):
            guard await portal.donate(request, toGroup: groupId), let donation = portal.lastDonation else {
                phase = .failed(portal.actionError ?? .unknown("Don non enregistré."))
                return
            }
            phase = .succeeded(.make(donation: donation))
        case .sponsorship(let groupId, let goal):
            guard await portal.sponsor(groupId: groupId, monthlyBasketGoal: goal),
                  let sponsorship = portal.sponsorship(ofGroup: groupId) else {
                phase = .failed(portal.actionError ?? .unknown("Parrainage non enregistré."))
                return
            }
            phase = .succeeded(.make(sponsorship: sponsorship, monthlyAmountCents: amountCents, date: now()))
        }
    }

    /// Retour au récapitulatif après un refus ou une erreur.
    func backToReview() {
        guard !isBusy, receipt == nil else { return }
        phase = .review
    }

    private var authenticationReason: String {
        isRecurring
            ? String(localized: "Confirme le parrainage de \(groupName).")
            : String(localized: "Confirme le paiement pour \(groupName).")
    }
}
