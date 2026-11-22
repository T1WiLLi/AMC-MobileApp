// DeliveryManifest.swift
// Livraison du vendeur (E09 : RQ-073, RQ-074).
// Bordereau consolidé par point de cueillette, export texte, et passage fermée → livrée.

import Foundation

nonisolated struct DeliveryManifest: Sendable, Equatable {
    /// Un produit à déposer à un point de cueillette (plusieurs commandes du même lot y sont fusionnées).
    struct Line: Identifiable, Sendable, Equatable {
        var productId: String
        var productName: String
        /// Ce que contient une part : « 10 kg », « 1 caisse »…
        var shareUnit: String
        var totalShares: Int
        var households: Int
        var orderIds: [String]

        var id: String { "\(productId)|\(shareUnit)" }
    }

    /// Un arrêt de la tournée : un point de cueillette et ce qu'on y dépose.
    struct Stop: Identifiable, Sendable, Equatable {
        /// nil quand la commande n'a pas encore de point de cueillette.
        var pickupPointId: String?
        var name: String
        var address: String
        /// Triées par nom de produit.
        var lines: [Line]

        var id: String { pickupPointId ?? DeliveryManifest.unassignedStopId }
        var totalShares: Int { lines.reduce(0) { $0 + $1.totalShares } }
        var totalHouseholds: Int { lines.reduce(0) { $0 + $1.households } }
        var orderIds: [String] { lines.flatMap(\.orderIds).sorted() }
    }

    static let unassignedStopId = "unassigned"

    /// Triés par nom ; le point « à confirmer » en dernier.
    var stops: [Stop]

    var totalShares: Int { stops.reduce(0) { $0 + $1.totalShares } }
    var totalHouseholds: Int { stops.reduce(0) { $0 + $1.totalHouseholds } }
    var orderCount: Int { stops.reduce(0) { $0 + $1.orderIds.count } }
    var isEmpty: Bool { stops.isEmpty }

    /// RQ-073 : bordereau consolidé des commandes fermées à livrer.
    /// Les commandes non fermées, sans part ou dont le lot est inconnu sont ignorées.
    /// - Parameter vendorId: si fourni, ne garde que les lots de ce vendeur.
    init(
        orders: [GroupOrder],
        offers: [Offer],
        products: [Product],
        pickupPoints: [PickupPoint],
        vendorId: String? = nil
    ) {
        let offersById = Dictionary(offers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pointsById = Dictionary(pickupPoints.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // pickupPointId (ou unassigned) → id de ligne → ligne
        var grouped: [String: [String: Line]] = [:]
        for order in orders where order.status == .closed && order.committedShares > 0 {
            guard let offer = offersById[order.offerId],
                  vendorId == nil || offer.vendorId == vendorId else { continue }
            let pointKey = order.pickupPointId.flatMap { pointsById[$0] == nil ? nil : $0 }
                ?? Self.unassignedStopId
            var line = Line(
                productId: offer.productId,
                productName: productsById[offer.productId]?.name ?? String(localized: "Produit inconnu"),
                shareUnit: offer.shareUnit,
                totalShares: 0, households: 0, orderIds: []
            )
            line = grouped[pointKey]?[line.id] ?? line
            line.totalShares += order.committedShares
            line.households += order.committedHouseholds
            line.orderIds.append(order.id)
            line.orderIds.sort()
            grouped[pointKey, default: [:]][line.id] = line
        }

        stops = grouped.map { key, lines in
            let point = pointsById[key]
            return Stop(
                pickupPointId: point?.id,
                name: point?.name ?? String(localized: "Point de cueillette à confirmer"),
                address: point?.address ?? "",
                lines: lines.values.sorted { left, right in
                    let byName = left.productName.localizedStandardCompare(right.productName)
                    return byName != .orderedSame ? byName == .orderedAscending : left.id < right.id
                }
            )
        }
        .sorted { left, right in
            if (left.pickupPointId == nil) != (right.pickupPointId == nil) { return left.pickupPointId != nil }
            let byName = left.name.localizedStandardCompare(right.name)
            return byName != .orderedSame ? byName == .orderedAscending : left.id < right.id
        }
    }

    /// Bordereau en texte brut, à partager ou imprimer.
    func plainText(title: String = String(localized: "Bordereau de livraison")) -> String {
        guard !isEmpty else { return String(localized: "\(title)\n\nAucune commande fermée à livrer.") }
        let commandes = orderCount > 1 ? String(localized: "\(orderCount) commandes") : String(localized: "\(orderCount) commande")
        let points = stops.count > 1 ? String(localized: "\(stops.count) points de cueillette") : String(localized: "1 point de cueillette")
        var lines = [title, "\(commandes) · \(points) · \(Self.sharesLabel(totalShares))"]
        for stop in stops {
            lines.append("")
            lines.append(stop.address.isEmpty ? "== \(stop.name) ==" : "== \(stop.name) — \(stop.address) ==")
            for line in stop.lines {
                lines.append(
                    String(localized: "- \(line.productName) (\(line.shareUnit)) : \(Self.sharesLabel(line.totalShares)), \(Self.householdsLabel(line.households))")
                )
            }
            lines.append(
                String(localized: "Total : \(Self.sharesLabel(stop.totalShares)), \(Self.householdsLabel(stop.totalHouseholds))")
            )
        }
        lines.append("")
        lines.append(
            String(localized: "Grand total : \(Self.sharesLabel(totalShares)), \(Self.householdsLabel(totalHouseholds))")
        )
        return lines.joined(separator: "\n")
    }

    static func sharesLabel(_ count: Int) -> String {
        count > 1 ? String(localized: "\(count) parts") : String(localized: "\(count) part")
    }

    static func householdsLabel(_ count: Int) -> String {
        count > 1 ? String(localized: "\(count) ménages") : String(localized: "\(count) ménage")
    }

    // MARK: - Livraison faite (RQ-074)

    /// RQ-074 : marque la livraison comme faite. Seule une commande fermée peut passer à « livrée ».
    static func markDelivered(_ order: GroupOrder) throws -> GroupOrder {
        switch order.status {
        case .closed:
            var order = order
            order.status = .delivered
            return order
        case .delivered:
            throw AppError.invalidInput(String(localized: "Cette livraison est déjà marquée comme faite."))
        case .open, .reached:
            throw AppError.invalidInput(String(localized: "Cette commande est encore ouverte : ferme-la avant de la livrer."))
        case .cancelled:
            throw AppError.invalidInput(String(localized: "Cette commande a été annulée : il n'y a rien à livrer."))
        }
    }
}
