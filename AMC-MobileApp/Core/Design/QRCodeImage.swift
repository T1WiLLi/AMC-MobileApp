import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Matrice d'un code QR : un booléen par module (`true` = module foncé), sans zone de silence.
///
/// Générée une fois avec CoreImage (`CIFilter.qrCodeGenerator`), puis dessinée module par module :
/// le rendu reste net à toute taille, et les couleurs viennent du thème.
nonisolated struct QRMatrix: Sendable, Hashable {
    /// Niveau de correction d'erreur (L 7 %, M 15 %, Q 25 %, H 30 %).
    enum Correction: String, Sendable, CaseIterable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"
    }

    /// Nombre de modules par côté (21 pour la version 1, +4 par version).
    let size: Int
    /// Modules ligne par ligne, de haut en bas.
    let modules: [Bool]

    /// Zone de silence recommandée autour du code, en modules.
    static let quietZone = 2

    init?(_ payload: String, correction: Correction = .medium) {
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correction.rawValue
        guard let output = filter.outputImage else { return nil }

        // CoreImage rend 1 pixel par module, avec sa propre marge claire : on lit les pixels puis on la retire.
        let width = Int(output.extent.width)
        let height = Int(output.extent.height)
        guard width > 0, width == height else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        pixels.withUnsafeMutableBytes { buffer in
            context.render(
                output,
                toBitmap: buffer.baseAddress!,
                rowBytes: width,
                bounds: output.extent,
                format: .L8,
                colorSpace: nil
            )
        }

        let dark = pixels.map { $0 < 128 }
        let rows = (0..<height).filter { y in (0..<width).contains { dark[y * width + $0] } }
        let columns = (0..<width).filter { x in (0..<height).contains { dark[$0 * width + x] } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last,
              bottom - top == right - left else { return nil }

        let side = bottom - top + 1
        var trimmed = [Bool]()
        trimmed.reserveCapacity(side * side)
        for y in top...bottom {
            for x in left...right {
                trimmed.append(dark[y * width + x])
            }
        }
        self.size = side
        self.modules = trimmed
    }

    subscript(row: Int, column: Int) -> Bool {
        guard (0..<size).contains(row), (0..<size).contains(column) else { return false }
        return modules[row * size + column]
    }

    /// Image bitmap (noir sur blanc, zone de silence incluse), `scale` pixels par module. Sert au partage et aux tests.
    func cgImage(scale: Int = 8) -> CGImage? {
        let side = (size + 2 * Self.quietZone) * scale
        guard scale > 0,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        for row in 0..<size {
            for column in 0..<size where self[row, column] {
                // CoreGraphics a l'origine en bas à gauche.
                let x = (column + Self.quietZone) * scale
                let y = side - (row + Self.quietZone + 1) * scale
                context.fill(CGRect(x: x, y: y, width: scale, height: scale))
            }
        }
        return context.makeImage()
    }
}

/// Code QR dessiné en couleur Texte sur Surface, net à toute taille, toujours carré.
///
/// ```swift
/// QRCodeImage("grenier://part/GRN-4821", accessibilityLabel: "Code de cueillette de ta part")
///     .frame(maxWidth: 240)
/// ```
struct QRCodeImage: View {
    let matrix: QRMatrix?
    var accessibilityLabel: String
    var foreground: Color
    var background: Color
    @Environment(\.displayScale) private var displayScale

    init(
        _ payload: String,
        correction: QRMatrix.Correction = .medium,
        accessibilityLabel: String = String(localized: "Code QR"),
        foreground: Color = .texte,
        background: Color = .surface
    ) {
        self.matrix = QRMatrix(payload, correction: correction)
        self.accessibilityLabel = accessibilityLabel
        self.foreground = foreground
        self.background = background
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(background))
            guard let matrix else { return }
            let total = CGFloat(matrix.size + 2 * QRMatrix.quietZone)
            // Modules alignés sur les pixels physiques : pas de lignes fantômes entre deux modules.
            let scale = max(displayScale, 1)
            let module = max((min(canvasSize.width, canvasSize.height) / total * scale).rounded(.down) / scale, 1 / scale)
            let origin = CGPoint(
                x: ((canvasSize.width - module * CGFloat(matrix.size)) / 2 * scale).rounded() / scale,
                y: ((canvasSize.height - module * CGFloat(matrix.size)) / 2 * scale).rounded() / scale
            )
            var path = Path()
            for row in 0..<matrix.size {
                for column in 0..<matrix.size where matrix[row, column] {
                    path.addRect(CGRect(x: origin.x + CGFloat(column) * module,
                                        y: origin.y + CGFloat(row) * module,
                                        width: module, height: module))
                }
            }
            context.fill(path, with: .color(foreground))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }
}

#Preview("Clair") {
    QRCodeImage("grenier://part/GRN-4821", accessibilityLabel: "Code de cueillette de ta part")
        .frame(width: 240)
        .padding()
        .background(Color.surface, in: .rect(cornerRadius: 24))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
}

#Preview("Sombre") {
    QRCodeImage("grenier://part/GRN-4821")
        .frame(width: 120)
        .padding()
        .background(Color.surface, in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .preferredColorScheme(.dark)
}
