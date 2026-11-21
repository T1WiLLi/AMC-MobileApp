import SwiftUI

/// RQ-063 (T-077) : le coordonnateur choisit le point de cueillette de la commande et ses créneaux.
struct PickupPointPickerScreen: View {
    @State private var viewModel: PickupPointPickerViewModel

    init(viewModel: PickupPointPickerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.state, retry: { await viewModel.load() }) { content in
            if content.isCoordinator {
                PickerContent(viewModel: viewModel, content: content)
            } else {
                ContentUnavailableView(
                    "Réservé aux coordonnateurs",
                    systemImage: "person.badge.key.fill",
                    description: Text("Seuls les coordonnateurs de \(content.group.name) choisissent le point de cueillette.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Point de cueillette")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { if viewModel.state.value == nil { await viewModel.load() } }
        .grenierHaptic(.success, trigger: viewModel.savedOrder)
    }
}

private struct PickerContent: View {
    let viewModel: PickupPointPickerViewModel
    let content: PickupPointPickerViewModel.Content
    @State private var showsValidation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Où les voisins viennent chercher", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .foregroundStyle(.texte)
                ForEach(content.points) { point in
                    PointChoiceCard(
                        point: point,
                        demand: content.order.committedShares,
                        isSelected: viewModel.selectedPointId == point.id
                    ) {
                        viewModel.selectPoint(id: point.id)
                    }
                }

                HStack {
                    Label("Créneaux", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Spacer()
                    Button {
                        viewModel.addSlot()
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, 8)

                if content.reservedHouseholds > 0 {
                    Label("\(content.reservedHouseholds) ménages ont déjà réservé. Retirer leur créneau annule leur réservation.",
                          systemImage: "exclamationmark.bubble.fill")
                        .font(.footnote)
                        .foregroundStyle(.texteSecondaire)
                }

                if viewModel.slots.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun créneau", systemImage: "calendar")
                    } description: {
                        Text("Choisis un point pour reprendre ses horaires, ou ajoute un créneau.")
                    }
                    .grenierCard()
                } else {
                    ForEach(viewModel.slots, id: \.start) { slot in
                        SlotEditorCard(viewModel: viewModel, slot: slot)
                            .grenierTransition(.cardAppear)
                    }
                }

                if showsValidation, let error = viewModel.validationError ?? viewModel.saveError {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.grenier)
                        .grenierTransition(.banner)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .grenierAnimation(.smooth, value: viewModel.slots)
        }
        .grenierScrollEdge()
        .safeAreaInset(edge: .bottom) { saveBar }
        .grenierHaptic(.warning, trigger: showsValidation) { _, new in new }
    }

    private var saveBar: some View {
        Button {
            guard viewModel.validationError == nil else {
                showsValidation = true
                return
            }
            Task { showsValidation = await viewModel.save() == nil }
        } label: {
            Label(viewModel.savedOrder != nil && !viewModel.hasChanges ? "Enregistré" : "Confirmer le point",
                  systemImage: viewModel.savedOrder != nil && !viewModel.hasChanges ? "checkmark.seal.fill" : "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentTransition(.symbolEffect(.replace))
                .overlay(alignment: .trailing) {
                    if viewModel.isSaving { ProgressView().tint(.onAccent) }
                }
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(!viewModel.hasChanges || viewModel.isSaving)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct PointChoiceCard: View {
    let point: PickupPoint
    /// Parts déjà engagées dans la commande (pour signaler un point trop petit).
    let demand: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.grenier : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.name).font(.headline).foregroundStyle(.texte)
                    Text(point.address).font(.subheadline).foregroundStyle(.texteSecondaire)
                    Label(capacityText, systemImage: tooSmall ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tooSmall ? Color.grenier : Color.secondary)
                    AccessibilityBadges(options: point.accessibility)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isSelected ? Color.grenier : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .pressable()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .grenierHaptic(.selection, trigger: isSelected) { _, new in new }
    }

    private var tooSmall: Bool { point.capacity < demand }

    private var capacityText: String {
        tooSmall ? "\(point.capacity) parts max · \(demand) déjà engagées" : "Jusqu'à \(point.capacity) parts"
    }
}

private struct SlotEditorCard: View {
    let viewModel: PickupPointPickerViewModel
    let slot: PickupSlot

    private static let durations = [30, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker(
                    "Début",
                    selection: Binding(get: { slot.start }, set: { viewModel.moveSlot(start: slot.start, to: $0) }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    viewModel.removeSlot(start: slot.start)
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Retirer le créneau du \(SlotFormat.day(slot.start))")
            }
            Picker("Durée", selection: Binding(
                get: { Int(slot.end.timeIntervalSince(slot.start) / 60) },
                set: { viewModel.setDuration(start: slot.start, minutes: $0) }
            )) {
                ForEach(Self.durations, id: \.self) { minutes in
                    Text(SlotFormat.duration(minutes: minutes)).tag(minutes)
                }
                if !Self.durations.contains(currentMinutes) {
                    Text(SlotFormat.duration(minutes: currentMinutes)).tag(currentMinutes)
                }
            }
            .pickerStyle(.menu)
            Stepper(
                value: Binding(
                    get: { slot.capacity ?? PickupPointPickerViewModel.defaultSlotCapacity },
                    set: { viewModel.setCapacity(start: slot.start, capacity: $0) }
                ),
                in: 1...PickupSlotBook.maxSlotCapacity
            ) {
                Label("\(slot.capacity ?? PickupPointPickerViewModel.defaultSlotCapacity) ménages au plus",
                      systemImage: "person.2.fill")
                    .contentTransition(.numericText())
            }
        }
        .grenierCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Créneau \(SlotFormat.day(slot.start)), \(SlotFormat.range(slot))")
    }

    private var currentMinutes: Int { Int(slot.end.timeIntervalSince(slot.start) / 60) }
}

#Preview("Coordonnatrice") {
    NavigationStack {
        PickupPointPickerScreen(viewModel: PickupPointPickerViewModel(
            repositories: .fake(behavior: .instant), userId: FakeData.ID.amina, groupOrderId: FakeData.ID.potatoOrder
        ))
    }
}

#Preview("Sombre") {
    NavigationStack {
        PickupPointPickerScreen(viewModel: PickupPointPickerViewModel(
            repositories: .fake(), userId: FakeData.ID.amina, groupOrderId: FakeData.ID.potatoOrder
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("Membre (pas coordonnateur)") {
    NavigationStack {
        PickupPointPickerScreen(viewModel: PickupPointPickerViewModel(
            repositories: .fake(behavior: .instant), userId: "user-voisin", groupOrderId: FakeData.ID.potatoOrder
        ))
    }
}
