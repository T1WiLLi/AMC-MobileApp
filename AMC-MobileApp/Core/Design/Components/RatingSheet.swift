import SwiftUI

/// Feuille de notation commune (producteurs T-157, groupes T-174) : 1 à 5 étoiles animées (rebond et retour
/// haptique à chaque choix), des mots rapides qui remplissent le commentaire et un commentaire court facultatif.
/// Préremplie avec l'avis existant du ménage.
/// Refonte (retour samuel) : fond crème opaque, en-tête avec le groupe ou le producteur, cartes Grenier et une
/// seule action principale « Publier mon avis » en bas, comme « Rejoindre avec un code ».
///
///     .sheet(isPresented: $rates) {
///         RatingSheet(title: "Voisins de Saint-Michel", prompt: "Comment ça se passe dans ce groupe ?",
///                     context: .init(text: "Membre du groupe", systemImage: "person.3.fill"),
///                     subject: .init(photoURL: group.photoURL, systemImage: "person.3.fill"),
///                     suggestions: RatingCommentTags.group,
///                     placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength,
///                     existingRating: mine?.rating, existingComment: mine?.comment) { rating, comment in
///             await model.save(rating: rating, comment: comment)
///         }
///     }
struct RatingSheet: View {
    /// Ligne de contexte sous la question (« Carottes nantaises · il y a 9 jours »).
    struct Context {
        var text: String
        var systemImage: String
    }

    /// Ce qu'on note, pour l'en-tête : sa photo (sinon ses initiales) et le symbole posé en pastille.
    struct Subject {
        var photoURL: URL?
        var systemImage: String
    }

    /// Nom du producteur ou du groupe.
    let title: String
    /// Question du premier avis (« Comment était ton lot ? »).
    let prompt: String
    var context: Context?
    var subject: Subject
    /// Mots rapides proposés au-dessus du commentaire (vide : pas de pastilles).
    var suggestions: [String]
    let placeholder: String
    let maxLength: Int
    let onSave: (Int, String) async -> AppError?

    private let isEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rating: Int
    @State private var comment: String
    @State private var isSaving = false
    @State private var error: AppError?
    @State private var savedCount = 0
    @State private var refusedTag = 0
    @FocusState private var commentFocused: Bool
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 76
    @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 96

    init(title: String, prompt: String, context: Context? = nil,
         subject: Subject = .init(photoURL: nil, systemImage: "star.bubble.fill"), suggestions: [String] = [],
         placeholder: String, maxLength: Int, existingRating: Int? = nil, existingComment: String? = nil,
         onSave: @escaping (Int, String) async -> AppError?) {
        self.title = title
        self.prompt = prompt
        self.context = context
        self.subject = subject
        self.suggestions = suggestions
        self.placeholder = placeholder
        self.maxLength = maxLength
        self.onSave = onSave
        isEditing = existingRating != nil
        _rating = State(initialValue: existingRating ?? 0)
        _comment = State(initialValue: existingComment ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    starsCard
                    commentCard
                    if let error { errorCard(error) }
                }
                .padding(16)
                .grenierAnimation(.smooth, value: error?.message)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .grenierBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) { publishBar }
            .navigationTitle(isEditing ? String(localized: "Modifier mon avis") : String(localized: "Donner mon avis"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .grenierHaptic(.success, trigger: savedCount)
            .grenierHaptic(.error, trigger: error?.message)
            .grenierHaptic(.warning, trigger: refusedTag)
        }
        .tint(.grenier)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: En-tête

    private var hero: some View {
        VStack(spacing: 12) {
            // Aux tailles d'accessibilité, les étoiles remontent : pas d'avatar.
            if !dynamicTypeSize.isAccessibilitySize {
                AvatarView(name: title, photoURL: subject.photoURL, size: avatarSize, showsRing: true)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isEditing ? "pencil" : subject.systemImage)
                            .font(.system(size: avatarSize * 0.18, weight: .semibold))
                            .foregroundStyle(Color.onAccent)
                            .frame(width: avatarSize * 0.38, height: avatarSize * 0.38)
                            .background(Color.grenier, in: .circle)
                            .overlay { Circle().stroke(Color.fond, lineWidth: 3) }
                            .offset(x: 4, y: 4)
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : rating)
                    }
                    .accessibilityHidden(true)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .multilineTextAlignment(.center)
                Text(isEditing ? String(localized: "Modifie ton avis") : prompt)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.texte)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let context {
                Label(context.text, systemImage: context.systemImage)
                    .font(.footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.texteSecondaire)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surface, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        // Plafonné pour que les étoiles restent près du haut aux très grandes tailles.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: Étoiles

    private var starsCard: some View {
        VStack(spacing: 10) {
            StarRatingPicker(rating: $rating, tint: .grenier)
                // Cinq cibles de 44 pt et plus : au-delà d'AX2, elles ne tiendraient plus sur une ligne.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityHint("Balaie vers le haut ou le bas pour changer la note.")
            Text(StarRatingText.label(for: rating))
                .font(rating == 0 ? .subheadline.weight(.medium) : .title3.bold())
                .fontDesign(.rounded)
                .foregroundStyle(rating == 0 ? Color.texteSecondaire : Color.grenier)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .id(rating)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .grenierCard()
        .grenierAnimation(.bouncy, value: rating)
    }

    // MARK: Commentaire

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    commentHeader
                    Spacer(minLength: 8)
                    optionalBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    commentHeader
                    optionalBadge
                }
            }

