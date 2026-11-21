// Report.swift
// Signalement d'un contenu ou d'un membre (T-106, RQ-098) : cible, motif, commentaire facultatif, date.

import Foundation

/// Ce qu'on signale : un lot, un vendeur, un membre d'un groupe ou un message.
nonisolated struct ReportTarget: Identifiable, Hashable, Sendable, Codable {
    nonisolated enum Kind: String, CaseIterable, Sendable, Codable {
        case offer
        case vendor
        case member
        case message

        /// « ce lot », « ce vendeur »… pour les titres et VoiceOver.
        var demonstrative: String {
            switch self {
            case .offer: String(localized: "ce lot")
            case .vendor: String(localized: "ce vendeur")
            case .member: String(localized: "ce membre")
            case .message: String(localized: "ce message")
            }
        }

        var systemImage: String {
            switch self {
            case .offer: "shippingbox.fill"
            case .vendor: "storefront.fill"
            case .member: "person.crop.circle.fill"
            case .message: "bubble.left.fill"
            }
        }
    }

    var kind: Kind
    /// Identifiant du document signalé (offre, vendeur, utilisateur, message).
    var id: String
    /// Nom montré dans la feuille (« Ferme de la Rive », « Pommes Cortland »).
    var displayName: String

    static func offer(id: String, name: String) -> ReportTarget { .init(kind: .offer, id: id, displayName: name) }
    static func vendor(id: String, name: String) -> ReportTarget { .init(kind: .vendor, id: id, displayName: name) }
    static func member(id: String, name: String) -> ReportTarget { .init(kind: .member, id: id, displayName: name) }
    static func message(id: String, excerpt: String) -> ReportTarget { .init(kind: .message, id: id, displayName: excerpt) }
}

/// Motif d'un signalement.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Sendable, Codable {
    case inappropriate
    case scam
    case behavior
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriate: String(localized: "Contenu inapproprié")
        case .scam: String(localized: "Arnaque ou fraude")
        case .behavior: String(localized: "Comportement")
        case .other: String(localized: "Autre")
        }
    }

    var subtitle: String {
        switch self {
        case .inappropriate: String(localized: "Photo, texte ou annonce choquante")
        case .scam: String(localized: "Prix trompeur, paiement hors de l'app")
        case .behavior: String(localized: "Propos blessants, harcèlement, absences répétées")
        case .other: String(localized: "Dis-nous ce qui ne va pas")
        }
    }

    var systemImage: String {
        switch self {
        case .inappropriate: "eye.slash.fill"
        case .scam: "exclamationmark.shield.fill"
        case .behavior: "person.fill.questionmark"
        case .other: "ellipsis.bubble.fill"
        }
    }

    /// « Autre » demande quelques mots pour être traitable.
    var requiresComment: Bool { self == .other }
}

/// Un signalement envoyé.
nonisolated struct Report: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var target: ReportTarget
    var reason: ReportReason
    /// Précisions facultatives (obligatoires pour « Autre »), sans espaces de début ni de fin.
    var comment: String?
    var createdAt: Date
}
