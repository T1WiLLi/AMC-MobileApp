import SwiftUI

// Petits éléments partagés par l'entraide entre voisins de la Cueillette :
// livraison à domicile (RQ-069, Delivery/) et covoiturage (RQ-070, Carpool/).

/// Formats en français du Québec : distances, heures, créneaux.
nonisolated enum NeighbourHelpFormat {
    private static var locale: Locale { AppLanguage.formattingLocale }

    /// « à 350 m », « à 1,2 km » ; « tout près » sous 100 m (même cellule de quartier).
    static func distance(_ meters: Double?) -> String? {
        guard let meters else { return nil }
        switch meters {
        case ..<100: return "Tout près"
        case ..<1_000: return "À \(Int((meters / 50).rounded()) * 50) m"
        default:
            let km = (meters / 100).rounded() / 10
            return "À \(km.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) km"
        }
    }

    /// « 17 h » ou « 18 h 30 ».
    static func hour(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }

    /// « Aujourd'hui », « Demain », « Jeudi 27 novembre ».
    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd'hui" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Demain"
        }
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « Demain · 13 h – 15 h ».
    static func window(start: Date, end: Date, now: Date = .now) -> String {
        "\(day(start, now: now)) · \(hour(start)) – \(hour(end))"
    }

    /// Plans, itinéraire à pied vers une adresse.
    static func walkingDirections(to address: String) -> URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: "w")]
        return components?.url
    }

    /// Initiales pour un avatar (« Mme Tremblay » → « T »).
    static func initial(of name: String) -> String {
        let words = name.split(separator: " ").filter { !["M.", "Mme", "Mlle"].contains($0) }
        return words.first.map { String($0.prefix(1)).uppercased() } ?? "?"
    }
}

/// En-tête de section : symbole teinté + titre (+ compteur animé).
struct NeighbourSectionHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .grenier
    var count: Int?

    var body: some View {
        HStack {
            Label {
                Text(title).font(.headline).foregroundStyle(.texte)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Info secondaire : symbole teinté + texte gris.
struct NeighbourInfoLabel: View {
    let text: String
    let systemImage: String
    var tint: Color = .grenier
    var font: Font = .subheadline

    var body: some View {
        Label {
            Text(text).foregroundStyle(.texteSecondaire)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(font)
    }
}

/// Pastille de statut (« En route », « Complet »…), symbole qui change en douceur.
struct NeighbourBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .grenier

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .font(.caption.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Avatar rond avec une initiale, teinté.
struct NeighbourAvatar: View {
    let name: String
    var tint: Color = .grenier
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 44

    var body: some View {
        Text(NeighbourHelpFormat.initial(of: name))
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .circle)
            .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Scène de réussite plein écran : sceau qui rebondit, titre, message. Se ferme d'un toucher.
struct NeighbourSuccessScene: View {
    let title: String
    let message: String
    var symbol = "checkmark.seal.fill"
    var satellites: [String] = ["house.fill", "heart.fill", "basket.fill"]
    let dismiss: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 120

    var body: some View {
        VStack(spacing: 20) {
            PickupSymbolScene(main: symbol, satellites: satellites, tint: .economie, diameter: min(diameter, 170))
            Text(title)
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .foregroundStyle(.texte)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
            Button(action: dismiss) {
                Label("Continuer", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.economie)
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(Color.surface, in: .rect(cornerRadius: 32))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
