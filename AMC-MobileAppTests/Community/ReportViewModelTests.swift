import Foundation
import Testing
@testable import AMC_MobileApp

/// Signalement d'un contenu ou d'un membre (T-106, RQ-098).
@MainActor
struct ReportViewModelTests {
    private let target = ReportTarget.vendor(id: "ferme-rive", name: "Ferme de la Rive")
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(_ repository: InMemoryReportRepository = InMemoryReportRepository()) -> ReportViewModel {
        ReportViewModel(target: target, repository: repository, now: { fixedDate }, makeID: { "report-1" })
    }

    @Test func cannotSubmitWithoutReason() async throws {
        let repository = InMemoryReportRepository()
        let model = makeModel(repository)
        #expect(model.phase == .editing)
        #expect(!model.canSubmit)

        await model.submit()
        #expect(model.phase == .editing)
        #expect(try await repository.reports(for: target).isEmpty)
    }

    @Test func submitsReportWithTrimmedComment() async throws {
        let repository = InMemoryReportRepository()
        let model = makeModel(repository)
        model.reason = .scam
        model.comment = "  Demande un virement Interac hors de l'app \n"
        #expect(model.canSubmit)

        await model.submit()

        let expected = Report(
            id: "report-1", target: target, reason: .scam,
            comment: "Demande un virement Interac hors de l'app", createdAt: fixedDate
        )
        #expect(model.phase == .sent)
        #expect(model.submitted == expected)
        #expect(try await repository.reports(for: target) == [expected])
        #expect(!model.canSubmit)
    }

    @Test func emptyCommentIsStoredAsNil() async throws {
        let repository = InMemoryReportRepository()
        let model = makeModel(repository)
        model.reason = .inappropriate
        model.comment = "   "

        await model.submit()
        #expect(model.submitted?.comment == nil)
    }

    @Test func otherRequiresComment() {
        let model = makeModel()
        model.reason = .other
        #expect(!model.canSubmit)
        #expect(model.validationMessage == "Ajoute quelques mots pour « Autre ».")

        model.comment = "Lot en double"
        #expect(model.canSubmit)
        #expect(model.validationMessage == nil)
    }

    @Test func rejectsTooLongComment() {
        let model = makeModel()
        model.reason = .behavior
        model.comment = String(repeating: "a", count: ReportViewModel.commentMaxLength + 1)
        #expect(model.isCommentTooLong)
        #expect(!model.canSubmit)

        model.comment = String(repeating: "a", count: ReportViewModel.commentMaxLength)
        #expect(model.canSubmit)
    }

    @Test func failureKeepsFormAndAllowsRetry() async throws {
        let failing = InMemoryReportRepository(behavior: .failing(.offline))
        let model = makeModel(failing)
        model.reason = .behavior

        await model.submit()
        #expect(model.phase == .failed(.offline))
        #expect(model.submitted == nil)
        #expect(model.reason == .behavior)
        #expect(model.canSubmit)
    }

    @Test func submitsOnlyOnce() async throws {
        let repository = InMemoryReportRepository()
        let model = makeModel(repository)
        model.reason = .inappropriate

        await model.submit()
        await model.submit()
        #expect(try await repository.reports(for: target).count == 1)
    }

    @Test func repositoryFiltersByTarget() async throws {
        let other = ReportTarget.member(id: "u-42", name: "Karim B.")
        let older = Report(id: "a", target: target, reason: .scam, comment: nil, createdAt: fixedDate)
        let newer = Report(id: "b", target: target, reason: .other, comment: "x", createdAt: fixedDate.addingTimeInterval(60))
        let unrelated = Report(id: "c", target: other, reason: .behavior, comment: nil, createdAt: fixedDate)
        let repository = InMemoryReportRepository(reports: [older, unrelated, newer])

        #expect(try await repository.reports(for: target).map(\.id) == ["b", "a"])
        #expect(try await repository.reports(for: other).map(\.id) == ["c"])
    }

    @Test func reasonsCoverTheFourMotives() {
        #expect(ReportReason.allCases.map(\.title) == ["Contenu inapproprié", "Arnaque ou fraude", "Comportement", "Autre"])
        #expect(ReportReason.allCases.filter(\.requiresComment) == [.other])
    }
}
