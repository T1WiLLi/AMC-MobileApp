// OrderActivityPresentation.swift
// Textes et calculs affichés par la Live Activity et le widget. Logique pure, testée dans
// AMC-MobileAppTests/LiveActivity/. Les vues de GrenierWidgets ne calculent rien elles-mêmes.

import Foundation

/// Ce que la Live Activity et le widget montrent pour une commande à un instant donné.
nonisolated struct OrderActivityPresentation: Hashable, Sendable {
    typealias Stage = GrenierOrderAttributes.Stage

    let attributes: GrenierOrderAttributes
    let state: GrenierOrderAttributes.ContentState

    init(_ attributes: GrenierOrderAttributes, _ state: GrenierOrderAttributes.ContentState) {
        self.attributes = attributes
        self.state = state
    }

    // MARK: - Paliers

    /// Paliers triés par seuil croissant.
    var sortedTiers: [GrenierOrderAttributes.Tier] { attributes.tiers.sorted { $0.minFamilies < $1.minFamilies } }

    /// Prochain palier à atteindre, nil si le dernier est atteint.
    var nextTier: GrenierOrderAttributes.Tier? {
        guard let threshold = state.nextThreshold else { return nil }
        return sortedTiers.first { $0.minFamilies == threshold }
            ?? sortedTiers.first { $0.minFamilies > state.committedFamilies }
    }

    /// Index du palier atteint dans `sortedTiers`, nil si aucun.
    var currentTierIndex: Int? { sortedTiers.lastIndex { state.committedFamilies >= $0.minFamilies } }

    /// Familles qui manquent pour le prochain palier (0 si le dernier est atteint).
    var familiesMissing: Int {
        guard let threshold = state.nextThreshold else { return 0 }
        return max(threshold - state.committedFamilies, 0)
    }

    /// Baisse en % du prochain palier par rapport au prix courant (19 pour 2,60 → 2,10 $), nil si aucun.
    var nextDiscountPercent: Int? {
        guard let next = nextTier, state.currentPriceCents > 0, next.priceCents < state.currentPriceCents else { return nil }
        return Int((Double(state.currentPriceCents - next.priceCents) / Double(state.currentPriceCents) * 100).rounded())
    }

    /// Prix d'avant (barré) quand un palier vient de tomber, sinon nil.
    var previousPriceCents: Int? {
        guard state.stage == .palierFranchi, let index = currentTierIndex, index > 0 else { return nil }
        return sortedTiers[index - 1].priceCents
    }

    // MARK: - Textes

    /// « Riz basmati · Parc-Ex Ouest »
    var title: String { "\(attributes.productName) · \(attributes.groupName)" }

    /// « Parc-Ex Ouest · Palier débloqué » : sous le nom du produit.
    var subtitle: String { "\(attributes.groupName) · \(stageLabel)" }

    /// « 1 famille », « 2 familles »
    static func families(_ count: Int) -> String { count > 1 ? "\(count) familles" : "\(count) famille" }

    /// Phrase principale, en Grenier sous le titre.
    var headline: String {
        switch state.stage {
        case .ouverte:
            guard familiesMissing > 0 else { return "Meilleur prix atteint pour \(attributes.groupName)" }
            let who = "Encore \(Self.families(familiesMissing))"
            if let percent = nextDiscountPercent { return "\(who) pour −\(percent) %" }
            return "\(who) pour le prochain palier"
        case .palierFranchi:
            return "Palier débloqué : \(priceText)/\(attributes.unit) pour tout le groupe"
        case .enRoute:
            return "Ta commande arrive à \(pickupTimeText) au \(attributes.pickupAddress)"
        case .arrivee:
            return "Ta commande t'attend au \(attributes.pickupAddress)"
        case .recuperee:
            return "Commande récupérée, bon appétit !"
        }
    }

    /// Ligne secondaire sous la phrase principale.
    var detail: String {
        switch state.stage {
        case .ouverte:
            "\(Self.families(state.committedFamilies)) · \(attributes.vendorName)"
        case .palierFranchi:
            "Tu es la \(state.committedFamilies)e famille · ta part \(attributes.shareLabel)"
        case .enRoute:
            "\(attributes.vendorName) → \(attributes.pickupPlaceName)"
        case .arrivee:
            "Montre le code \(attributes.orderCode) à \(attributes.pickupHost)"
        case .recuperee:
            "\(attributes.shareLabel) de \(attributes.productName.lowercased()) · merci \(attributes.pickupHost)"
        }
    }

    /// Libellé court de l'étape (Dynamic Island étendue, accessibilité).
    var stageLabel: String {
        switch state.stage {
        case .ouverte: "Groupe ouvert"
        case .palierFranchi: "Palier débloqué"
        case .enRoute: "En route"
        case .arrivee: "Arrivée"
        case .recuperee: "Récupérée"
        }
    }

    /// Symbole SF de l'étape (rendu hiérarchique).
    var stageSymbol: String {
        switch state.stage {
        case .ouverte: "person.3.fill"
        case .palierFranchi: "checkmark.seal.fill"
        case .enRoute: "box.truck.fill"
        case .arrivee: "shippingbox.fill"
        case .recuperee: "checkmark.circle.fill"
        }
    }

    /// « 2,10 $ »
    var priceText: String { GrenierFormat.price(state.currentPriceCents) }

    /// « 17 h » ou « 17 h 30 »
    var pickupTimeText: String { GrenierFormat.hour(state.pickupTime) }

    /// Texte de droite en Dynamic Island compacte : le prix tant que le groupe se remplit, puis l'heure.
    var compactTrailingText: String {
        switch state.stage {
        case .ouverte, .palierFranchi: priceText
        case .enRoute: pickupTimeText
        case .arrivee: "Prête"
        case .recuperee: "OK"
        }
    }

    /// Le prix est l'information vedette (sinon c'est l'heure de cueillette).
    var showsPrice: Bool { state.stage == .ouverte || state.stage == .palierFranchi }

    // MARK: - Barre de progression (3 segments)

    /// Barre des paliers pour `ouverte` / `palierFranchi`, puis barre du trajet (en route, arrivée, récupérée).
    var showsTierBar: Bool { showsPrice }

    /// Remplissage (0…1) de chaque segment de la barre.
    var segmentFills: [Double] {
        if showsTierBar {
            let tiers = sortedTiers
            return tiers.indices.map { index in
                let lower = tiers[index].minFamilies
                guard index + 1 < tiers.count else { return state.committedFamilies >= lower ? 1 : 0 }
                let span = Double(tiers[index + 1].minFamilies - lower)
                return min(max(Double(state.committedFamilies - lower + 1) / span, 0), 1)
            }
        }
        switch state.stage {
        case .enRoute: return [1, 0, 0]
        case .arrivee: return [1, 1, 0]
        default: return [1, 1, 1]
        }
    }

    /// Libellés sous la barre : « 1–10 · 3,20 $ » … ou « En route », « Arrivée », « Récupérée ».
    var segmentLabels: [String] {
        guard showsTierBar else { return ["En route", "Arrivée", "Récupérée"] }
        let tiers = sortedTiers
        return tiers.indices.map { index in
            let tier = tiers[index]
            let range = index + 1 < tiers.count ? "\(tier.minFamilies)–\(tiers[index + 1].minFamilies - 1)" : "\(tier.minFamilies)+"
            return "\(range) · \(GrenierFormat.price(tier.priceCents))"
        }
    }

    /// Segment mis en gras (palier atteint, ou étape du trajet en cours).
    var highlightedSegment: Int? {
        if showsTierBar { return currentTierIndex }
        switch state.stage {
        case .enRoute: return 0
        case .arrivee: return 1
        default: return 2
        }
    }

    // MARK: - Alerte de mise à jour (allume la Dynamic Island)

    /// Titre et corps de l'alerte envoyée à la mise à jour vers cette étape, nil si on reste discret.
    var alert: (title: String, body: String)? {
        switch state.stage {
        case .ouverte, .recuperee:
            nil
        case .palierFranchi:
            ("Palier débloqué !",
             "\(attributes.productName) à \(priceText)/\(attributes.unit) pour tout \(attributes.groupName).")
        case .enRoute:
            ("Ta commande est en route", headline + ".")
        case .arrivee:
            ("Ta commande est arrivée", "Montre le code \(attributes.orderCode) à \(attributes.pickupHost).")
        }
    }

    /// Phrase lue par VoiceOver pour toute l'activité.
    var accessibilitySummary: String { "\(title). \(headline). \(detail)." }
}

/// Formatage partagé app / extension (l'extension n'a pas accès à `Money`).
nonisolated enum GrenierFormat {
    private static let locale = Locale(identifier: "fr_CA")

    /// « 2,60 $ » (espace insécable avant $), comme `Money.format`.
    static func price(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "CAD").locale(locale))
    }

    /// « 17 h », « 17 h 30 » (usage québécois).
    static func hour(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }
}
