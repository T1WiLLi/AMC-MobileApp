import SwiftUI

/// Étoiles en lecture (moyenne, demi-étoiles comprises) : « ★★★★½ ». Décoratif pour VoiceOver :
/// le parent dit la note en mots.
struct StarRatingView: View {
    let rating: Double
    var font: Font = .subheadline

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .foregroundStyle(.orange)
            }
        }
        .font(font)
        .symbolRenderingMode(.hierarchical)
        .accessibilityHidden(true)
    }

    private func symbol(for star: Int) -> String {
        let value = rating - Double(star - 1)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Choix de 1 à 5 étoiles : cibles de 44 pt, rebond à chaque choix, ajustable au balayage VoiceOver.
struct StarRatingPicker: View {
    @Binding var rating: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { rating = star }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(star <= rating ? Color.orange : Color.texteSecondaire.opacity(0.5))
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : (star == rating ? rating : 0))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note")
        .accessibilityValue(rating == 0 ? String(localized: "aucune") : FrenchPlural.count(rating, String(localized: "étoile")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(1, rating - 1)
            @unknown default: break
            }
        }
    }
}

/// Phrase courte pour une note entière (sous les étoiles du formulaire).
enum StarRatingText {
    static func label(for rating: Int) -> String {
        switch rating {
        case 1: String(localized: "Décevant")
        case 2: String(localized: "Moyen")
        case 3: String(localized: "Correct")
        case 4: String(localized: "Très bien")
        case 5: String(localized: "Excellent !")
        default: String(localized: "Touche une étoile")
        }
    }

    /// « 4,7 » en français.
    static func average(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.formattingLocale))
    }
}

#Preview("Étoiles") {
    @Previewable @State var rating = 4
    VStack(spacing: 24) {
        StarRatingView(rating: 4.7, font: .title2)
        StarRatingView(rating: 3.4)
        StarRatingPicker(rating: $rating)
        Text(StarRatingText.label(for: rating))
    }
    .padding()
}
