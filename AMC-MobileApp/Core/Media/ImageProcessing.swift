// ImageProcessing.swift
// Recadrage et compression d'une image choisie dans Photos avant envoi (T-122).
// Lourd pour une photo de 12 Mpx : à appeler hors du fil principal (`Task.detached`).

import UIKit

nonisolated enum ImageProcessing {
    /// Plus basse qualité JPEG essayée avant de refuser l'image.
    static let minimumQuality: CGFloat = 0.3

    /// Rectangle (dans le repère de la cible) où dessiner la source pour la remplir en entier,
    /// centrée : ce qui dépasse est rogné (« aspect fill »).
    static func aspectFillRect(source: CGSize, target: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: target) }
        let scale = max(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Recadre au centre au format de `spec`, redimensionne, puis compresse en JPEG.
    /// La qualité baisse par pas de 0,1 tant que l'image dépasse `spec.targetBytes`, jusqu'à `minimumQuality` ;
    /// lève `.invalidInput` si ce n'est pas une image ou si elle reste trop lourde pour Firestore.
    static func prepare(_ imageData: Data, spec: ImageSpec) throws -> PreparedImage {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
            throw AppError.invalidInput("Ce fichier n'est pas une image lisible.")
        }
        return try prepare(image, spec: spec)
    }

    static func prepare(_ image: UIImage, spec: ImageSpec) throws -> PreparedImage {
        let target = spec.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: aspectFillRect(source: image.size, target: target))
        }
        var quality = spec.quality
        guard var jpeg = rendered.jpegData(compressionQuality: quality) else {
            throw AppError.invalidInput("Impossible de compresser cette image.")
        }
        while jpeg.count > spec.targetBytes, quality - 0.1 >= minimumQuality - 0.001 {
            quality -= 0.1
            if let smaller = rendered.jpegData(compressionQuality: quality) { jpeg = smaller }
        }
        guard PreparedImage.base64Size(of: jpeg.count) <= spec.maxBase64Bytes else {
            throw AppError.invalidInput("Cette image est trop lourde, même compressée. Essaie une autre photo.")
        }
        return PreparedImage(jpeg: jpeg, width: spec.width, height: spec.height)
    }
}