            if !suggestions.isEmpty { tagChips }

            TextField(text: $comment, prompt: Text(placeholder).foregroundStyle(Color.texteSecondaire), axis: .vertical) {
                Text("Commentaire")
            }
            .lineLimit(4...10)
            .focused($commentFocused)
            .foregroundStyle(Color.texte)
            .frame(minHeight: editorHeight, alignment: .topLeading)
            .padding(12)
            .background(Color.fond, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(commentFocused ? Color.grenier : Color.piste, lineWidth: commentFocused ? 2 : 1)
            }
            .contentShape(.rect)
            .onTapGesture { commentFocused = true }
            .onChange(of: comment) { _, new in
                if new.count > maxLength { comment = String(new.prefix(maxLength)) }
            }
            .grenierAnimation(.snappy, value: commentFocused)

            let footer = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            footer {
                signatureNote
                    .frame(maxWidth: .infinity, alignment: .leading)
                characterCount
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }

    private var commentHeader: some View {
        Label {
            Text("Ton commentaire")
                .font(.headline)
                .foregroundStyle(Color.texte)
        } icon: {
            Image(systemName: "text.bubble.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .accessibilityAddTraits(.isHeader)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private var optionalBadge: some View {
        Text("Facultatif")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.texteSecondaire)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.fond, in: .capsule)
    }

    private var tagChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Touche un mot pour l'ajouter au commentaire.")
                .font(.caption)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            PickupFlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { tag in
                    tagChip(tag)
                }
            }
        }
        // Des pastilles plus grandes rempliraient l'écran sans rien apporter.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func tagChip(_ tag: String) -> some View {
        let isOn = RatingCommentTags.contains(tag, in: comment)
        return Button {
            if let updated = RatingCommentTags.toggled(tag, in: comment, maxLength: maxLength) {
                withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { comment = updated }
            } else {
                refusedTag += 1
            }
        } label: {
            Label {
                Text(tag).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Color.onAccent : Color.texte)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(isOn ? Color.grenier : Color.grenier.opacity(0.1), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(tag)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? String(localized: "Retire ce mot du commentaire.") : String(localized: "Ajoute ce mot au commentaire."))
        .grenierHaptic(.selection, trigger: isOn)
    }

    private var signatureNote: some View {
        Label("Signé de ton prénom et de l'initiale de ton nom.", systemImage: "signature")
            .font(.footnote)
            .foregroundStyle(Color.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var characterCount: some View {
        let count = comment.count
        let color: Color = count >= maxLength ? .red : count >= maxLength - 20 ? .orange : .texteSecondaire
        return Text(verbatim: "\(count)/\(maxLength)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(count)))
            .grenierAnimation(.snappy, value: count)
            .accessibilityLabel("\(count) sur \(maxLength) caractères")
    }

    // MARK: Erreur

    private func errorCard(_ error: AppError) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text(error.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
        .grenierTransition(.cardAppear)
    }

    // MARK: Action principale

    private var publishBar: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(Color.onAccent)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSaving ? LocalizedStringKey("Publication…") : LocalizedStringKey("Publier mon avis"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline)
            // Le bouton reste sur une ligne : au-delà d'AX2, il cacherait le formulaire.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .disabled(rating == 0 || isSaving)
        .accessibilityHint(rating == 0 ? String(localized: "Choisis d'abord une note") : "")
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        // Fondu crème derrière le bouton : le contenu qui défile dessous ne brouille pas son libellé.
        .background {
            LinearGradient(stops: [.init(color: Color.fond.opacity(0), location: 0),
                                   .init(color: Color.fond.opacity(0.92), location: 0.35),
                                   .init(color: Color.fond, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func save() async {
        isSaving = true
        commentFocused = false
        let failure = await onSave(rating, comment)
        isSaving = false
        if let failure {
            error = failure
        } else {
            error = nil
            savedCount += 1
            dismiss()
        }
    }
}

#Preview("Nouvel avis") {
    Color.fond.sheet(isPresented: .constant(true)) {
        RatingSheet(title: "Voisins de Saint-Michel", prompt: "Comment ça se passe dans ce groupe ?",
                    context: .init(text: "Membre du groupe", systemImage: "person.3.fill"),
                    subject: .init(photoURL: nil, systemImage: "person.3.fill"), suggestions: RatingCommentTags.group,
                    placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength) { _, _ in nil }
    }
}

#Preview("Modifier, sombre") {
    Color.fond.sheet(isPresented: .constant(true)) {
        RatingSheet(title: "Cuisine collective Villeray", prompt: "Comment ça se passe dans ce groupe ?",
                    subject: .init(photoURL: nil, systemImage: "person.3.fill"), suggestions: RatingCommentTags.group,
                    placeholder: "Organisation, ambiance, cueillettes…", maxLength: GroupRating.maxCommentLength,
                    existingRating: 4, existingComment: "Bonne ambiance") { _, _ in .offline }
    }
    .preferredColorScheme(.dark)
}
