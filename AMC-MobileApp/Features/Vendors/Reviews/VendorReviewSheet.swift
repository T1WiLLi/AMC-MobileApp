import SwiftUI

/// Feuille de notation d'un producteur (T-157) : 1 à 5 étoiles et un commentaire facultatif.
/// Préremplie avec l'avis existant du ménage (un seul avis par ménage, modifiable).
///
///     .sheet(isPresented: $rates) {
///         VendorReviewSheet(vendorName: "Ferme Bio-Rive", saleText: "Carottes nantaises, il y a 9 jours",
///                           existing: myReview) { rating, comment in await model.saveReview(rating: rating, comment: comment) }
///     }
struct VendorReviewSheet: View {
    let vendorName: String
    /// Le lot reçu qui permet de noter (« Carottes nantaises · il y a 9 jours »), nil si inconnu.
    var saleText: String?
    var existing: VendorReview?
    /// Enregistre ; renvoie l'erreur à afficher, nil si c'est enregistré.
    let onSave: (Int, String) async -> AppError?

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int
    @State private var comment: String
    @State private var isSaving = false
    @State private var error: AppError?
    @State private var savedCount = 0
    @FocusState private var commentFocused: Bool

    init(vendorName: String, saleText: String? = nil, existing: VendorReview? = nil,
         onSave: @escaping (Int, String) async -> AppError?) {
        self.vendorName = vendorName
        self.saleText = saleText
        self.existing = existing
        self.onSave = onSave
        _rating = State(initialValue: existing?.rating ?? 0)
        _comment = State(initialValue: existing?.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: existing == nil ? "star.bubble.fill" : "pencil.and.list.clipboard")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                            .accessibilityHidden(true)
                        Text(existing == nil ? "Comment était ton lot ?" : "Modifie ton avis")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        if let saleText {
                            Label(saleText, systemImage: "shippingbox.fill")
                                .font(.subheadline)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.texteSecondaire)
                                .multilineTextAlignment(.center)
                        }
                        StarRatingPicker(rating: $rating)
                            .padding(.top, 4)
                        Text(StarRatingText.label(for: rating))
                            .font(.headline)
                            .foregroundStyle(rating == 0 ? Color.texteSecondaire : Color.texte)
                            .contentTransition(.opacity)
                            .grenierAnimation(.snappy, value: rating)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    TextField("Fraîcheur, ponctualité, quantité…", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($commentFocused)
                        .onChange(of: comment) { _, new in
                            if new.count > VendorReview.maxCommentLength {
                                comment = String(new.prefix(VendorReview.maxCommentLength))
                            }
                        }
                } header: {
                    Label("Commentaire (facultatif)", systemImage: "text.bubble")
                } footer: {
                    Text("Ton avis est signé de ton prénom et de l'initiale de ton nom. \(comment.count) sur \(VendorReview.maxCommentLength) caractères.")
                }

                if let error {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(error.title).font(.headline)
                                Text(error.message).font(.subheadline).foregroundStyle(Color.texteSecondaire)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(vendorName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Publier", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .disabled(rating == 0 || isSaving)
                    .accessibilityHint(rating == 0 ? String(localized: "Choisis d'abord une note") : "")
                }
            }
            .grenierHaptic(.success, trigger: savedCount)
            .grenierHaptic(.error, trigger: error?.message)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        isSaving = true
        commentFocused = false
        let failure = await onSave(rating, comment)
        isSaving = false
        if let failure {
            withAnimation(.smooth) { error = failure }
        } else {
            savedCount += 1
            dismiss()
        }
    }
}

#Preview("Nouvel avis") {
    Color.fond.sheet(isPresented: .constant(true)) {
        VendorReviewSheet(vendorName: "Ferme Bio-Rive", saleText: "Carottes nantaises · il y a 9 jours") { _, _ in nil }
    }
}

#Preview("Modifier, sombre") {
    Color.fond.sheet(isPresented: .constant(true)) {
        VendorReviewSheet(vendorName: "Le Fournil du coin", existing: FakeData.demoVendorReviews[8]) { _, _ in .offline }
    }
    .preferredColorScheme(.dark)
}
