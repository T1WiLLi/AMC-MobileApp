// ReportViewModel.swift
// Feuille de signalement (T-106, RQ-098) : choix du motif, commentaire facultatif, envoi.
//
// Usage :
//   @State private var model = ReportViewModel(target: .vendor(id: "v1", name: "Ferme de la Rive"),
//                                              repository: InMemoryReportRepository())
//   Button("Envoyer") { Task { await model.submit() } }.disabled(!model.canSubmit)

import Foundation
import Observation

@Observable @MainActor
final class ReportViewModel {
    enum Phase: Equatable {
        case editing
        case sending
        case sent
        case failed(AppError)
    }

    static let commentMaxLength = 500

    let target: ReportTarget
    var reason: ReportReason?
    var comment: String = ""
    private(set) var phase: Phase = .editing
    /// Signalement enregistré, une fois envoyé.
    private(set) var submitted: Report?

    private let repository: any ReportRepository
    private let now: () -> Date
    private let makeID: () -> String

    init(
        target: ReportTarget,
        repository: any ReportRepository,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.target = target
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    /// Commentaire sans espaces autour ; `nil` s'il est vide.
    var trimmedComment: String? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isCommentTooLong: Bool { comment.count > Self.commentMaxLength }

    /// Ce qui manque pour envoyer, à afficher sous le formulaire.
    var validationMessage: String? {
        if isCommentTooLong { return String(localized: "Le commentaire dépasse \(Self.commentMaxLength) caractères.") }
        if reason?.requiresComment == true, trimmedComment == nil { return String(localized: "Ajoute quelques mots pour « Autre ».") }
        return nil
    }

    var canSubmit: Bool {
        guard reason != nil, validationMessage == nil else { return false }
        switch phase {
        case .editing, .failed: return true
        case .sending, .sent: return false
        }
    }

    var isSending: Bool { phase == .sending }

    /// Envoie le signalement. Ne fait rien si le formulaire est incomplet ou déjà envoyé.
    func submit() async {
        guard canSubmit, let reason else { return }
        phase = .sending
        let report = Report(id: makeID(), target: target, reason: reason, comment: trimmedComment, createdAt: now())
        do {
            try await repository.submit(report)
            submitted = report
            phase = .sent
        } catch {
            phase = .failed(AppError(error))
        }
    }
}
