// PickupDesk.swift
// Cueillette chez l'hôte (E08 : RQ-066, RQ-067).
// Lecture du code QR d'un ménage, part marquée comme cueillie, liste de distribution.

import Foundation

nonisolated enum PickupDesk {
    /// Résultat d'un code scanné par l'hôte.
    enum ScanResult: Sendable, Equatable {
        /// Part remise : `share.isPickedUp` vaut maintenant `true`, à enregistrer.
        case pickedUp(Share)
        /// La part avait déjà été remise ; rien à enregistrer.
        case alreadyPickedUp(Share)
        /// Code illisible, modifié, ou d'un ménage sans part dans cette commande.
        case unknownCode
        /// Code Grenier valide, mais pour une autre commande.
        case wrongOrder
        /// La commande n'est pas encore (ou plus) prête à être cueillie.
        case orderNotReady(GroupOrder.Status)

        var isSuccess: Bool {
            if case .pickedUp = self { true } else { false }
        }

        /// La part concernée, quand le code a été reconnu.
        var share: Share? {
            switch self {
            case .pickedUp(let share), .alreadyPickedUp(let share): share
            case .unknownCode, .wrongOrder, .orderNotReady: nil
            }
        }

        var title: String {
            switch self {
            case .pickedUp: String(localized: "Part remise")
            case .alreadyPickedUp: String(localized: "Déjà cueillie")
            case .unknownCode: String(localized: "Code inconnu")
            case .wrongOrder: String(localized: "Mauvaise commande")
            case .orderNotReady: String(localized: "Commande pas prête")
            }
        }

        var message: String {
            switch self {
            case .pickedUp(let share):
                String(localized: "C'est bon ! Remets \(PickupDesk.sharesLabel(share.quantity)) à ce ménage.")
            case .alreadyPickedUp:
                String(localized: "Cette part a déjà été remise. Ne la donne pas une deuxième fois.")
            case .unknownCode:
                String(localized: "Ce code ne correspond à aucune part de cette commande. Demande au ménage d'ouvrir son code dans l'app.")
            case .wrongOrder:
                String(localized: "Ce code est pour une autre commande. Vérifie que tu as ouvert la bonne cueillette.")
            case .orderNotReady(let status):
                switch status {
                case .open, .reached:
                    String(localized: "La commande est encore ouverte : attends qu'elle soit fermée et livrée chez toi.")
                case .cancelled:
                    String(localized: "Cette commande a été annulée : il n'y a rien à remettre.")
                case .closed, .delivered:
                    String(localized: "La commande n'est pas prête.")
                }
            }
        }
    }

    /// Seules les commandes fermées (en route ou chez l'hôte) ou livrées peuvent être cueillies.
    static func canPickUp(_ status: GroupOrder.Status) -> Bool {
        switch status {
        case .closed, .delivered: true
        case .open, .reached, .cancelled: false
        }
    }

    // MARK: Code d'un membre (T-159)

    /// Séparateur entre le QR de la part (le même pour tout le ménage) et l'uid du membre qui le montre.
    static let memberSeparator: Character = "#"

    /// Code affiché par un membre : `GRENIER:…#uid`. Le QR identifie la part du ménage ; l'uid dit qui la récupère.
    static func memberCode(_ qrCode: String, memberId: String) -> String {
        let memberId = memberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !memberId.isEmpty, !memberId.contains(memberSeparator) else { return qrCode }
        return "\(qrCode)\(memberSeparator)\(memberId)"
    }

    /// Sépare un code scanné en QR de la part et uid du membre (nil pour un ancien code sans membre).
    static func splitMemberCode(_ code: String) -> (qrCode: String, memberId: String?) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = code.lastIndex(of: memberSeparator) else { return (code, nil) }
        let memberId = String(code[code.index(after: index)...])
        return (String(code[..<index]), memberId.isEmpty ? nil : memberId)
    }

    /// RQ-066 : valide le code scanné et renvoie la part à marquer comme cueillie.
    /// T-159 : une part par ménage, remise une seule fois, à n'importe quel membre ; un deuxième membre qui se
    /// présente reçoit `.alreadyPickedUp`. Le membre du code est noté dans `pickedUpBy`.
    static func scan(_ code: String, order: GroupOrder, shares: [Share], at date: Date = .now) -> ScanResult {
        guard canPickUp(order.status) else { return .orderNotReady(order.status) }
        let (code, memberId) = splitMemberCode(code)
        guard let householdId = ShareAllocator.householdId(fromQRCode: code, orderId: order.id) else {
            return isValidCodeOfAnotherOrder(code, orderId: order.id) ? .wrongOrder : .unknownCode
        }
        guard var share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else {
            return .unknownCode
        }
        if share.isPickedUp { return .alreadyPickedUp(share) }
        share.isPickedUp = true
        share.pickedUpBy = memberId
        share.pickedUpAt = date
        return .pickedUp(share)
    }

    /// Code bien formé et intact, mais émis pour une autre commande.
    private static func isValidCodeOfAnotherOrder(_ code: String, orderId: String) -> Bool {
        let parts = code.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "GRENIER", parts[1] != orderId else { return false }
        return ShareAllocator.qrCode(orderId: parts[1], householdId: parts[2]) == code
    }

    // MARK: - Liste de distribution (RQ-067)

    struct Checklist: Sendable, Equatable {
        struct Entry: Identifiable, Sendable, Equatable {
            var householdId: String
            var displayName: String
            var quantity: Int
            var isPickedUp: Bool

            var id: String { householdId }
        }

        /// Ménages à servir : ceux qui manquent d'abord, puis par nom.
        var entries: [Entry]

        var missing: [Entry] { entries.filter { !$0.isPickedUp } }
        var pickedUp: [Entry] { entries.filter(\.isPickedUp) }
        var totalCount: Int { entries.count }
        var pickedUpCount: Int { pickedUp.count }
        var missingCount: Int { totalCount - pickedUpCount }
        var totalShares: Int { entries.reduce(0) { $0 + $1.quantity } }
        var pickedUpShares: Int { pickedUp.reduce(0) { $0 + $1.quantity } }
        /// Part des ménages servis, de 0 à 1 (0 s'il n'y a personne).
        var progress: Double { totalCount == 0 ? 0 : Double(pickedUpCount) / Double(totalCount) }
        var isComplete: Bool { totalCount > 0 && missingCount == 0 }

        var summary: String {
            if totalCount == 0 { return String(localized: "Aucune part à remettre.") }
            if isComplete { return String(localized: "Tout le monde est passé !") }
            let waiting = missingCount == 1 ? String(localized: "1 ménage attendu") : String(localized: "\(missingCount) ménages attendus")
            return String(localized: "\(pickedUpCount) sur \(totalCount) passés · \(waiting)")
        }
    }

    /// RQ-067 : liste de distribution de l'hôte.
    /// - Parameter displayNames: nom affiché de chaque ménage ; à défaut, « Ménage <id> ».
    static func checklist(shares: [Share], displayNames: [String: String] = [:]) -> Checklist {
        let entries = shares
            .filter { $0.quantity > 0 }
            .map { share in
                Checklist.Entry(
                    householdId: share.householdId,
                    displayName: displayNames[share.householdId] ?? String(localized: "Ménage \(share.householdId)"),
                    quantity: share.quantity,
                    isPickedUp: share.isPickedUp
                )
            }
            .sorted { left, right in
                if left.isPickedUp != right.isPickedUp { return !left.isPickedUp }
                let byName = left.displayName.localizedStandardCompare(right.displayName)
                if byName != .orderedSame { return byName == .orderedAscending }
                return left.householdId < right.householdId
            }
        return Checklist(entries: entries)
    }

    /// « 1 part », « 3 parts ».
    static func sharesLabel(_ count: Int) -> String {
        count > 1 ? "\(count) parts" : "\(count) part"
    }
}
