import SwiftUI
import Testing
@testable import AMC_MobileApp

@MainActor
struct TmpRevenueRender {
    @Test func render() async throws {
        for (name, data) in [("demo", FakeData.vendorRevenueDemo), ("base", FakeData.montreal)] {
            let model = VendorRevenueModel(repositories: .fake(behavior: .instant, data: data), vendorId: FakeData.ID.fermeRive)
            await model.load()
            let revenue = try #require(model.state.value)
            for (suffix, scheme, size) in [("light", ColorScheme.light, DynamicTypeSize.large), ("dark", .dark, .large), ("ax5", .light, .accessibility5)] {
                let view = VendorRevenueContent(revenue: revenue)
                    .frame(width: 393)
                    .background(Color.fond)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.uiImage)
                try image.pngData()!.write(to: URL(fileURLWithPath: "/tmp/t037-\(name)-\(suffix).png"))
            }
        }
    }
}
