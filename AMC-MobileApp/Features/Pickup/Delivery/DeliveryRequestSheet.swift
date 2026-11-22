import SwiftUI

/// Feuille « Demander une livraison » (RQ-069) : motif, commande, créneau, adresse privée, mot au bénévole.
/// La validation est celle de `VolunteerDelivery.request` ; son message s'affiche sous le formulaire.
struct DeliveryRequestSheet: View {
    let viewModel: VolunteerDeliveryViewModel
    @State private var draft: VolunteerDeliveryViewModel.Draft
    @State private var validationMessage: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field { case address, instructions, note }

    private static let durations: [(label: String, seconds: TimeInterval)] = [
        ("30 min", 30 * 60), ("1 h", 3_600), ("2 h", 2 * 3_600), ("3 h", 3 * 3_600), ("4 h", 4 * 3_600),
    ]

    init(viewModel: VolunteerDeliveryViewModel, draft: VolunteerDeliveryViewModel.Draft) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    private var content: VolunteerDeliveryViewModel.Content? { viewModel.state.value }
    private var isEligible: Bool { (content?.seniorMode ?? false) || draft.reducedMobility }

    var body: some View {
        NavigationStack {
            Form {
                reasonSection
                orderSection
                windowSection
                addressSection
                noteSection
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                    }
                    .grenierTransition(.banner)
                }
            }
            .scrollContentBackground(.hidden)
            .grenierBackground()
            .navigationTitle("Demander une livraison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if viewModel.isSubmitting { ProgressView() } else { Text("Envoyer") }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .disabled(!isEligible || viewModel.isSubmitting)
                }
            }
            .grenierHaptic(.warning, trigger: validationMessage) { _, new in new != nil }
            .grenierAnimation(.smooth, value: validationMessage)
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var reasonSection: some View {
        Section {
            if content?.seniorMode == true {
                Label("Mode aîné activé : tu as droit à la livraison.", systemImage: "figure.walk.motion")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
            } else {
                Toggle(isOn: $draft.reducedMobility) {
                    Label("J'ai une mobilité réduite", systemImage: "figure.roll")
                        .symbolRenderingMode(.hierarchical)
                }
                .tint(.grenier)
            }
        } header: {
            Label("Motif", systemImage: "heart.text.square.fill")
        } footer: {
            if !isEligible {
                Text("La livraison par un voisin est réservée aux aînés et aux personnes à mobilité réduite.")
            }
        }
    }

    private var orderSection: some View {
        Section {
            Picker(selection: $draft.orderId) {
                ForEach(content?.orderOptions ?? []) { option in
                    Text("\(option.productName) · \(option.share.quantity) × \(option.shareUnit)")
                        .tag(Optional(option.id))
                }
            } label: {
                Label("Commande", systemImage: "basket.fill").symbolRenderingMode(.hierarchical)
            }
        } header: {
            Label("Quoi livrer", systemImage: "shippingbox.fill")
        }
    }

    private var windowSection: some View {
        Section {
            DatePicker(selection: $draft.start, in: Date.now...Date.now.addingTimeInterval(VolunteerDelivery.maxAdvance),
                       displayedComponents: [.date, .hourAndMinute]) {
                Label("À partir de", systemImage: "clock.fill").symbolRenderingMode(.hierarchical)
            }
            Picker(selection: $draft.duration) {
                ForEach(Self.durations, id: \.seconds) { duration in
                    Text(duration.label).tag(duration.seconds)
                }
            } label: {
                Label("Pendant", systemImage: "hourglass").symbolRenderingMode(.hierarchical)
            }
            .pickerStyle(.menu)
        } header: {
            Label("Quand", systemImage: "calendar.badge.clock")
        } footer: {
            Text(NeighbourHelpFormat.window(start: draft.start, end: draft.start.addingTimeInterval(draft.duration)))
                .contentTransition(.numericText())
        }
    }

    private var addressSection: some View {
        Section {
            TextField("Adresse et appartement", text: $draft.address, axis: .vertical)
                .textContentType(.fullStreetAddress)
                .focused($focusedField, equals: .address)
            TextField("Indications (sonnette, étage…)", text: $draft.instructions)
                .focused($focusedField, equals: .instructions)
        } header: {
            Label("Où", systemImage: "house.fill")
        } footer: {
            Label("Seul le voisin qui te livre verra ton adresse, et seulement jusqu'à la livraison.",
                  systemImage: "lock.fill")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Un mot pour ton bénévole (facultatif)", text: $draft.note, axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .note)
        } header: {
            Label("Mot au bénévole", systemImage: "quote.bubble.fill")
        } footer: {
            Text("\(draft.note.count)/\(VolunteerDelivery.noteLimit)")
                .monospacedDigit()
                .foregroundStyle(draft.note.count > VolunteerDelivery.noteLimit ? Color.grenier : Color.texteSecondaire)
        }
    }

    private func send() async {
        focusedField = nil
        if let message = await viewModel.submit(draft) {
            validationMessage = message
        } else {
            dismiss()
        }
    }
}
