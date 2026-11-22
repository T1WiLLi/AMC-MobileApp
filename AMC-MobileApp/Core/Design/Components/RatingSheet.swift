import SwiftUI

/// Feuille de notation commune (producteurs T-157, groupes T-174) : 1 à 5 étoiles animées (rebond et retour
/// haptique à chaque choix) et un commentaire court facultatif. Préremplie avec l'avis existant du ménage.
///
///     .sheet(isPresented: $rates) {
///         RatingSheet(title: "Voisins de Saint-Michel", prompt: "Comment ça se passe dans ce groupe ?",
///                     context: .init(text: "Membre depuis 3 mois", systemImage: "person.3.fill"),
///                     placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength,
///                     existingRating: mine?.rating, existingComment: mine?.comment) { rating, comment in
///             await model.save(rating: rating, comment: comment)
///         }
///     }
struct RatingSheet: View {
    /// Ligne de contexte sous le titre (« Carottes nantaises · il y a 9 jours »).
    struct Context {
        var text: String
        var systemImage: String
    }

    /// Titre de la barre (nom du producteur ou du groupe).
    let title: String
    /// Question du premier avis (« Comment était ton lot ? »).
    let prompt: String
    var context: Context?
    let placeholder: String
    let maxLength: Int
    let onSave: (Int, String) async -> AppError?

    private let isEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int
    @State private var comment: String
    @State private var isSaving = false
    @State private var error: AppError?
    @State private var savedCount = 0
    @FocusState private var commentFocused: Bool

    init(title: String, prompt: String, context: Context? = nil, placeholder: String, maxLength: Int,
         existingRating: Int? = nil, existingComment: String? = nil,
         onSave: @escaping (Int, String) async -> AppError?) {
        self.title = title
        self.prompt = prompt
        self.context = context
        self.placeholder = placeholder
        self.maxLength = maxLength
        self.onSave = onSave
        isEditing = existingRating != nil
        _rating = State(initialValue: existingRating ?? 0)
        _comment = State(initialValue: existingComment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: isEditing ? "pencil.and.list.clipboard" : "star.bubble.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.grenier)
                            .symbolEffect(.bounce, value: savedCount)
                            .accessibilityHidden(true)
                        Text(isEditing ? String(localized: "Modifie ton avis") : prompt)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        if let context {
                            Label(context.text, systemImage: context.systemImage)
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
                    TextField(placeholder, text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($commentFocused)
                        .onChange(of: comment) { _, new in
                            if new.count > maxLength { comment = String(new.prefix(maxLength)) }
                        }
                } header: {
                    Label("Commentaire (facultatif)", systemImage: "text.bubble")
                } footer: {
                    Text("Ton avis est signé de ton prénom et de l'initiale de ton nom. \(comment.count) sur \(maxLength) caractères.")
                        .monospacedDigit()
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
            .navigationTitle(title)
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
        RatingSheet(title: "Voisins de Saint-Michel", prompt: "Comment ça se passe dans ce groupe ?",
                    context: .init(text: "Membre du groupe", systemImage: "person.3.fill"),
                    placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength) { _, _ in nil }
    }
}

#Preview("Modifier, sombre") {
    Color.fond.sheet(isPresented: .constant(true)) {
        RatingSheet(title: "Cuisine collective Villeray", prompt: "Comment ça se passe dans ce groupe ?",
                    placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength,
                    existingRating: 4, existingComment: "Super ambiance !") { _, _ in .offline }
    }
    .preferredColorScheme(.dark)
}
