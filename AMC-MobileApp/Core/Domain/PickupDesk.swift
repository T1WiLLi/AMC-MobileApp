// PickupDesk.swift
// Cueillette chez l'hôte (E08 : RQ-066, RQ-067).
// Lecture du code QR d'un ménage, part marquée comme cueillie, liste de distribution.
//
// Sécurité (vol de cueillette) : le code est `GRENIER:<commande>:<ménage>:<jeton>#<uid>`. Le jeton est aléatoire
// (128 bits, `newPickupToken`) et vit dans un document privé de la part (`shares/{h}/private/pickup`, firestore.rules),
// lisible par le ménage, l'hôte du point et les coordonnateurs, pas par les autres membres du groupe. L'ancien code
// (somme de contrôle FNV calculable par tous à partir des ids) est refusé au scan (`.outdatedCode`).

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
        /// Ancien code (d'avant le jeton secret) : il se recalcule à partir des ids, l'hôte ne peut plus s'y fier.
        case outdatedCode
        /// La commande n'est pas encore (ou plus) prête à être cueillie.
        case orderNotReady(GroupOrder.Status)

        var isSuccess: Bool {
            if case .pickedUp = self { true } else { false }
        }

        /// La part concernée, quand le code a été reconnu.
        var share: Share? {
            switch self {
            case .pickedUp(let share), .alreadyPickedUp(let share): share
            case .unknownCode, .wrongOrder, .outdatedCode, .orderNotReady: nil
            }
        }

        var title: String {
            switch self {
            case .pickedUp: String(localized: "Part remise")
            case .alreadyPickedUp: String(localized: "Déjà cueillie")
            case .unknownCode: String(localized: "Code inconnu")
            case .wrongOrder: String(localized: "Mauvaise commande")
            case .outdatedCode: String(localized: "Ancien code")
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
            case .outdatedCode:
                String(localized: "Ce code n'est plus valide. Demande au ménage de rouvrir son code dans l'app à jour, ou vérifie qui il est et touche « Récupéré » dans la liste.")
            case .orderNotReady(let status):
                switch status {
                case .open, .reached:
                    String(localized: "La commande est encore ouverte : attends qu'elle soit fermée et livrée chez toi.")
                case .cancelled:
                    String(localized: "Cette commande a été annulée : il n'y a rien à remettre.")
                case .closed:
                    String(localized: "La livraison n'est pas encore arrivée. Marque-la comme arrivée avant de remettre les parts.")
                case .delivered:
                    String(localized: "La commande n'est pas prête.")
                }
            }
        }
    }

    /// Seule une commande livrée (arrivée au point, `OrderArrival.markArrived`) peut être cueillie : fermée, elle est
    /// encore en route.
    static func canPickUp(_ status: GroupOrder.Status) -> Bool {
        switch status {
        case .delivered: true
        case .open, .reached, .closed, .cancelled: false
        }
    }

    // MARK: Jeton et code de la part

    /// Jeton secret d'une part : 128 bits de `SystemRandomNumberGenerator`, en 32 caractères hexadécimaux.
    static func newPickupToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<2).map { _ in
            let value = generator.next() as UInt64
            let hex = String(value, radix: 16)
            return String(repeating: "0", count: 16 - hex.count) + hex
        }.joined()
    }

    /// Jeton bien formé (`newPickupToken`) : 32 caractères hexadécimaux minuscules, comme l'exige firestore.rules.
    static func isPickupToken(_ token: String) -> Bool {
        token.utf8.count == 32 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Code QR de la part d'un ménage, le même pour tous ses membres : `GRENIER:<commande>:<ménage>:<jeton>`.
    static func pickupCode(orderId: String, householdId: String, token: String) -> String {
        "\(ShareAllocator.qrCodePrefix)\(orderId):\(householdId):\(token)"
    }

    /// Code scanné, découpé. `secret` est le jeton (ou, pour un ancien code, sa somme de contrôle).
    struct ParsedCode: Sendable, Equatable {
        var orderId: String
        var householdId: String
        var secret: String
        var memberId: String?

        /// Ancien format (T-043) : somme de contrôle FNV de 8 caractères, recalculable par n'importe qui.
        var isLegacy: Bool { secret.utf8.count == 8 && !PickupDesk.isPickupToken(secret) }
    }

    /// Découpe `GRENIER:<commande>:<ménage>:<secret>[#uid]`, nil si ce n'est pas un code Grenier.
    static func parse(_ code: String) -> ParsedCode? {
        let (qrCode, memberId) = splitMemberCode(code)
        let parts = qrCode.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        // Pas de « / » : l'id devient un chemin Firestore (`shares/<ménage>`).
        guard parts.count == 4, parts[0] == "GRENIER",
              parts[1...].allSatisfy({ !$0.isEmpty && !$0.contains("/") }) else { return nil }
        return ParsedCode(orderId: parts[1], householdId: parts[2], secret: parts[3], memberId: memberId)
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

    /// Sépare un code scanné en QR de la part et uid du membre (nil pour un code sans membre).
    static func splitMemberCode(_ code: String) -> (qrCode: String, memberId: String?) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = code.lastIndex(of: memberSeparator) else { return (code, nil) }
        let memberId = String(code[code.index(after: index)...])
        return (String(code[..<index]), memberId.isEmpty ? nil : memberId)
    }

    /// RQ-066 : valide le code scanné contre le jeton privé du ménage et renvoie la part à marquer comme cueillie.
    /// T-159 : une part par ménage, remise une seule fois, à n'importe quel membre ; un deuxième membre qui se
    /// présente reçoit `.alreadyPickedUp`. Le membre du code est noté dans `pickedUpBy`.
    /// - Parameter pickupTokens: jeton de chaque ménage (`shares/{h}/private/pickup`), lu par l'hôte ; un ménage
    ///   sans jeton n'a pas encore ouvert son code : son code est inconnu.
    static func scan(
        _ code: String, order: GroupOrder, shares: [Share], pickupTokens: [String: String], at date: Date = .now
    ) -> ScanResult {
        guard canPickUp(order.status) else { return .orderNotReady(order.status) }
        guard let parsed = parse(code) else { return .unknownCode }
        guard parsed.orderId == order.id else { return .wrongOrder }
        if parsed.isLegacy { return .outdatedCode }
        guard let token = pickupTokens[parsed.householdId], isPickupToken(token),
              constantTimeEquals(token, parsed.secret) else {
            return .unknownCode
        }
        return handOver(householdId: parsed.householdId, order: order, shares: shares,
                        pickedUpBy: parsed.memberId, at: date)
    }

    /// Remise à la main (« Récupéré ») : l'hôte a reconnu la famille, sans code. Aussi le chemin des parts dont le
    /// ménage n'a pas encore de jeton (commandes fermées avant le jeton, famille sans l'app à jour).
    /// `pickedUpBy` est l'uid de l'hôte ou du coordonnateur qui confirme.
    static func handOver(
        householdId: String, order: GroupOrder, shares: [Share], pickedUpBy: String?, at date: Date = .now
    ) -> ScanResult {
        guard canPickUp(order.status) else { return .orderNotReady(order.status) }
        guard var share = shares.first(where: { $0.householdId == householdId }), share.quantity > 0 else {
            return .unknownCode
        }
        if share.isPickedUp { return .alreadyPickedUp(share) }
        share.isPickedUp = true
        share.pickedUpBy = pickedUpBy
        share.pickedUpAt = date
        return .pickedUp(share)
    }

    /// Comparaison sans sortie anticipée : le temps de réponse ne dit pas combien de caractères étaient justes.
    private static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let left = Array(left.utf8), right = Array(right.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
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
        count > 1 ? String(localized: "\(count) parts") : String(localized: "\(count) part")
    }
}
