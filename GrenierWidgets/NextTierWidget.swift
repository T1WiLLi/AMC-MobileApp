// NextTierWidget.swift
// Widget « Encore N familles pour le prochain palier » (RQ-086), small et medium.
// Timeline statique de démo : Parc-Ex Ouest passe de 24 à 25 familles sur le riz basmati de la Ferme Lafleur.

import SwiftUI
import WidgetKit

struct NextTierEntry: TimelineEntry {
    let date: Date
    let presentation: OrderActivityPresentation

    static func demo(families: Int, date: Date = .now) -> NextTierEntry {
        let state = GrenierOrderAttributes.ContentState(
            stage: .ouverte,
            committedFamilies: families,
            nextThreshold: families < 26 ? 26 : nil,
            currentPriceCents: families >= 26 ? 210 : (families >= 11 ? 260 : 320),
            pickupTime: GrenierOrderAttributes.demoPickupTime(now: date)
        )
        return NextTierEntry(date: date, presentation: OrderActivityPresentation(.demo, state))
    }
}

struct NextTierProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextTierEntry { .demo(families: 24) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextTierEntry) -> Void) {
        completion(.demo(families: 24))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextTierEntry>) -> Void) {
        let now = Date.now
        // Démo sans serveur : une famille de plus rejoint le groupe une heure plus tard.
        let entries = [
            NextTierEntry.demo(families: 24, date: now),
            NextTierEntry.demo(families: 25, date: now.addingTimeInterval(3600)),
        ]
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct NextTierWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ca.amc2026.mobileapp.next-tier", provider: NextTierProvider()) { entry in
            NextTierWidgetView(entry: entry)
                .containerBackground(GrenierPalette.fond, for: .widget)
        }
        .configurationDisplayName("Prochain palier")
        .description("Combien de familles il manque à ton groupe pour faire baisser le prix.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextTierWidgetView: View {
    let entry: NextTierEntry
    @Environment(\.widgetFamily) private var family

    private var presentation: OrderActivityPresentation { entry.presentation }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupLabel
            Spacer(minLength: 6)
            missingBlock
            Spacer(minLength: 8)
            SegmentsBar(fills: presentation.segmentFills, height: 6)
            Text(priceLine)
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(GrenierPalette.texteSecondaire)
                .padding(.top, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                groupLabel
                Spacer(minLength: 6)
                missingBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(GrenierPalette.accent)
                        .frame(width: 28, height: 28)
                        .background(GrenierPalette.accent.opacity(0.12), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(presentation.attributes.productName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GrenierPalette.texte)
                        Text(presentation.attributes.vendorName)
                            .font(.caption)
                            .foregroundStyle(GrenierPalette.texteSecondaire)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(presentation.priceText)
                        .font(.title3.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(GrenierPalette.texte)
                    if let next = presentation.nextTier {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GrenierPalette.texteSecondaire)
                        Text(GrenierFormat.price(next.priceCents))
                            .font(.title3.bold())
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(GrenierPalette.accent)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                SegmentsBar(
                    fills: presentation.segmentFills,
                    labels: presentation.segmentLabels.map { $0.components(separatedBy: " · ").last ?? $0 },
                    highlighted: presentation.currentTierIndex,
                    height: 6
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Morceaux

    private var groupLabel: some View {
        Label(presentation.attributes.groupName, systemImage: "person.3.fill")
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(GrenierPalette.accent)
            .lineLimit(1)
    }

    @ViewBuilder
    private var missingBlock: some View {
        if presentation.familiesMissing > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Encore")
                    .font(.subheadline)
                    .foregroundStyle(GrenierPalette.texteSecondaire)
                Text(OrderActivityPresentation.families(presentation.familiesMissing))
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(GrenierPalette.accent)
                    .contentTransition(.numericText(value: Double(presentation.familiesMissing)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(discountLine)
                    .font(.caption)
                    .foregroundStyle(GrenierPalette.texte)
                    .lineLimit(2)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GrenierPalette.accent)
                Text("Meilleur prix atteint")
                    .font(.headline)
                    .foregroundStyle(GrenierPalette.texte)
            }
        }
    }

    private var discountLine: String {
        if let percent = presentation.nextDiscountPercent { return "pour le prochain palier (−\(percent) %)" }
        return "pour le prochain palier"
    }

    private var priceLine: String {
        guard let next = presentation.nextTier else { return "\(presentation.priceText)/\(presentation.attributes.unit)" }
        return "\(presentation.priceText) → \(GrenierFormat.price(next.priceCents))/\(presentation.attributes.unit)"
    }

    private var accessibilityText: String {
        guard presentation.familiesMissing > 0 else {
            return "\(presentation.attributes.groupName) : meilleur prix atteint, \(presentation.priceText) le \(presentation.attributes.unit)."
        }
        return "\(presentation.attributes.groupName) : encore \(OrderActivityPresentation.families(presentation.familiesMissing)) "
            + "pour le prochain palier. \(priceLine)."
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NextTierWidget()
} timeline: {
    NextTierEntry.demo(families: 24)
    NextTierEntry.demo(families: 25)
    NextTierEntry.demo(families: 26)
}

#Preview("Medium", as: .systemMedium) {
    NextTierWidget()
} timeline: {
    NextTierEntry.demo(families: 24)
    NextTierEntry.demo(families: 25)
}
