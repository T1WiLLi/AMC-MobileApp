// ReportSheet.swift
// Feuille de signalement (T-106, RQ-098). Présentée par `.reportable(target:)` ou `.reportSheet(item:)`.

import SwiftUI

struct ReportSheet: View {
    @State private var model: ReportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var commentFocused: Bool
    @State private var sealBounce = false

    init(target: ReportTarget, repository: any ReportRepository) {
        _model = State(initialValue: ReportViewModel(target: target, repository: repository))
    }

    init(model: ReportViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .sent {
                    thanks
                        .grenierTransition(.celebration)
                } else {
                    form
                }
            }
            .grenierAnimation(.smooth, value: model.phase)
            .navigationTitle(model.phase == .sent ? "" : String(localized: "Signaler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase != .sent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler", systemImage: "xmark") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .grenierHaptic(.success, trigger: model.phase) { _, new in new == .sent }
        .grenierHaptic(.error, trigger: model.phase) { _, new in
            if case .failed = new { true } else { false }
        }
        .onChange(of: model.phase) { _, new in
            if new == .sent {
                AccessibilityNotification.Announcement(String(localized: "Signalement envoyé. Merci, on regarde ça.")).post()
            }
        }
    }

    // MARK: Formulaire

    private var form: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.target.displayName)
                            .font(.headline)
                            .foregroundStyle(.texte)
                        Text("Seule l'équipe LeGrenier verra ton signalement.")
                            .font(.footnote)
                            .foregroundStyle(.texteSecondaire)
                    }
                } icon: {
                    Image(systemName: model.target.kind.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tu signales \(model.target.kind.demonstrative) : \(model.target.displayName)")
            }

            Section("Pourquoi signales-tu \(model.target.kind.demonstrative) ?") {
                ForEach(ReportReason.allCases) { reason in
                    reasonRow(reason)
                }
            }

            Section {
                TextField(
                    model.reason?.requiresComment == true ? String(localized: "Explique en quelques mots") : String(localized: "Précisions (facultatif)"),
                    text: $model.comment,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($commentFocused)
                .accessibilityLabel("Commentaire")
                .accessibilityHint(model.reason?.requiresComment == true ? String(localized: "Obligatoire pour le motif Autre.") : String(localized: "Facultatif."))
            } footer: {
                footer
            }
        }
        .scrollContentBackground(.hidden)
        .grenierBackground()
        .safeAreaInset(edge: .bottom) { submitButton }
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        let isSelected = model.reason == reason
        return Button {
            withGrenierAnimation(.snappy, reduceMotion: reduceMotion) { model.reason = reason }
            if reason.requiresComment { commentFocused = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: reason.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire)
                    .imageScale(.large)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reason.title).font(.body).foregroundStyle(.texte)
                    Text(reason.subtitle).font(.caption).foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.grenier : Color.texteSecondaire)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .grenierHaptic(.selection, trigger: isSelected) { _, new in new }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reason.title)
        .accessibilityHint(reason.subtitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var footer: some View {
        if case .failed(let error) = model.phase {
            Label(error.message, systemImage: error.systemImage)
                .foregroundStyle(Color.grenier)
        } else if let message = model.validationMessage {
            Label(message, systemImage: "exclamationmark.bubble")
                .foregroundStyle(Color.grenier)
        } else {
            Text("\(model.comment.count)/\(ReportViewModel.commentMaxLength)")
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("\(model.comment.count) caractères sur \(ReportViewModel.commentMaxLength)")
        }
    }

    private var submitButton: some View {
        Button {
            commentFocused = false
            Task { await model.submit() }
        } label: {
            Group {
                if model.isSending {
                    ProgressView()
                } else {
                    Label(
                        model.phase.isFailure ? String(localized: "Réessayer") : String(localized: "Envoyer le signalement"),
                        systemImage: model.phase.isFailure ? "arrow.clockwise" : "flag.fill"
                    )
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .disabled(!model.canSubmit)
        .accessibilityLabel(model.isSending ? String(localized: "Envoi en cours") : (model.phase.isFailure ? String(localized: "Réessayer l'envoi") : String(localized: "Envoyer le signalement")))
        .accessibilityHint(model.reason == nil ? String(localized: "Choisis d'abord un motif.") : "")
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Merci

    private var thanks: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, options: .nonRepeating, value: sealBounce)
                .onAppear { if !reduceMotion { sealBounce.toggle() } }
                .accessibilityHidden(true)
            Text("Merci, on regarde ça")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .foregroundStyle(.texte)
            Text("L'équipe LeGrenier va examiner \(model.target.kind.demonstrative). La personne signalée ne voit pas qui a signalé.")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Fermer").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .accessibilityElement(children: .contain)
    }
}

private extension ReportViewModel.Phase {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

// MARK: - Previews

private struct ReportSheetPreviewHost: View {
    let repository: any ReportRepository
    @State private var isPresented = true

    var body: some View {
        Button("Ouvrir le signalement") { isPresented = true }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .sheet(isPresented: $isPresented) {
                ReportSheet(target: .vendor(id: "ferme-rive", name: "Ferme de la Rive"), repository: repository)
            }
    }
}

#Preview("Signaler") {
    ReportSheetPreviewHost(repository: InMemoryReportRepository(behavior: .realistic))
}

#Preview("Signaler sombre") {
    ReportSheetPreviewHost(repository: InMemoryReportRepository(behavior: .realistic))
        .preferredColorScheme(.dark)
}

#Preview("Signaler hors ligne") {
    ReportSheetPreviewHost(repository: InMemoryReportRepository(behavior: .failing()))
}
