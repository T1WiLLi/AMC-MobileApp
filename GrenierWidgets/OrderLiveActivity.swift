// OrderLiveActivity.swift
// Live Activity de la commande (RQ-085) : écran verrouillé, Dynamic Island compacte, minimale et étendue.
// Tous les textes viennent de OrderActivityPresentation (Shared/), testée côté app.

import ActivityKit
import SwiftUI
import WidgetKit

struct OrderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GrenierOrderAttributes.self) { context in
            OrderLockScreenView(presentation: OrderActivityPresentation(context.attributes, context.state))
                .activityBackgroundTint(GrenierPalette.fond)
                .activitySystemActionForegroundColor(GrenierPalette.accent)
        } dynamicIsland: { context in
            let presentation = OrderActivityPresentation(context.attributes, context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StageBadge(presentation: presentation, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeroValue(presentation: presentation, onDark: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.attributes.productName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(presentation.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(presentation.headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GrenierPalette.accent)
                            .contentTransition(.numericText())
                            .lineLimit(2)
                        SegmentsBar(
                            fills: presentation.segmentFills,
                            labels: presentation.segmentLabels,
                            highlighted: presentation.highlightedSegment,
                            height: 6,
                            track: .white.opacity(0.18),
                            labelColor: .white.opacity(0.6),
                            highlightColor: .white
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: presentation.stageSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GrenierPalette.accent)
                    .contentTransition(.symbolEffect(.replace))
            } compactTrailing: {
                Text(presentation.compactTrailingText)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(GrenierPalette.accent)
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: presentation.stageSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GrenierPalette.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .keylineTint(GrenierPalette.accent)
        }
    }
}

// MARK: - Écran verrouillé

struct OrderLockScreenView: View {
    let presentation: OrderActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                StageBadge(presentation: presentation, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.attributes.productName)
                        .font(.headline)
                        .foregroundStyle(GrenierPalette.texte)
                    Text(presentation.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GrenierPalette.texteSecondaire)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                HeroValue(presentation: presentation, onDark: false)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GrenierPalette.accent)
                    .contentTransition(.numericText())
                    .lineLimit(2)
                Text(presentation.detail)
                    .font(.footnote)
                    .foregroundStyle(GrenierPalette.texteSecondaire)
                    .lineLimit(1)
            }

            SegmentsBar(
                fills: presentation.segmentFills,
                labels: presentation.segmentLabels,
                highlighted: presentation.highlightedSegment
            )
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

// MARK: - Morceaux partagés

/// Carré d'icône de l'étape : symbole hiérarchique sur fond Grenier (plein quand un palier tombe).
struct StageBadge: View {
    let presentation: OrderActivityPresentation
    var size: CGFloat = 44

    private var isCelebration: Bool { presentation.state.stage == .palierFranchi }

    var body: some View {
        Image(systemName: presentation.stageSymbol)
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isCelebration ? Color.white : GrenierPalette.accent)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(
                isCelebration ? AnyShapeStyle(GrenierPalette.accent) : AnyShapeStyle(GrenierPalette.accent.opacity(0.15)),
                in: .rect(cornerRadius: size * 0.3)
            )
            .accessibilityHidden(true)
    }
}

/// Valeur vedette à droite : le prix (avec l'ancien barré quand un palier tombe), puis l'heure de cueillette.
struct HeroValue: View {
    let presentation: OrderActivityPresentation
    let onDark: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if presentation.showsPrice {
                if let previous = presentation.previousPriceCents {
                    Text(GrenierFormat.price(previous))
                        .font(.caption.weight(.medium))
                        .strikethrough()
                        .foregroundStyle(onDark ? Color.white.opacity(0.6) : GrenierPalette.texteSecondaire)
                }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(presentation.priceText)
                        .font(.title2.bold())
                        .contentTransition(.numericText(value: Double(presentation.state.currentPriceCents)))
                    Text("/\(presentation.attributes.unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(onDark ? Color.white.opacity(0.7) : GrenierPalette.texteSecondaire)
                }
            } else {
                Text(presentation.state.stage == .recuperee ? String(localized: "Merci") : presentation.pickupTimeText)
                    .font(.title2.bold())
                    .contentTransition(.numericText())
                Text(presentation.state.stage == .recuperee ? String(localized: "récupérée") : String(localized: "cueillette"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(onDark ? Color.white.opacity(0.7) : GrenierPalette.texteSecondaire)
            }
        }
        .fontDesign(.rounded)
        .monospacedDigit()
        .foregroundStyle(GrenierPalette.accent)
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Previews

private typealias PreviewState = GrenierOrderAttributes.ContentState

#Preview("Écran verrouillé", as: .content, using: GrenierOrderAttributes.demo) {
    OrderLiveActivity()
} contentStates: {
    PreviewState.demo(.ouverte)
    PreviewState.demo(.palierFranchi)
    PreviewState.demo(.enRoute)
    PreviewState.demo(.arrivee)
    PreviewState.demo(.recuperee)
}

#Preview("Dynamic Island étendue", as: .dynamicIsland(.expanded), using: GrenierOrderAttributes.demo) {
    OrderLiveActivity()
} contentStates: {
    PreviewState.demo(.ouverte)
    PreviewState.demo(.palierFranchi)
    PreviewState.demo(.enRoute)
    PreviewState.demo(.arrivee)
    PreviewState.demo(.recuperee)
}

#Preview("Dynamic Island compacte", as: .dynamicIsland(.compact), using: GrenierOrderAttributes.demo) {
    OrderLiveActivity()
} contentStates: {
    PreviewState.demo(.ouverte)
    PreviewState.demo(.palierFranchi)
    PreviewState.demo(.enRoute)
    PreviewState.demo(.arrivee)
    PreviewState.demo(.recuperee)
}

#Preview("Dynamic Island minimale", as: .dynamicIsland(.minimal), using: GrenierOrderAttributes.demo) {
    OrderLiveActivity()
} contentStates: {
    PreviewState.demo(.ouverte)
    PreviewState.demo(.palierFranchi)
    PreviewState.demo(.enRoute)
    PreviewState.demo(.arrivee)
    PreviewState.demo(.recuperee)
}
