import SwiftUI
import UIKit

/// Carte de cueillette (maquette F5) : grand QR de la part, « Montre ce code à Fatima »,
/// point de cueillette, adresse, créneau, compte à rebours et bouton « Itinéraire » vers Plans.
///
/// Pendant que la carte est à l'écran, la luminosité est poussée au maximum pour que le code se lise bien,
/// puis restaurée à la disparition (ou quand l'app passe en arrière-plan).
struct PickupQRCard: View {
    let share: Share
    let pickupPoint: PickupPoint
    let slot: PickupSlot
    /// Prénom de l'hôte qui scanne le code : « Fatima ».
    let hostName: String
    /// Sous le titre : « Commande GRN-4821 · 2 articles ».
    var detail: String?
    /// Temps de marche jusqu'au point ; ajouté au bouton : « Itinéraire · 6 min ».
    var walkingMinutes: Int?
    /// Pousse la luminosité au max à l'apparition. Désactivable (aperçus, tests, réglage).
    var boostsBrightness = true
    /// Affiche « Autre créneau » quand fourni.
    var onChangeSlot: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconSide: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var qrMaxSide: CGFloat = 240
    @State private var brightness = ScreenBrightness()

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                countdownBadge(now: context.date)
            }

            QRCodeImage(Self.qrPayload(for: share), correction: .quartile,
                        accessibilityLabel: "Code de cueillette de ta part")
                .padding(14)
                .background(Color.surface, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.piste, lineWidth: 1.5))
                .frame(maxWidth: min(qrMaxSide, 320))
                .accessibilityHint("Montre-le à \(hostName) pour récupérer ta part.")

            VStack(spacing: 4) {
                Text("Montre ce code à \(hostName)")
                    .font(.title3.bold())
                    .foregroundStyle(.texte)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.piste)

            VStack(alignment: .leading, spacing: 14) {
                infoRow(symbol: "mappin.and.ellipse", title: pickupPoint.name, subtitle: pickupPoint.address)
                infoRow(symbol: "calendar.badge.clock",
                        title: PickupSchedule.slotText(slot),
                        subtitle: "Créneau de cueillette")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            buttons
        }
        .grenierCard(padding: 20)
        .onAppear { if boostsBrightness { brightness.boost() } }
        .onDisappear { brightness.restore() }
        .onChange(of: scenePhase) { _, phase in
            guard boostsBrightness else { return }
            if phase == .active { brightness.boost() } else { brightness.restore() }
        }
    }

    // MARK: Morceaux

    private func countdownBadge(now: Date) -> some View {
        let state = PickupSchedule.state(now: now, slot: slot)
        return Label(PickupSchedule.countdownText(now: now, slot: slot), systemImage: state.symbol)
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(state == .finished ? Color.texteSecondaire : Color.grenier)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background((state == .finished ? Color.piste : Color.grenier.opacity(0.12)), in: .capsule)
            .contentTransition(.numericText())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func infoRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: iconSide, height: iconSide)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize || onChangeSlot == nil
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button {
                if let url = PickupSchedule.directionsURL(to: pickupPoint.address) { openURL(url) }
            } label: {
                Label(directionsTitle, systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityHint("Ouvre Plans avec le trajet à pied.")

            if let onChangeSlot {
                Button(action: onChangeSlot) {
                    Label("Autre créneau", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .fontWeight(.semibold)
        .tint(.texte)
    }

    private var directionsTitle: String {
        guard let walkingMinutes else { return "Itinéraire" }
        return "Itinéraire · \(walkingMinutes) min"
    }

    /// Contenu du QR : le code de la part s'il existe, sinon un identifiant stable dérivé du ménage.
    static func qrPayload(for share: Share) -> String {
        if let code = share.qrCode, !code.isEmpty { return code }
        return "grenier://part/\(share.householdId)"
    }
}

// MARK: - Créneau et compte à rebours

/// Textes du créneau de cueillette, en français du Canada (« Jeudi 27 novembre · 17 h – 18 h 30 »).
nonisolated enum PickupSchedule {
    enum State: Equatable {
        case upcoming
        case ongoing
        case finished

        var symbol: String {
            switch self {
            case .upcoming: "clock"
            case .ongoing: "figure.walk"
            case .finished: "checkmark.circle"
            }
        }
    }

    static let locale = Locale(identifier: "fr_CA")

    static func state(now: Date, slot: PickupSlot) -> State {
        if now < slot.start { return .upcoming }
        if now < slot.end { return .ongoing }
        return .finished
    }

    /// « Cueillette dans 25 min », « dans 2 h 15 », « dans 3 jours », « en cours jusqu'à 18 h 30 », « Créneau terminé ».
    static func countdownText(now: Date, slot: PickupSlot, calendar: Calendar = .current) -> String {
        switch state(now: now, slot: slot) {
        case .finished:
            return "Créneau terminé"
        case .ongoing:
            return "Cueillette en cours jusqu'à \(timeText(slot.end, calendar: calendar))"
        case .upcoming:
            let minutes = Int((slot.start.timeIntervalSince(now) / 60).rounded(.up))
            switch minutes {
            case ...1: return "Cueillette dans 1 min"
            case ..<60: return "Cueillette dans \(minutes) min"
            case ..<(24 * 60):
                let rest = minutes % 60
                return rest == 0 ? "Cueillette dans \(minutes / 60) h" : "Cueillette dans \(minutes / 60) h \(twoDigits(rest))"
            default:
                let days = minutes / (24 * 60)
                return "Cueillette dans \(days) \(days > 1 ? "jours" : "jour")"
            }
        }
    }

    /// « Jeudi 27 novembre · 17 h – 18 h 30 »
    static func slotText(_ slot: PickupSlot, calendar: Calendar = .current) -> String {
        "\(dayText(slot.start, calendar: calendar)) · \(timeText(slot.start, calendar: calendar)) – \(timeText(slot.end, calendar: calendar))"
    }

    /// « Jeudi 27 novembre »
    static func dayText(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.wide).day(.defaultDigits).month(.wide)
        let text = date.formatted(style)
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }

    /// « 17 h », « 18 h 30 »
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(twoDigits(minute))"
    }

    /// Trajet à pied dans Plans vers l'adresse du point de cueillette.
    static func directionsURL(to address: String) -> URL? {
        guard !address.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: address),
            URLQueryItem(name: "dirflg", value: "w")
        ]
        return components?.url
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

// MARK: - Luminosité

/// Pousse la luminosité de l'écran au max et retient l'ancienne valeur pour la restaurer.
@MainActor
@Observable
final class ScreenBrightness {
    private var saved: CGFloat?

    func boost() {
        guard saved == nil, let screen = Self.screen else { return }
        saved = screen.brightness
        screen.brightness = 1
    }

    func restore() {
        guard let saved else { return }
        Self.screen?.brightness = saved
        self.saved = nil
    }

    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}

// MARK: - Aperçus

#if DEBUG
enum PickupPreviewData {
    /// Jeudi 27 novembre 2025, 17 h – 18 h 30 (heure de Montréal).
    static let slot: PickupSlot = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        let start = calendar.date(from: DateComponents(year: 2025, month: 11, day: 27, hour: 17)) ?? .now
        return PickupSlot(start: start, end: start.addingTimeInterval(90 * 60))
    }()
    /// Un créneau qui commence dans 25 min, pour voir le compte à rebours vivre.
    static let soonSlot = PickupSlot(start: .now.addingTimeInterval(25 * 60), end: .now.addingTimeInterval(115 * 60))

    static let point = PickupPoint(
        id: "pickup-ogilvy", hostUserId: "user-fatima", name: "Chez Fatima",
        address: "7420 rue Ogilvy, Montréal", photoURL: nil, capacity: 30,
        accessibility: [.stepFree, .nearMetro], slots: [slot]
    )
    static let share = Share(
        householdId: "household-amina", quantity: 1, finalPriceCents: 2_600, isPaid: true,
        suspendedAmountCents: 0, subsidyCents: 0, qrCode: "grenier://part/GRN-4821", isPickedUp: false
    )

    static func card(slot: PickupSlot = soonSlot) -> some View {
        ScrollView {
            PickupQRCard(share: share, pickupPoint: point, slot: slot, hostName: "Fatima",
                         detail: "Commande GRN-4821 · 2 articles", walkingMinutes: 6,
                         boostsBrightness: false, onChangeSlot: {})
                .padding(16)
        }
        .grenierBackground()
    }
}

#Preview("Clair") {
    PickupPreviewData.card()
}

#Preview("Sombre") {
    PickupPreviewData.card()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    PickupPreviewData.card()
        .dynamicTypeSize(.accessibility5)
}
#endif
