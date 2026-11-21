import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// F5 Cueillette (maquette `docs/maquettes/F5-cueillette.png`) : QR de la commande, point de cueillette, créneau et articles.
/// Branché sur `PickupViewModel` ; la luminosité passe au maximum tant que l'écran est affiché pour faciliter le scan.
struct PickupScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: PickupViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    StateView(
                        state: viewModel.state,
                        empty: .init(
                            title: "Aucune cueillette prévue",
                            systemImage: GrenierSymbol.qrCode,
                            message: "Réserve ta part d'un lot : ton code QR et ton créneau apparaîtront ici."
                        ),
                        retry: { await viewModel.load() }
                    ) { content in
                        PickupContentView(content: content)
                            .refreshable { await viewModel.load() }
                    }
                } else if context.groupId == nil {
                    ContentUnavailableView(
                        "Aucune cueillette prévue",
                        systemImage: GrenierSymbol.groups,
                        description: Text("Rejoins un groupe de ton quartier pour réserver ta première part.")
                    )
                } else {
                    ProgressView("Chargement…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Cueillette")
            .profileToolbar()
        }
        .task {
            guard viewModel == nil, let groupId = context.groupId else { return }
            let model = PickupViewModel(repositories: context.repositories, householdId: context.householdId, groupId: groupId)
            viewModel = model
            await model.load()
        }
    }
}

// MARK: - Contenu

private struct PickupContentView: View {
    let content: PickupViewModel.Content

    @Environment(\.openURL) private var openURL
    @State private var brightness = MaxBrightness()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PickupCountdownBanner(content: content)
                if let slot = content.slot {
                    Text(PickupFormat.slot(slot))
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .padding(.horizontal, 4)
                }
                PickupCodeCard(content: content)
                PickupItemsCard(items: content.items)
                PickupPointSummaryCard(content: content)
                directionsButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear { brightness.raise() }
        .onDisappear { brightness.restore() }
    }

    private var directionsButton: some View {
        Button {
            if let url = PickupFormat.mapsURL(for: content.pickupPoint) { openURL(url) }
        } label: {
            Label("Itinéraire", systemImage: "map")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Ouvre Plans avec l'itinéraire vers \(content.pickupPoint.name)")
    }
}

/// Bandeau façon Live Activity : « Cueillette dans 25 min · Chez Amina ».
private struct PickupCountdownBanner: View {
    let content: PickupViewModel.Content
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 52

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(Color.onAccent)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.grenier, in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PickupFormat.countdown(minutes: content.minutesUntilPickup(from: timeline.date)))
                        .font(.headline)
                        .foregroundStyle(.texte)
                        .contentTransition(.numericText())
                    Text(hostLine)
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
            .accessibilityElement(children: .combine)
        }
    }

    private var hostLine: String {
        if let host = content.hostFirstName {
            return "Chez \(host) · \(content.pickupPoint.address)"
        }
        return content.pickupPoint.address
    }
}

/// Grande carte du QR : « Montre ce code à Amina », « Commande GRN-1234 · 2 articles ».
private struct PickupCodeCard: View {
    let content: PickupViewModel.Content
    @ScaledMetric(relativeTo: .largeTitle) private var qrSize: CGFloat = 220

    var body: some View {
        VStack(spacing: 12) {
            PickupQRImage(payload: content.qrPayload)
                .frame(width: min(qrSize, 300), height: min(qrSize, 300))
                .padding(16)
                // Le QR reste noir sur blanc, même en sombre, pour que tous les lecteurs le scannent.
                .background(Color.white, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.piste))
                .accessibilityLabel("Code QR de la commande \(content.orderCode)")

            Text(hostInstruction)
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .multilineTextAlignment(.center)
            Text("Commande \(content.orderCode) · \(articles)")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
    }

    private var hostInstruction: String {
        content.hostFirstName.map { "Montre ce code à \($0)" } ?? "Montre ce code à ton hôte"
    }

    private var articles: String {
        content.items.count == 1 ? "1 article" : "\(content.items.count) articles"
    }
}

/// Liste des articles à récupérer.
private struct PickupItemsCard: View {
    let items: [PickupViewModel.Item]
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Color.piste) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { icon(item); name(item); Spacer(minLength: 8); quantity(item) }
                    VStack(alignment: .leading, spacing: 8) { icon(item); name(item); quantity(item) }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.isPickedUp ? "Déjà récupéré" : "")
            }
        }
        .grenierCard(padding: 16)
    }

    private func icon(_ item: PickupViewModel.Item) -> some View {
        Image(systemName: item.isPickedUp ? "checkmark.circle.fill" : PickupFormat.symbol(for: item.product.category))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(item.isPickedUp ? Color.economie : Color.grenier)
            .frame(width: iconSize, height: iconSize)
            .background((item.isPickedUp ? Color.economie : Color.grenier).opacity(0.12), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private func name(_ item: PickupViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.product.name).font(.body).foregroundStyle(.texte)
            Text(Money.format(item.totalCents))
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
        }
    }

    private func quantity(_ item: PickupViewModel.Item) -> some View {
        Text("\(item.quantity) × \(item.offer.shareUnit)")
            .font(.headline)
            .foregroundStyle(.texte)
            .monospacedDigit()
    }
}

