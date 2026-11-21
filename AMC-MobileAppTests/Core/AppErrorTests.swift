import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct AppErrorTests {
    @Test func everyCaseHasUserFacingText() {
        let cases: [AppError] = [.offline, .unauthenticated, .permissionDenied, .notFound, .orderClosed, .invalidInput("Quantité invalide"), .unknown("x")]
        for error in cases {
            #expect(!error.title.isEmpty)
            #expect(!error.message.isEmpty)
            #expect(!error.systemImage.isEmpty)
        }
    }

    @Test func invalidInputShowsItsDetail() {
        #expect(AppError.invalidInput("Choisis au moins 1 kg").message == "Choisis au moins 1 kg")
    }

    @Test func onlyTransientErrorsAreRetryable() {
        #expect(AppError.offline.isRetryable)
        #expect(AppError.unknown("x").isRetryable)
        #expect(!AppError.orderClosed.isRetryable)
        #expect(!AppError.invalidInput("x").isRetryable)
        #expect(!AppError.permissionDenied.isRetryable)
    }

    @Test func urlErrorsMapToOffline() {
        #expect(AppError(URLError(.notConnectedToInternet)) == .offline)
        #expect(AppError(URLError(.timedOut)) == .offline)
    }

    @Test func appErrorPassesThrough() {
        #expect(AppError(AppError.notFound) == .notFound)
    }

    @Test func cancellationIsRecognized() {
        let error = AppError(CancellationError())
        #expect(error.isCancellation)
        #expect(!AppError.offline.isCancellation)
        #expect(!AppError.unknown("Boom").isCancellation)
    }

    @Test func otherErrorsBecomeUnknown() {
        struct Boom: Error {}
        if case .unknown = AppError(Boom()) {} else {
            Issue.record("Boom devrait devenir .unknown")
        }
    }
}

@MainActor
struct LoadStateTests {
    @Test func fromEmptyCollectionIsEmpty() {
        #expect(LoadState<[Int]>.from([]) == .empty)
        #expect(LoadState<[Int]>.from([1, 2]) == .loaded([1, 2]))
    }

    @Test func runCapturesValue() async {
        let state = await LoadState<Int>.run { 42 }
        #expect(state.value == 42)
        #expect(state.error == nil)
    }

    @Test func runCapturesErrorAsAppError() async {
        let state = await LoadState<Int>.run { throw AppError.offline }
        #expect(state.error == .offline)
        #expect(state.value == nil)
    }

    @Test func isLoadingOnlyWhenLoading() {
        #expect(LoadState<Int>.loading.isLoading)
        #expect(!LoadState<Int>.idle.isLoading)
        #expect(!LoadState<Int>.loaded(1).isLoading)
    }
}
