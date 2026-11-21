import Testing
@testable import AMC_MobileApp

@MainActor
struct AppSmokeTests {
    @Test func rootViewBuilds() {
        _ = RootView().body
    }
}
