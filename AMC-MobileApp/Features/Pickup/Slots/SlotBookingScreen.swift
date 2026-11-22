import SwiftUI

/// RQ-064 (T-077) : choisir son créneau de cueillette, places restantes en direct.
struct SlotBookingScreen: View {
    @State private var viewModel: SlotBookingViewModel

    init(viewModel: SlotBookingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(
            state: viewModel.state,
            empty: .init(
                title: "Pas encore de créneau",
                systemImage: "calendar.badge.clock",
                message: "Un créneau, c'est l'heure où tu passes chercher ton panier. Le coordonnateur du groupe n'en a pas encore proposé : actualise un peu plus tard."
            ),
            retry: { await viewModel.load() }
        ) { content in
            SlotBookingContent(viewModel: viewModel, content: content)
                .refreshable { await viewModel.load() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Mon créneau")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { if viewModel.state.value == nil { await viewModel.load() } }
        .grenierHaptic(.success, trigger: viewModel.confirmations)
        .grenierHaptic(.error, trigger: viewModel.actionError) { _, new in new != nil }
    }
}

private struct SlotBookingContent: View {
    let viewModel: SlotBookingViewModel
    let content: SlotBookingViewModel.Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let point = content.pickupPoint { PickupPointHeader(point: point) }
                ReservationBanner(content: content, viewModel: viewModel)
                if let error = viewModel.actionError {
                    Label(error.message, systemImage: error.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(Color.grenier)
                        .padding(.horizontal, 4)
                        .grenierTransition(.banner)
                }
                Label("Créneaux proposés", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.texte)
                    .padding(.top, 8)
                ForEach(Array(content.availability.enumerated()), id: \.element.id) { index, availability in
                    SlotCard(
                        availability: availability,
                        isMine: content.reservedStart == availability.slot.start,
                        isPast: viewModel.isPast(availability),
                        isPending: viewModel.pendingStart == availability.slot.start,
                        canReserve: viewModel.canReserve(availability)
                    ) {
                        Task { await viewModel.reserve(availability.slot.start) }
                    }
                    .grenierTransition(.cardAppear)
                    .animation(reduceMotion ? nil : .grenierSmooth.delay(Double(index) * 0.04), value: content)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .grenierScrollEdge()
        .grenierAnimation(.smooth, value: content)
    }
}

/// Point de cueillette en tête : nom, adresse et icônes d'accessibilité.
struct PickupPointHeader: View {
    let point: PickupPoint
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "house.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(point.name).font(.headline).foregroundStyle(.texte)
                Text(point.address).font(.subheadline).foregroundStyle(.texteSecondaire)
                AccessibilityBadges(options: point.accessibility)
            }
            Spacer(minLength: 0)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Petites pastilles d'accessibilité (« Sans marche », « Près du métro »).
struct AccessibilityBadges: View {
    let options: [PickupPoint.Accessibility]

    var body: some View {
        if !options.isEmpty {
            PickupFlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.grenier)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.grenier.opacity(0.12), in: .capsule)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// Bandeau « Ton créneau : samedi 10 h – 11 h » ou invitation à choisir.
private struct ReservationBanner: View {
    let content: SlotBookingViewModel.Content
    let viewModel: SlotBookingViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reserved == nil ? "calendar.badge.plus" : "checkmark.seal.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(reserved == nil ? Color.grenier : Color.economie)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.texte)
                Text(subtitle).font(.subheadline).foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 8)
            if reserved != nil {
                Button("Annuler", role: .destructive) {
                    Task { await viewModel.cancelReservation() }
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isSaving)
            }
        }
        .grenierCard()
        .accessibilityElement(children: .contain)
    }

    private var reserved: PickupSlot? {
        content.availability.first { $0.slot.start == content.reservedStart }?.slot
    }

    private var title: String {
        if content.myShare == nil { return String(localized: "Réserve d'abord une part") }
        guard let reserved else { return String(localized: "Choisis ton créneau") }
        return String(localized: "Ton créneau : \(SlotFormat.day(reserved.start))")
    }

    private var subtitle: String {
        if content.myShare == nil { return String(localized: "Les créneaux s'ouvrent aux ménages qui ont une part dans ce lot.") }
        guard let reserved else { return String(localized: "Ton hôte saura quand t'attendre.") }
        return SlotFormat.range(reserved)
    }
}

private struct SlotCard: View {
    let availability: PickupSlotBook.Availability
    let isMine: Bool
    let isPast: Bool
    let isPending: Bool
    let canReserve: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SlotFormat.day(availability.slot.start))
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Text(SlotFormat.range(availability.slot))
                            .font(.subheadline)
                            .foregroundStyle(.texteSecondaire)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    status
                }
                if let ratio = availability.fillRatio {
                    ProgressView(value: ratio)
                        .tint(availability.isFull ? Color.secondary : Color.grenier)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isMine ? Color.economie : Color.clear, lineWidth: 2)
            }
            .opacity(isPast ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .pressable()
        .disabled(!canReserve)
        .accessibilityLabel("\(SlotFormat.day(availability.slot.start)), \(SlotFormat.range(availability.slot))")
        .accessibilityValue(statusText)
        .accessibilityHint(canReserve ? String(localized: "Réserve ce créneau") : "")
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }

    @ViewBuilder private var status: some View {
        if isPending {
            ProgressView()
        } else {
            Label(statusText, systemImage: statusSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(statusColor.opacity(0.12), in: .capsule)
                .contentTransition(.numericText())
                .symbolEffect(.bounce, value: isMine)
        }
    }

    private var statusText: String {
        if isMine { return String(localized: "Réservé") }
        if isPast { return String(localized: "Passé") }
        if availability.isFull { return String(localized: "Complet") }
        guard let remaining = availability.remaining else { return String(localized: "Places libres") }
        return remaining == 1 ? String(localized: "1 place") : "\(remaining) places"
    }

    private var statusSymbol: String {
        if isMine { return "checkmark.circle.fill" }
        if isPast { return "clock.badge.xmark" }
        if availability.isFull { return "xmark.circle.fill" }
        return "person.2.fill"
    }

    private var statusColor: Color {
        if isMine { return .economie }
        if isPast || availability.isFull { return .secondary }
        return .grenier
    }
}

/// Formats des créneaux en français (« samedi 22 nov. », « 10 h – 11 h 30 »).
enum SlotFormat {
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(AppLanguage.formattingLocale))
    }

    static func hour(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
    }

    static func range(_ slot: PickupSlot) -> String { "\(hour(slot.start)) – \(hour(slot.end))" }

    /// « 30 min », « 1 h », « 1 h 30 ».
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }
}

/// Mise en page en lignes qui passent à la ligne (pastilles), utile en AX5.
struct PickupFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .init(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#Preview("Créneaux") {
    NavigationStack {
        SlotBookingScreen(viewModel: SlotBookingViewModel(
            repositories: .fake(behavior: .instant), householdId: "household-voisin-1",
            groupOrderId: FakeData.ID.potatoOrder
        ))
    }
}

#Preview("Sombre") {
    NavigationStack {
        SlotBookingScreen(viewModel: SlotBookingViewModel(
            repositories: .fake(), householdId: "household-voisin-1", groupOrderId: FakeData.ID.potatoOrder
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack {
        SlotBookingScreen(viewModel: SlotBookingViewModel(
            repositories: .fake(behavior: .instant), householdId: "household-voisin-1",
            groupOrderId: FakeData.ID.potatoOrder
        ))
    }
    .dynamicTypeSize(.accessibility5)
}