/// Point de cueillette : nom, adresse, accessibilité.
private struct PickupPointSummaryCard: View {
    let content: PickupViewModel.Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.pickupPoint.name).font(.headline).foregroundStyle(.texte)
                    Text(content.pickupPoint.address).font(.subheadline).foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: "mappin.and.ellipse")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            if !content.pickupPoint.accessibility.isEmpty {
                Text(content.pickupPoint.accessibility.map(PickupFormat.title(for:)).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
            }
            HStack {
                Text("À payer à la cueillette").font(.subheadline).foregroundStyle(.texteSecondaire)
                Spacer(minLength: 8)
                Text(Money.format(content.totalCents)).priceStyle(.priceCompact).foregroundStyle(.texte)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

// MARK: - QR

/// QR code net (pixels non lissés), généré par Core Image.
private struct PickupQRImage: View {
    let payload: String

    var body: some View {
        if let image = Self.makeImage(payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: GrenierSymbol.qrCode)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.texte)
        }
    }

    static func makeImage(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - Luminosité

/// Monte la luminosité au maximum à l'apparition et la remet à sa valeur précédente au départ.
@MainActor
private struct MaxBrightness {
    private var previous: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
    }

    mutating func raise() {
        guard previous == nil, let screen else { return }
        previous = screen.brightness
        screen.brightness = 1
    }

    mutating func restore() {
        guard let previous, let screen else { return }
        screen.brightness = previous
        self.previous = nil
    }
}

// MARK: - Formatage

private enum PickupFormat {
    private static let locale = Locale(identifier: "fr_CA")

    /// « Cueillette dans 25 min », « Cueillette dans 3 h », « Cueillette dans 2 jours ».
    static func countdown(minutes: Int?) -> String {
        guard let minutes else { return "Créneau à confirmer" }
        switch minutes {
        case 0: return "C'est l'heure de ta cueillette"
        case ..<60: return "Cueillette dans \(minutes) min"
        case ..<(24 * 60): return "Cueillette dans \(minutes / 60) h"
        default:
            let days = minutes / (24 * 60)
            return days == 1 ? "Cueillette demain" : "Cueillette dans \(days) jours"
        }
    }

    /// « Jeudi 27 novembre · 17 h – 18 h 30 »
    static func slot(_ slot: PickupSlot) -> String {
        let day = slot.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return "\(day.prefix(1).uppercased())\(day.dropFirst()) · \(hour(slot.start)) – \(hour(slot.end))"
    }

    /// « 17 h » ou « 18 h 30 ».
    static func hour(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h \(String(format: "%02d", minute))"
    }

    static func mapsURL(for point: PickupPoint) -> URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "daddr", value: point.address), URLQueryItem(name: "dirflg", value: "w")]
        return components?.url
    }

    static func symbol(for category: Product.Category) -> String {
        switch category {
        case .grains, .flour: "bag.fill"
        case .legumes: "circle.grid.3x3.fill"
        case .oils: "drop.fill"
        case .canned: "cylinder.fill"
        case .eggs: "egg.fill"
        case .meat: "fork.knife"
        case .produce: "carrot.fill"
        case .household: "sparkles"
        }
    }

    static func title(for accessibility: PickupPoint.Accessibility) -> String {
        switch accessibility {
        case .wheelchair: "Accessible en fauteuil"
        case .stepFree: "Sans marche"
        case .elevator: "Ascenseur"
        case .nearMetro: "Près du métro"
        case .parking: "Stationnement"
        }
    }
}

// MARK: - Previews

/// Réserve la part d'Amina avant d'afficher l'écran, pour voir le QR et les articles.
private struct PickupPreviewHost: View {
    @State private var isReady = false

    var body: some View {
        if isReady {
            PickupScreen()
        } else {
            ProgressView().task {
                _ = try? await AppContext.instant.repositories.groupOrders.setShare(
                    quantity: 2, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
                )
                isReady = true
            }
        }
    }
}

#Preview("Clair") {
    PickupPreviewHost()
        .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    PickupPreviewHost()
        .environment(\.appContext, .instant)
        .preferredColorScheme(.dark)
}

#Preview("Vide") {
    PickupScreen()
        .environment(\.appContext, AppContext(
            repositories: .fake(behavior: .instant), userId: FakeData.ID.amina,
            householdId: "household-sans-part", groupId: FakeData.ID.saintMichel, vendorId: FakeData.ID.moulinsDuNord
        ))
}
