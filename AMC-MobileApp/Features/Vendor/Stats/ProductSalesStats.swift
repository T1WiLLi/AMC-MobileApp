// ProductSalesStats.swift
// RQ-077 (T-119) : statistiques de ventes par produit pour un vendeur.
// Swift pur : aucune dépendance à Firebase ni à l'UI. Les entrées (produits, lots, commandes groupées)
// sont passées en paramètres, ce qui rend l'agrégation testable sans dépôt.
//
// Règles :
// - une commande compte si elle n'est pas annulée (`open`, `reached`, `closed`, `delivered`) ;
// - un lot compte s'il n'est ni brouillon ni annulé ;
// - la date de vente d'une commande est la date limite de son lot (c'est là que la commande se ferme) ;
// - parts vendues = parts engagées ; revenu = parts × prix du palier atteint (0 sous le premier palier,
//   comme `VendorRepositoryQueries.projectedRevenue`) ;
// - économies offertes = max(0, prix d'épicerie de référence − prix du palier) × parts (RQ-089) ;
// - palier moyen = moyenne des numéros de palier atteints par commande (0 sous le premier palier).

import Foundation

/// Fenêtre de temps des statistiques.
nonisolated enum ProductStatsPeriod: String, CaseIterable, Identifiable, Sendable, Hashable {
    case fourWeeks
    case twelveWeeks
    case all

    var id: Self { self }

    /// Libellé court du sélecteur.
    var title: String {
        switch self {
        case .fourWeeks: String(localized: "4 sem.")
        case .twelveWeeks: String(localized: "12 sem.")
        case .all: String(localized: "Tout")
        }
    }

    /// Libellé lu par VoiceOver et affiché en sous-titre.
    var spokenTitle: String {
        switch self {
        case .fourWeeks: String(localized: "4 dernières semaines")
        case .twelveWeeks: String(localized: "12 dernières semaines")
        case .all: String(localized: "Depuis le début")
        }
    }

    /// Nombre de semaines remontées avant la semaine courante incluse ; nil = tout l'historique.
    var weeks: Int? {
        switch self {
        case .fourWeeks: 4
        case .twelveWeeks: 12
        case .all: nil
        }
    }
}

/// Ventes d'une semaine (lundi 0 h, heure de Montréal).
nonisolated struct ProductWeekPoint: Identifiable, Sendable, Hashable {
    var weekStart: Date
    var units: Int
    var revenueCents: Cents

    var id: Date { weekStart }
}

/// Sens de la tendance : dernière semaine avec des ventes comparée à la précédente.
nonisolated enum ProductSalesTrend: Sendable, Hashable {
    case up(percent: Int)
    case down(percent: Int)
    case flat
    /// Une seule semaine de ventes : rien à comparer.
    case new
}

/// Statistiques d'un produit sur la période.
nonisolated struct ProductSalesStats: Identifiable, Sendable, Hashable {
    var productId: String
    var name: String
    var category: Product.Category?
    /// Contenu d'une part (« sac de 10 kg »).
    var shareUnit: String
    var unitsSold: Int
    var revenueCents: Cents
    /// Groupes de quartier distincts qui ont commandé.
    var groupCount: Int
    /// Ménages engagés, toutes commandes confondues.
    var householdCount: Int
    var orderCount: Int
    /// Palier moyen atteint (1 = premier palier, 0 = sous le premier) ; nil sans commande.
    var averageTier: Double?
    /// Nombre de paliers du lot le plus détaillé de ce produit.
    var tierCount: Int
    var savingsCents: Cents
    /// Une entrée par semaine de la période, même vide (pour un axe régulier).
    var weekly: [ProductWeekPoint]

    var id: String { productId }

    var trend: ProductSalesTrend { ProductSalesAggregator.trend(of: weekly) }
}

