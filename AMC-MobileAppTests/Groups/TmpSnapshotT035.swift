import SwiftUI
import UIKit
import Testing
@testable import AMC_MobileApp

@MainActor
struct TmpSnapshotT035 {
    struct Screen: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NeighborhoodMapPreviewData.map()
                        .frame(height: 300)
                        .clipShape(.rect(cornerRadius: 24))
                    Text("Parc-Ex Ouest").font(.largeTitle.bold())
                    PickupPointCard(point: NeighborhoodMapPreviewData.pickupPoint, hostName: "Fatima", distanceMeters: 450,
                                    coordinate: NeighborhoodMapPreviewData.pickupCoordinate)
                }.padding()
            }.grenierBackground()
        }
    }

    func shoot(_ name: String, _ view: some View, style: UIUserInterfaceStyle) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(7))
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()!.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-willi-Documents-Source-AMC-MobileApp/11f39e84-f5a2-4b39-915a-c9ce86df8257/scratchpad/t035-\(name).png"))
        window.isHidden = true
    }

    @Test func snapshots() async throws {
        try await shoot("light", Screen(), style: .light)
        try await shoot("dark", Screen(), style: .dark)
        try await shoot("ax5", Screen().dynamicTypeSize(.accessibility5), style: .light)
        try await shoot("full", NeighborhoodMapPreviewData.map(mode: .interactive).ignoresSafeArea(), style: .dark)
    }
}
