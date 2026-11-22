import SwiftUI
import Vision
import VisionKit

/// T-181 : caméra qui lit le code QR d'une famille (`DataScannerViewController`, VisionKit).
/// Appelle `onCode` une fois par code lu ; un même code n'est pas relancé tant qu'il reste dans le cadre
/// (`PickupDesk` rejette de toute façon une deuxième remise).
struct QRScannerView: UIViewControllerRepresentable {
    /// Lecture possible : appareil compatible, caméra autorisée et non restreinte.
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var isPaused = false
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if isPaused {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var lastCode: String?

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, payload != lastCode else { continue }
                lastCode = payload
                onCode(payload)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            if allItems.isEmpty { lastCode = nil }
        }
    }
}