/// Rapport complet d'un vendeur sur une période.
nonisolated struct ProductStatsReport: Sendable, Hashable {
    var period: ProductStatsPeriod
    /// Produits, du plus grand revenu au plus petit (puis plus de parts, puis par nom).
    var products: [ProductSalesStats]
    /// Totaux hebdomadaires, tous produits confondus.
    var weekly: [ProductWeekPoint]
    var totalUnits: Int
    var totalRevenueCents: Cents
    var totalSavingsCents: Cents
    /// Groupes distincts, tous produits confondus.
    var groupCount: Int
    var householdCount: Int

    /// Meilleurs vendeurs : jusqu'à 3 produits, par parts vendues (puis revenu, puis nom), sans les produits à 0.
    var bestSellers: [ProductSalesStats] {
        Array(
            products
                .filter { $0.unitsSold > 0 }
                .sorted { ($0.unitsSold, $0.revenueCents, $1.name) > ($1.unitsSold, $1.revenueCents, $0.name) }
                .prefix(3)
        )
    }

    /// Aucune part vendue sur la période.
    var hasNoSales: Bool { totalUnits == 0 }

    func product(id: String?) -> ProductSalesStats? {
        guard let id else { return nil }
        return products.first { $0.productId == id }
    }
}

nonisolated enum ProductSalesAggregator {
    /// Commandes qui comptent comme des ventes.
    static let countedStatuses: Set<GroupOrder.Status> = [.open, .reached, .closed, .delivered]
    /// Lots qui comptent.
    static let countedOfferStatuses: Set<Offer.Status> = [.active, .closed]
    /// Plafond de semaines affichées pour « Tout » (un an).
    static let maxWeeks = 52

    /// Agrège les ventes d'un vendeur.
    /// - Parameters:
    ///   - products: produits du vendeur (un lot dont le produit manque est affiché sous son unité de part).
    ///   - offers: lots du vendeur.
    ///   - orders: commandes groupées de ces lots (les autres sont ignorées).
    ///   - period: fenêtre de temps.
    ///   - now: maintenant (injecté pour les tests).
    static func report(
        products: [Product],
        offers: [Offer],
        orders: [GroupOrder],
        period: ProductStatsPeriod,
        now: Date,
        calendar: Calendar = SavingsCalculator.montrealCalendar
    ) -> ProductStatsReport {
        var calendar = calendar
        calendar.firstWeekday = 2 // lundi
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let countedOffers = offers.filter { countedOfferStatuses.contains($0.status) }
        let offersById = Dictionary(countedOffers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let countedOrders = orders.filter { countedStatuses.contains($0.status) && offersById[$0.offerId] != nil }

        // Fenêtre : du début de la première semaine jusqu'à la fin de la semaine de la dernière date limite
        // (les lots ouverts ferment dans le futur : leurs commandes comptent déjà).
        let currentWeek = weekStart(of: now, calendar: calendar)
        let lastDeadline = countedOffers.map(\.deadline).max() ?? now
        let lastWeek = max(currentWeek, weekStart(of: lastDeadline, calendar: calendar))
        let firstWeek: Date
        if let weeks = period.weeks {
            firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeek) ?? currentWeek
        } else {
            let earliest = countedOffers.map(\.deadline).min() ?? now
            let start = min(currentWeek, weekStart(of: earliest, calendar: calendar))
            let floor = calendar.date(byAdding: .weekOfYear, value: -(maxWeeks - 1), to: lastWeek) ?? lastWeek
            firstWeek = max(start, floor)
        }
        let weekStarts = weeks(from: firstWeek, through: lastWeek, calendar: calendar)
        let windowEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: lastWeek) ?? lastWeek

        func inWindow(_ offer: Offer) -> Bool {
            // « Tout » garde aussi les lots plus vieux qu'un an dans les totaux.
            (period.weeks == nil || offer.deadline >= firstWeek) && offer.deadline < windowEnd
        }

        let offersInWindow = countedOffers.filter(inWindow)
        let ordersByOffer = Dictionary(grouping: countedOrders, by: \.offerId)

        var builders: [String: Builder] = [:]
        for offer in offersInWindow {
            let product = productsById[offer.productId]
            var builder = builders[offer.productId] ?? Builder(
                productId: offer.productId,
                name: product?.name ?? offer.shareUnit,
                category: product?.category,
                shareUnit: offer.shareUnit,
                weekStarts: weekStarts
            )
            builder.tierCount = max(builder.tierCount, offer.tiers.count)
            let week = weekStart(of: offer.deadline, calendar: calendar)
            for order in ordersByOffer[offer.id] ?? [] {
                let shares = max(0, order.committedShares)
                let revenue = VendorRepositoryQueries.projectedRevenue(of: order, offer: offer)
                let price = VendorRepositoryQueries.currentPrice(of: order, offer: offer)
                let savings = price.map { max(0, (product?.referenceGroceryPriceCents ?? $0) - $0) * shares } ?? 0
                let tierNumber = price == nil ? 0 : (order.currentTierIndex ?? -1) + 1

                builder.units += shares
                builder.revenue += revenue
                builder.savings += savings
                builder.households += max(0, order.committedHouseholds)
                builder.groups.insert(order.groupId)
                builder.orderCount += 1
                builder.tierSum += tierNumber
                builder.add(units: shares, revenue: revenue, week: week)
            }
            builders[offer.productId] = builder
        }

        let stats = builders.values
            .map { $0.stats }
            .sorted { lhs, rhs in
                if lhs.revenueCents != rhs.revenueCents { return lhs.revenueCents > rhs.revenueCents }
                if lhs.unitsSold != rhs.unitsSold { return lhs.unitsSold > rhs.unitsSold }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        let weekly = weekStarts.enumerated().map { index, start in
            ProductWeekPoint(
                weekStart: start,
                units: stats.reduce(0) { $0 + $1.weekly[index].units },
                revenueCents: stats.reduce(0) { $0 + $1.weekly[index].revenueCents }
            )
        }
        let allGroups = builders.values.reduce(into: Set<String>()) { $0.formUnion($1.groups) }

        return ProductStatsReport(
            period: period,
            products: stats,
            weekly: weekly,
            totalUnits: stats.reduce(0) { $0 + $1.unitsSold },
            totalRevenueCents: stats.reduce(0) { $0 + $1.revenueCents },
            totalSavingsCents: stats.reduce(0) { $0 + $1.savingsCents },
            groupCount: allGroups.count,
            householdCount: stats.reduce(0) { $0 + $1.householdCount }
        )
    }

    /// Tendance : dernière semaine avec des ventes contre la semaine avec des ventes qui la précède.
    static func trend(of weekly: [ProductWeekPoint]) -> ProductSalesTrend {
        let active = weekly.filter { $0.units > 0 }
        guard active.count >= 2 else { return .new }
        let last = active[active.count - 1].units
        let previous = active[active.count - 2].units
        guard previous > 0 else { return .new }
        let percent = Int((Double(last - previous) / Double(previous) * 100).rounded())
        if abs(percent) < 5 { return .flat }
        return percent > 0 ? .up(percent: percent) : .down(percent: -percent)
    }

    /// Moyenne mobile sur `window` semaines (les premières semaines utilisent ce qu'elles ont).
    static func movingAverage(of weekly: [ProductWeekPoint], window: Int = 3) -> [Double] {
        guard window > 0 else { return weekly.map { Double($0.units) } }
        return weekly.indices.map { index in
            let slice = weekly[max(0, index - window + 1)...index]
            return Double(slice.reduce(0) { $0 + $1.units }) / Double(slice.count)
        }
    }

    // MARK: - Semaines

    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func weeks(from first: Date, through last: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = first
        while cursor <= last, result.count <= maxWeeks + 60 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - Accumulateur

    private nonisolated struct Builder {
        var productId: String
        var name: String
        var category: Product.Category?
        var shareUnit: String
        var weekStarts: [Date]
        var units = 0
        var revenue: Cents = 0
        var savings: Cents = 0
        var households = 0
        var groups: Set<String> = []
        var orderCount = 0
        var tierSum = 0
        var tierCount = 0
        var weeklyUnits: [Date: Int] = [:]
        var weeklyRevenue: [Date: Cents] = [:]

        mutating func add(units: Int, revenue: Cents, week: Date) {
            weeklyUnits[week, default: 0] += units
            weeklyRevenue[week, default: 0] += revenue
        }

        var stats: ProductSalesStats {
            ProductSalesStats(
                productId: productId,
                name: name,
                category: category,
                shareUnit: shareUnit,
                unitsSold: units,
                revenueCents: revenue,
                groupCount: groups.count,
                householdCount: households,
                orderCount: orderCount,
                averageTier: orderCount > 0 ? Double(tierSum) / Double(orderCount) : nil,
                tierCount: tierCount,
                savingsCents: savings,
                weekly: weekStarts.map {
                    ProductWeekPoint(weekStart: $0, units: weeklyUnits[$0] ?? 0, revenueCents: weeklyRevenue[$0] ?? 0)
                }
            )
        }
    }
}
